import AppKit
@preconcurrency import ApplicationServices
import Combine
import MousePilotCore
import OSLog
import ServiceManagement

enum NavigationPage: String, CaseIterable, Identifiable {
    case mappings, settings
    var id: String { rawValue }
    var title: String {
        switch self { case .mappings: "제스처"; case .settings: "설정" }
    }
    var symbol: String {
        switch self { case .mappings: "computermouse"; case .settings: "slider.horizontal.3" }
    }
}

struct PermissionState: Equatable {
    var accessibility = false
    var inputMonitoring = false
    var postEvents = false
    // A filtering tap for mouse events uses Accessibility. ListenEvent preflight
    // describes Input Monitoring and must not gate our mouse-only event mask.
    var isReady: Bool { accessibility && postEvents }
}

struct CapturedInput: Identifiable, Equatable {
    let id = UUID()
    let owner: UUID
    let trigger: MouseTrigger
}

@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var configuration: AppConfiguration
    @Published var page = NavigationPage.mappings
    @Published private(set) var permissions = PermissionState()
    @Published private(set) var engineStatus = EngineStatus.stopped
    @Published private(set) var diagnostics = InputDiagnostics()
    @Published private(set) var devices: [MouseDevice] = []
    @Published private(set) var captureOwner: UUID?
    @Published private(set) var capturedInput: CapturedInput?
    @Published var notice: String?
    @Published var errorMessage: String?
    @Published private(set) var launchAtLogin = false
    @Published private(set) var outputStatus = "대기 중"
    private(set) var previousConfiguration: AppConfiguration?
    let storage: ConfigurationStore
    private var permissionTimer: Timer?
    private var captureTimer: Timer?
    private var refreshCount = 0
    private let runtimeLogger = Logger(subsystem: "dev.mousepilot.mac", category: "runtime")

    private lazy var engine = EventTapEngine(
        onStatus: { [weak self] status in
            guard let self, self.engineStatus != status else { return }
            self.engineStatus = status
            if self.diagnostics.isEnabled {
                self.runtimeLogger.info("Mouse input engine: \(String(describing: status), privacy: .public)")
            }
        },
        onActivity: { [weak self] activity in
            guard let self else { return }
            self.diagnostics.record(activity)
        },
        onCapture: { [weak self] trigger in
            guard let self, let owner = self.captureOwner else { return }
            self.capturedInput = .init(owner: owner, trigger: trigger)
            self.cancelCapture()
        },
        onError: { [weak self] message in self?.errorMessage = message },
        onOutput: { [weak self] status in
            guard let self, self.diagnostics.isEnabled else { return }
            self.outputStatus = status
        }
    )

    init(preview: Bool = false) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MousePilot", isDirectory: true)
        storage = ConfigurationStore(url: directory.appendingPathComponent("settings.json"))
        if preview {
            configuration = .init(isEnabled: true, reverseMouseScroll: true)
            permissions = .init(accessibility: true, inputMonitoring: false, postEvents: true)
            engineStatus = .running
            return
        }
        do {
            let result = try storage.load()
            configuration = result.configuration
            notice = result.warning
        } catch {
            configuration = .init()
            errorMessage = "설정을 읽지 못했습니다: \(error.localizedDescription)"
        }
        engine.configure(configuration)
        refreshPermissions()
        refreshDevices()
        launchAtLogin = SMAppService.mainApp.status == .enabled
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.refreshPermissions()
                self.refreshCount += 1
                if self.refreshCount.isMultiple(of: 5) { self.refreshDevices() }
            }
        }
    }

    var isActive: Bool { configuration.isEnabled && permissions.isReady && engineStatus == .running }
    var statusTitle: String {
        if !permissions.isReady { return "권한 필요" }
        if case .failed = engineStatus { return "연결 끊김" }
        if engineStatus == .starting { return "연결 중" }
        if isActive { return "사용 중" }
        return "일시 정지"
    }

    var activeMappingCount: Int { configuration.mappings.filter(\.isEnabled).count }

    func setEnabled(_ enabled: Bool) {
        var next = configuration
        next.isEnabled = enabled
        commit(next)
        if enabled && !permissions.isReady {
            notice = "손쉬운 사용을 허용하면 사용할 수 있습니다."
            page = .settings
        } else if enabled { reconnect() }
    }

    func setMappingEnabled(id: UUID, enabled: Bool) {
        var next = configuration
        guard let index = next.mappings.firstIndex(where: { $0.id == id }) else { return }
        next.mappings[index].isEnabled = enabled
        commit(next)
    }

    func setGestureThreshold(_ threshold: Double) {
        var next = configuration
        next.gestureThreshold = threshold
        commit(next)
    }

    func setReverseMouseScroll(_ enabled: Bool) {
        var next = configuration
        next.reverseMouseScroll = enabled
        commit(next)
    }

    @discardableResult
    func saveMapping(_ mapping: MouseMapping) -> Bool {
        var next = configuration
        if let index = next.mappings.firstIndex(where: { $0.id == mapping.id }) {
            next.mappings[index] = mapping
        } else { next.mappings.append(mapping) }
        return commit(next)
    }

    func deleteMapping(id: UUID) {
        var next = configuration
        next.mappings.removeAll { $0.id == id }
        if commit(next) { notice = "매핑을 삭제했습니다. 되돌리기로 복원할 수 있습니다." }
    }

    func applyPreset(_ preset: MousePreset) {
        var next = configuration
        next.mappings = preset.mappings
        if commit(next) { notice = "\(preset.title) 기본 매핑을 적용했습니다. 되돌리기로 이전 설정을 복원할 수 있습니다." }
    }

    func undo() {
        guard let previousConfiguration else { return }
        if commit(previousConfiguration) { notice = "이전 설정으로 되돌렸습니다." }
    }

    @discardableResult
    private func commit(_ next: AppConfiguration) -> Bool {
        do {
            try storage.save(next)
            previousConfiguration = configuration
            configuration = next
            engine.configure(next)
            return true
        } catch {
            errorMessage = "설정을 저장하지 못했습니다: \(error.localizedDescription)"
            return false
        }
    }

    func refreshPermissions() {
        let next = PermissionState(accessibility: AXIsProcessTrusted(),
                                   inputMonitoring: CGPreflightListenEventAccess(),
                                   postEvents: CGPreflightPostEventAccess())
        let becameReady = !permissions.isReady && next.isReady
        if permissions != next {
            permissions = next
            if diagnostics.isEnabled {
                runtimeLogger.info("Permissions: accessibility=\(next.accessibility), inputMonitoring=\(next.inputMonitoring), postEvents=\(next.postEvents)")
            }
        }
        if next.isReady {
            if engineStatus == .stopped || becameReady { engine.start() }
        } else if engineStatus == .running || engineStatus == .starting {
            cancelCapture()
            engine.stop()
        }
    }

    func reconnect() {
        refreshPermissions()
        if permissions.isReady { engine.start() }
    }

    func requestAccessibility() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        openSystemSettings("Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        openSystemSettings("Privacy_ListenEvent")
    }

    func openSystemSettings(_ anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }

    func openKeyboardSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func startCapture(owner: UUID) {
        refreshPermissions()
        guard permissions.isReady else {
            errorMessage = "버튼을 감지하려면 먼저 MousePilot의 손쉬운 사용 권한을 허용하세요."
            return
        }
        if case .failed(let reason) = engineStatus { errorMessage = reason; return }
        cancelCapture()
        capturedInput = nil
        captureOwner = owner
        engine.setCapturing(true)
        engine.start()
        captureTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.captureOwner != nil else { return }
                self.cancelCapture()
                self.notice = "버튼을 찾지 못했습니다. 다시 시도해 주세요."
            }
        }
    }

    func cancelCapture(owner: UUID? = nil) {
        if let owner, captureOwner != owner { return }
        captureTimer?.invalidate()
        captureTimer = nil
        captureOwner = nil
        engine.setCapturing(false)
    }

    func endCaptureSession(owner: UUID) {
        cancelCapture(owner: owner)
        if capturedInput?.owner == owner { capturedInput = nil }
    }

    func testMapping(_ mapping: MouseMapping) {
        guard permissions.isReady else {
            errorMessage = "동작을 테스트하려면 MousePilot의 손쉬운 사용 권한을 먼저 허용하세요."
            return
        }
        guard let shortcut = mapping.effectiveShortcut, shortcut.isValid else {
            errorMessage = "실행할 단축키를 먼저 지정하세요."
            return
        }
        engine.execute(shortcut)
    }

    var activities: [MouseActivity] { diagnostics.activities }
    var diagnosticsEnabled: Bool { diagnostics.isEnabled }

    func setDiagnosticsEnabled(_ enabled: Bool) {
        diagnostics.setEnabled(enabled)
        engine.setDiagnosticsEnabled(enabled)
        if !enabled { outputStatus = "대기 중" }
    }

    func clearActivities() { diagnostics.clear() }
    func refreshDevices() { devices = DeviceDiscovery.mice() }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                notice = "시스템 설정의 로그인 항목에서 MousePilot을 허용하세요."
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            errorMessage = "로그인 시 실행 설정을 바꾸지 못했습니다: \(error.localizedDescription)"
        }
    }

    func revealConfiguration() {
        do {
            if !FileManager.default.fileExists(atPath: storage.url.path) { try storage.save(configuration) }
            NSWorkspace.shared.activateFileViewerSelecting([storage.url])
        } catch { errorMessage = "설정 파일을 만들지 못했습니다: \(error.localizedDescription)" }
    }

    func copyDiagnostics() {
        let report = AppDiagnostics.report() + "\nengineStatus: \(String(describing: engineStatus))"
            + "\nkeyboardTransport: combinedSessionState / native modifier flags"
            + "\nkeyHoldMilliseconds: 40\nlastOutput: \(outputStatus)"
            + "\nreverseMouseScroll: \(configuration.reverseMouseScroll)"
            + "\nscrollFilter: discrete hardware wheel only / continuous and phased events unchanged"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        notice = "진단 정보를 복사했습니다."
    }

    func shutdown() { permissionTimer?.invalidate(); cancelCapture(); engine.stop() }
}

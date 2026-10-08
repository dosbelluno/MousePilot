import AppKit
import ApplicationServices
import MousePilotCore

extension Modifiers {
    init(cgFlags: CGEventFlags) {
        self.init(rawValue: 0)
        for (modifier, flag) in Self.flagPairs where cgFlags.contains(flag) { insert(modifier) }
    }

    var cgFlags: CGEventFlags {
        Self.flagPairs.reduce(into: CGEventFlags()) { flags, pair in
            if contains(pair.0) { flags.insert(pair.1) }
        }
    }

    private static let flagPairs: [(Modifiers, CGEventFlags)] = [
        (.control, .maskControl), (.option, .maskAlternate), (.shift, .maskShift),
        (.command, .maskCommand), (.function, .maskSecondaryFn)
    ]
}

enum EngineStatus: Equatable, Sendable {
    case stopped, starting, running, failed(String)
}

struct MouseActivity: Identifiable, Sendable {
    let id = UUID()
    let date = Date()
    let trigger: MouseTrigger
    let action: ActionKind?
    let shortcut: KeyboardShortcut?
    let captured: Bool
    var waitingForGesture = false
    var gestureCancelled = false
}

/// The event tap has its own run loop so UI work cannot stall mouse input.
/// Mutable state is protected by `lock`; all UI callbacks are delivered on the main actor.
final class EventTapEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var router = MouseRouter()
    private var diagnosticsEnabled = false
    private var requested = false
    private var worker: Thread?
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private let actionQueue = DispatchQueue(label: "dev.mousepilot.actions", qos: .userInteractive)

    let onStatus: @MainActor @Sendable (EngineStatus) -> Void
    let onActivity: @MainActor @Sendable (MouseActivity) -> Void
    let onCapture: @MainActor @Sendable (MouseTrigger) -> Void
    let onError: @MainActor @Sendable (String) -> Void
    let onOutput: (@MainActor @Sendable (String) -> Void)?

    init(onStatus: @escaping @MainActor @Sendable (EngineStatus) -> Void,
         onActivity: @escaping @MainActor @Sendable (MouseActivity) -> Void,
         onCapture: @escaping @MainActor @Sendable (MouseTrigger) -> Void,
         onError: @escaping @MainActor @Sendable (String) -> Void,
         onOutput: (@MainActor @Sendable (String) -> Void)? = nil) {
        self.onStatus = onStatus
        self.onActivity = onActivity
        self.onCapture = onCapture
        self.onError = onError
        self.onOutput = onOutput
    }

    func configure(_ configuration: AppConfiguration) {
        lock.withLock { router.configuration = configuration }
    }

    func setCapturing(_ capturing: Bool) {
        lock.withLock { router.isCapturing = capturing }
    }

    func setDiagnosticsEnabled(_ enabled: Bool) {
        lock.withLock { diagnosticsEnabled = enabled }
    }

    func start() {
        let shouldStart = lock.withLock {
            guard !requested, worker == nil else { return false }
            requested = true
            let thread = Thread { [weak self] in self?.run() }
            thread.name = "MousePilot event tap"
            thread.qualityOfService = .userInteractive
            worker = thread
            return true
        }
        guard shouldStart else { return }
        deliverStatus(.starting)
        lock.withLock { worker }?.start()
    }

    func stop() {
        let loop = lock.withLock {
            requested = false
            router.isCapturing = false
            return runLoop
        }
        if let loop {
            CFRunLoopStop(loop)
            CFRunLoopWakeUp(loop)
        }
    }

    private func run() {
        let types: [CGEventType] = [.otherMouseDown, .otherMouseUp,
                                    .otherMouseDragged, .mouseMoved, .scrollWheel]
        let mask = types.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard let newTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: mousePilotTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            lock.withLock { requested = false; worker = nil }
            deliverStatus(.failed("마우스 입력에 연결할 수 없습니다. 권한을 확인한 뒤 다시 연결하거나 앱을 재실행하세요."))
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            lock.withLock { requested = false; worker = nil }
            deliverStatus(.failed("입력 감지 실행 루프를 만들 수 없습니다."))
            return
        }

        let loop = CFRunLoopGetCurrent()!
        CFRunLoopAddSource(loop, source, .commonModes)
        let shouldRun = lock.withLock {
            tap = newTap
            runLoop = loop
            return requested
        }
        if shouldRun {
            CGEvent.tapEnable(tap: newTap, enable: true)
            deliverStatus(.running)
            // A bounded run also handles a stop requested just before the loop starts.
            while lock.withLock({ requested }) {
                CFRunLoopRunInMode(.defaultMode, 0.5, false)
            }
        }
        CGEvent.tapEnable(tap: newTap, enable: false)
        CFRunLoopRemoveSource(loop, source, .commonModes)
        CFMachPortInvalidate(newTap)
        lock.withLock {
            tap = nil; runLoop = nil; worker = nil; requested = false
            router.resetPressedButtons()
        }
        deliverStatus(.stopped)
    }

    fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // A stalled/disabled tap may have missed a release. Forget those stale presses.
            let currentTap = lock.withLock { () -> CFMachPort? in
                router.resetPressedButtons()
                return requested ? tap : nil
            }
            if let currentTap { CGEvent.tapEnable(tap: currentTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if event.getIntegerValueField(.eventSourceUserData) == KeyEventSender.eventMarker {
            return Unmanaged.passUnretained(event)
        }
        if type == .scrollWheel {
            let enabled = lock.withLock { router.configuration.isEnabled && router.configuration.reverseMouseScroll }
            let replacement = MouseScrollReverser.transform(event, enabled: enabled)
            if replacement === event { return Unmanaged.passUnretained(event) }
            // Transfer ownership of the newly allocated event to the event tap.
            return Unmanaged.passRetained(replacement)
        }
        let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
        let modifiers = Modifiers(cgFlags: event.flags)
        let deltaX = Double(event.getIntegerValueField(.mouseEventDeltaX))
        let deltaY = Double(event.getIntegerValueField(.mouseEventDeltaY))
        if type == .mouseMoved {
            let motion = lock.withLock { router.routeMovement(deltaX: deltaX, deltaY: deltaY) }
            return motion.suppress ? nil : Unmanaged.passUnretained(event)
        }
        let phase: MousePhase
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: phase = .down
        case .otherMouseUp: phase = .up
        case .otherMouseDragged: phase = .dragged
        default: return Unmanaged.passUnretained(event)
        }
        let result = lock.withLock { () -> RoutingResult in
            if phase == .dragged && router.hasPendingGesture {
                return router.routeMovement(deltaX: deltaX, deltaY: deltaY)
            }
            return router.route(button: button, modifiers: modifiers, phase: phase, deltaX: deltaX, deltaY: deltaY)
        }
        let collect = lock.withLock { diagnosticsEnabled }
        if collect && (phase == .down || result.gestureFinished) {
            let activity = MouseActivity(trigger: result.executedTrigger ?? .init(button: button, modifiers: modifiers),
                                         action: result.action, shortcut: result.shortcut,
                                         captured: result.capturedTrigger != nil,
                                         waitingForGesture: result.waitingForGesture,
                                         gestureCancelled: result.gestureFinished && result.action == nil)
            DispatchQueue.main.async { [onActivity] in onActivity(activity) }
        }
        if let trigger = result.capturedTrigger {
            DispatchQueue.main.async { [onCapture] in onCapture(trigger) }
        }
        if let shortcut = result.shortcut { execute(shortcut) }
        return result.suppress ? nil : Unmanaged.passUnretained(event)
    }

    func execute(_ shortcut: KeyboardShortcut) {
        actionQueue.async { [onError, onOutput] in
            do {
                try KeyEventSender.send(shortcut)
                if self.lock.withLock({ self.diagnosticsEnabled }) {
                    DispatchQueue.main.async { onOutput?("전송됨") }
                }
            }
            catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    onOutput?("전송 실패: \(message)")
                    onError(message)
                }
            }
        }
    }

    private func deliverStatus(_ status: EngineStatus) {
        DispatchQueue.main.async { [onStatus] in onStatus(status) }
    }
}

private func mousePilotTapCallback(proxy: CGEventTapProxy, type: CGEventType,
                                   event: CGEvent, userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    return Unmanaged<EventTapEngine>.fromOpaque(userInfo).takeUnretainedValue().handle(type: type, event: event)
}

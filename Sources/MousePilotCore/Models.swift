import Foundation

public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)
    public static let function = Modifiers(rawValue: 1 << 4)
    public static let supported: Modifiers = [.control, .option, .shift, .command, .function]

    public var symbols: String {
        [(Self.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘"), (.function, "fn ")]
            .filter { contains($0.0) }.map(\.1).joined()
    }
}

public enum MouseGesture: String, Codable, CaseIterable, Identifiable, Sendable {
    case click, swipeLeft, swipeRight, swipeUp, swipeDown
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .click: "짧게 클릭"
        case .swipeLeft: "누른 채 왼쪽으로 이동"
        case .swipeRight: "누른 채 오른쪽으로 이동"
        case .swipeUp: "누른 채 위로 이동"
        case .swipeDown: "누른 채 아래로 이동"
        }
    }
    public var arrow: String {
        switch self { case .click: ""; case .swipeLeft: "←"; case .swipeRight: "→"; case .swipeUp: "↑"; case .swipeDown: "↓" }
    }
    public var symbol: String {
        switch self { case .click: "computermouse"; case .swipeLeft: "arrow.left"; case .swipeRight: "arrow.right"; case .swipeUp: "arrow.up"; case .swipeDown: "arrow.down" }
    }
}

public struct MouseTrigger: Codable, Hashable, Sendable {
    /// Quartz uses 0 for left, 1 for right, 2 for middle, and 3+ for extra buttons.
    public var button: Int
    public var modifiers: Modifiers
    public var gesture: MouseGesture

    public init(button: Int, modifiers: Modifiers = [], gesture: MouseGesture = .click) {
        self.button = button
        self.modifiers = modifiers
        self.gesture = gesture
    }

    private enum CodingKeys: String, CodingKey { case button, modifiers, gesture }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        button = try values.decode(Int.self, forKey: .button)
        modifiers = try values.decode(Modifiers.self, forKey: .modifiers)
        gesture = try values.decodeIfPresent(MouseGesture.self, forKey: .gesture) ?? .click
    }

    public var isMappable: Bool {
        (2...31).contains(button) && modifiers.subtracting(.supported).isEmpty
    }

    public var buttonName: String {
        switch button {
        case 0: "왼쪽 클릭"
        case 1: "오른쪽 클릭"
        case 2: "휠 버튼"
        case 3: "뒤로 버튼 · 4"
        case 4: "앞으로 버튼 · 5"
        default: "추가 버튼 · \(button + 1)"
        }
    }

    public var displayName: String {
        let input = gesture == .click ? (button == 2 ? "휠 클릭" : buttonName) : "\(buttonName) · \(gesture.arrow)"
        return modifiers.isEmpty ? input : "\(modifiers.symbols) + \(input)"
    }
}

public struct KeyboardShortcut: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: Modifiers
    public var keyLabel: String

    public init(keyCode: UInt16, modifiers: Modifiers = [], keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    public var displayName: String { modifiers.symbols + keyLabel }
    public var isValid: Bool {
        keyCode <= 127 && !Self.modifierKeyCodes.contains(keyCode)
            && modifiers.subtracting(.supported).isEmpty
            && !keyLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && keyLabel.count <= 40
    }

    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
}

public enum ActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case missionControl, desktopLeft, desktopRight, appWindows, showDesktop
    case previousApp, spotlight, browserBack, browserForward, customShortcut

    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .missionControl: "Mission Control"
        case .desktopLeft: "왼쪽 데스크톱"
        case .desktopRight: "오른쪽 데스크톱"
        case .appWindows: "앱 창 보기"
        case .showDesktop: "데스크톱 보기"
        case .previousApp: "이전 앱"
        case .spotlight: "Spotlight 검색"
        case .browserBack: "뒤로 가기"
        case .browserForward: "앞으로 가기"
        case .customShortcut: "사용자 지정 단축키"
        }
    }

    public var symbol: String {
        switch self {
        case .missionControl: "rectangle.3.group"
        case .desktopLeft: "rectangle.lefthalf.inset.filled.arrow.left"
        case .desktopRight: "rectangle.righthalf.inset.filled.arrow.right"
        case .appWindows: "macwindow.on.rectangle"
        case .showDesktop: "desktopcomputer"
        case .previousApp: "arrow.triangle.swap"
        case .spotlight: "magnifyingglass"
        case .browserBack: "arrow.left"
        case .browserForward: "arrow.right"
        case .customShortcut: "keyboard"
        }
    }

    public var defaultShortcut: KeyboardShortcut? {
        switch self {
        case .missionControl: .init(keyCode: 126, modifiers: .control, keyLabel: "↑")
        case .desktopLeft: .init(keyCode: 123, modifiers: .control, keyLabel: "←")
        case .desktopRight: .init(keyCode: 124, modifiers: .control, keyLabel: "→")
        case .appWindows: .init(keyCode: 125, modifiers: .control, keyLabel: "↓")
        case .showDesktop: .init(keyCode: 103, modifiers: .function, keyLabel: "F11")
        case .previousApp: .init(keyCode: 48, modifiers: .command, keyLabel: "Tab")
        case .spotlight: .init(keyCode: 49, modifiers: .command, keyLabel: "Space")
        case .browserBack: .init(keyCode: 33, modifiers: .command, keyLabel: "[")
        case .browserForward: .init(keyCode: 30, modifiers: .command, keyLabel: "]")
        case .customShortcut: nil
        }
    }
}

public struct MouseMapping: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var trigger: MouseTrigger
    public var action: ActionKind
    public var shortcutOverride: KeyboardShortcut?
    public var isEnabled: Bool

    public init(id: UUID = UUID(), trigger: MouseTrigger, action: ActionKind,
                shortcutOverride: KeyboardShortcut? = nil, isEnabled: Bool = true) {
        self.id = id
        self.trigger = trigger
        self.action = action
        self.shortcutOverride = shortcutOverride
        self.isEnabled = isEnabled
    }

    public var effectiveShortcut: KeyboardShortcut? { shortcutOverride ?? action.defaultShortcut }
    public var isValid: Bool { trigger.isMappable && effectiveShortcut?.isValid == true }
}

public enum MousePreset: String, CaseIterable, Identifiable, Sendable {
    case wheelGestures, fiveButton, threeButton
    public var id: String { rawValue }
    public var title: String {
        switch self { case .wheelGestures: "휠 제스처"; case .fiveButton: "옆면 버튼 사용"; case .threeButton: "보조 키 사용" }
    }
    public var mappings: [MouseMapping] {
        var result = [MouseMapping(trigger: .init(button: 2), action: .missionControl)]
        if self == .wheelGestures {
            result += [
                .init(trigger: .init(button: 2, gesture: .swipeLeft), action: .desktopLeft),
                .init(trigger: .init(button: 2, gesture: .swipeRight), action: .desktopRight),
                .init(trigger: .init(button: 2, gesture: .swipeUp), action: .missionControl),
                .init(trigger: .init(button: 2, gesture: .swipeDown), action: .appWindows)
            ]
        } else if self == .fiveButton {
            result += [
                .init(trigger: .init(button: 3), action: .desktopLeft),
                .init(trigger: .init(button: 4), action: .desktopRight)
            ]
        } else {
            result += [
                .init(trigger: .init(button: 2, modifiers: .option), action: .desktopLeft),
                .init(trigger: .init(button: 2, modifiers: .shift), action: .desktopRight)
            ]
        }
        return result
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 2
    public var schemaVersion: Int
    public var isEnabled: Bool
    public var mappings: [MouseMapping]
    public var gestureThreshold: Double
    public var reverseMouseScroll: Bool

    public init(isEnabled: Bool = false, mappings: [MouseMapping] = MousePreset.wheelGestures.mappings,
                gestureThreshold: Double = 60, reverseMouseScroll: Bool = false) {
        schemaVersion = Self.currentSchemaVersion
        self.isEnabled = isEnabled
        self.mappings = mappings
        self.gestureThreshold = gestureThreshold
        self.reverseMouseScroll = reverseMouseScroll
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, isEnabled, mappings, gestureThreshold, reverseMouseScroll }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        mappings = try values.decode([MouseMapping].self, forKey: .mappings)
        gestureThreshold = try values.decodeIfPresent(Double.self, forKey: .gestureThreshold) ?? 60
        reverseMouseScroll = try values.decodeIfPresent(Bool.self, forKey: .reverseMouseScroll) ?? false
    }

    /// Converts desktop side buttons to wheel gestures on the next app launch.
    public func migratedToCurrent() -> AppConfiguration {
        guard schemaVersion == 1 else { return self }
        var next = self
        next.schemaVersion = Self.currentSchemaVersion
        next.mappings.removeAll {
            [3, 4].contains($0.trigger.button) && $0.trigger.modifiers.isEmpty
                && $0.trigger.gesture == .click && [.desktopLeft, .desktopRight].contains($0.action)
        }
        for mapping in MousePreset.wheelGestures.mappings where !next.mappings.contains(where: { $0.trigger == mapping.trigger }) {
            next.mappings.append(mapping)
        }
        return next
    }

    public func validated() throws -> AppConfiguration {
        guard schemaVersion == 1 || schemaVersion == Self.currentSchemaVersion else { throw ConfigurationError.unsupportedVersion }
        guard gestureThreshold.isFinite && (16...240).contains(gestureThreshold) else { throw ConfigurationError.invalidGestureThreshold }
        guard mappings.count <= 128 else { throw ConfigurationError.tooManyMappings }
        var triggers = Set<MouseTrigger>()
        var identifiers = Set<UUID>()
        for mapping in mappings {
            guard mapping.isValid else { throw ConfigurationError.invalidMapping }
            guard triggers.insert(mapping.trigger).inserted,
                  identifiers.insert(mapping.id).inserted else {
                throw ConfigurationError.duplicateMapping
            }
        }
        return self
    }
}

public enum ConfigurationError: Error, LocalizedError {
    case unsupportedVersion, tooManyMappings, invalidMapping, duplicateMapping, invalidGestureThreshold
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: "이 버전에서 읽을 수 없는 설정입니다."
        case .tooManyMappings: "매핑은 최대 128개까지 저장할 수 있습니다."
        case .invalidMapping: "버튼 또는 단축키 설정이 올바르지 않습니다."
        case .duplicateMapping: "같은 버튼 조합이 이미 등록되어 있습니다."
        case .invalidGestureThreshold: "제스처 인식 거리는 16에서 240 사이여야 합니다."
        }
    }
}

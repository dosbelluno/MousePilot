import CoreGraphics
import Foundation
import MousePilotCore

struct PhysicalModifierState {
    var keys: Set<CGKeyCode> = []
    var capsLock = false
}

struct KeyboardEventStep {
    let event: CGEvent
    let delayAfter: TimeInterval
}

struct PreparedKeyboardEvents {
    // Keep the source alive for the entire transmission. Login-session events
    // use the shared session table, not a short-lived private state table.
    let source: CGEventSource
    let steps: [KeyboardEventStep]
    let retainedPhysicalKeys: Set<CGKeyCode>
    let nativeModifierFlags: [CGKeyCode: CGEventFlags]
    let recoveryDown: [CGKeyCode: CGEvent]
    let recoveryUp: [CGKeyCode: CGEvent]

    func flags(for keys: Set<CGKeyCode>, capsLock: Bool) -> CGEventFlags {
        keys.reduce(into: capsLock ? CGEventFlags.maskAlphaShift : CGEventFlags()) {
            $0.formUnion(nativeModifierFlags[$1] ?? [])
        }
    }
}

enum KeyEventSender {
    static let eventMarker: Int64 = 0x4D50494C4F54
    static let modifierKeys: [(Modifiers, CGKeyCode)] = [
        (.control, 59), (.option, 58), (.shift, 56), (.command, 55), (.function, 63)
    ]
    static let physicalModifierKeys: [(Modifiers, CGKeyCode)] = [
        (.control, 59), (.control, 62), (.option, 58), (.option, 61),
        (.shift, 56), (.shift, 60), (.command, 55), (.command, 54), (.function, 63)
    ]

    static func physicalState() -> PhysicalModifierState {
        .init(keys: Set(physicalModifierKeys.compactMap {
            CGEventSource.keyState(.hidSystemState, key: $0.1) ? $0.1 : nil
        }), capsLock: CGEventSource.flagsState(.hidSystemState).contains(.maskAlphaShift))
    }

    /// Builds real CGEvents but does not post them. Tests exercise this exact
    /// production path with a fake transport, without changing the desktop.
    static func prepare(_ shortcut: KeyboardShortcut,
                        physical: PhysicalModifierState = .init()) throws -> PreparedKeyboardEvents {
        guard shortcut.isValid else { throw SendError.invalidShortcut }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let template = CGEventSource(stateID: .privateState) else { throw SendError.creationFailed }
        source.localEventsSuppressionInterval = 0
        source.userData = eventMarker

        var nativeFlags: [CGKeyCode: CGEventFlags] = [:]
        for (_, key) in physicalModifierKeys {
            guard let native = CGEvent(keyboardEventSource: template, virtualKey: key, keyDown: true) else {
                throw SendError.creationFailed
            }
            // A native Control press carries both maskControl and the left/right
            // device bit. Replacing it with maskControl alone loses information.
            nativeFlags[key] = native.flags
        }
        let knownKeys = Set(nativeFlags.keys)
        let original = physical.keys.intersection(knownKeys)
        var held = original
        var introduced: [CGKeyCode] = []
        var steps: [KeyboardEventStep] = []

        func flags(_ keys: Set<CGKeyCode>) -> CGEventFlags {
            keys.reduce(into: physical.capsLock ? CGEventFlags.maskAlphaShift : CGEventFlags()) {
                $0.formUnion(nativeFlags[$1] ?? [])
            }
        }
        func make(_ key: CGKeyCode, down: Bool, heldKeys: Set<CGKeyCode>) throws -> CGEvent {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down),
                  let native = CGEvent(keyboardEventSource: template, virtualKey: key, keyDown: down) else {
                throw SendError.creationFailed
            }
            // Preserve intrinsic arrow/function/keypad bits from CoreGraphics.
            // Modifier events keep their native flagsChanged type as well.
            let intrinsic: CGEventFlags = knownKeys.contains(key) ? [] : native.flags
            event.flags = flags(heldKeys).union(intrinsic)
            event.setIntegerValueField(.eventSourceUserData, value: eventMarker)
            return event
        }
        func append(_ key: CGKeyCode, down: Bool, delay: TimeInterval = 0.006) throws {
            steps.append(.init(event: try make(key, down: down, heldKeys: held), delayAfter: delay))
        }

        for (modifier, key) in physicalModifierKeys where original.contains(key) && !shortcut.modifiers.contains(modifier) {
            held.remove(key)
            try append(key, down: false)
        }
        for (modifier, preferredKey) in modifierKeys where shortcut.modifiers.contains(modifier) {
            let alreadyHeld = physicalModifierKeys.contains { $0.0 == modifier && held.contains($0.1) }
            if !alreadyHeld {
                held.insert(preferredKey)
                introduced.append(preferredKey)
                try append(preferredKey, down: true)
            }
        }
        try append(shortcut.keyCode, down: true, delay: 0.040)
        try append(shortcut.keyCode, down: false)
        for key in introduced.reversed() {
            held.remove(key)
            try append(key, down: false)
        }

        // Preallocate recovery events so a later allocation error cannot leave
        // a synthetic modifier pressed. Re-sample physical keys at the end.
        var recoveryDown: [CGKeyCode: CGEvent] = [:]
        var recoveryUp: [CGKeyCode: CGEvent] = [:]
        for (_, key) in physicalModifierKeys {
            recoveryDown[key] = try make(key, down: true, heldKeys: [])
            recoveryUp[key] = try make(key, down: false, heldKeys: [])
        }
        return .init(source: source, steps: steps, retainedPhysicalKeys: held,
                     nativeModifierFlags: nativeFlags, recoveryDown: recoveryDown, recoveryUp: recoveryUp)
    }

    /// Transport is injected for tests. Production is the only caller that
    /// supplies CGEvent.post; tests collect events and requested delays.
    static func transmit(_ prepared: PreparedKeyboardEvents,
                         physicalNow: () -> PhysicalModifierState,
                         post: (CGEvent) -> Void,
                         wait: (TimeInterval) -> Void) {
        withExtendedLifetime(prepared.source) {
            for step in prepared.steps {
                step.event.timestamp = DispatchTime.now().uptimeNanoseconds
                post(step.event)
                wait(step.delayAfter)
            }
            let physical = physicalNow()
            let actual = physical.keys.intersection(Set(prepared.nativeModifierFlags.keys))
            var held = prepared.retainedPhysicalKeys
            for key in held.subtracting(actual).sorted() {
                held.remove(key)
                if let event = prepared.recoveryUp[key] {
                    event.flags = prepared.flags(for: held, capsLock: physical.capsLock)
                    event.timestamp = DispatchTime.now().uptimeNanoseconds
                    post(event)
                }
            }
            for key in actual.subtracting(held).sorted() {
                held.insert(key)
                if let event = prepared.recoveryDown[key] {
                    event.flags = prepared.flags(for: held, capsLock: physical.capsLock)
                    event.timestamp = DispatchTime.now().uptimeNanoseconds
                    post(event)
                }
            }
        }
    }

    static func send(_ shortcut: KeyboardShortcut) throws {
        guard CGPreflightPostEventAccess() else { throw SendError.permissionDenied }
        let prepared = try prepare(shortcut, physical: physicalState())
        transmit(prepared, physicalNow: physicalState,
                 post: { $0.post(tap: .cghidEventTap) }, wait: { Thread.sleep(forTimeInterval: $0) })
    }

    enum SendError: LocalizedError {
        case permissionDenied, invalidShortcut, creationFailed
        var errorDescription: String? {
            switch self {
            case .permissionDenied: "단축키를 보내려면 손쉬운 사용 권한이 필요합니다."
            case .invalidShortcut: "올바른 단축키를 먼저 지정하세요."
            case .creationFailed: "단축키 이벤트를 만들 수 없습니다. 다시 시도해 주세요."
            }
        }
    }
}

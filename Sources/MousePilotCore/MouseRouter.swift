import Foundation

public enum MousePhase: Sendable { case down, up, dragged }

public struct RoutingResult: Equatable, Sendable {
    public var suppress: Bool
    public var shortcut: KeyboardShortcut?
    public var action: ActionKind?
    public var capturedTrigger: MouseTrigger?
    public var executedTrigger: MouseTrigger?
    public var waitingForGesture: Bool
    public var gestureFinished: Bool

    public init(suppress: Bool = false, shortcut: KeyboardShortcut? = nil,
                action: ActionKind? = nil, capturedTrigger: MouseTrigger? = nil,
                executedTrigger: MouseTrigger? = nil, waitingForGesture: Bool = false,
                gestureFinished: Bool = false) {
        self.suppress = suppress
        self.shortcut = shortcut
        self.action = action
        self.capturedTrigger = capturedTrigger
        self.executedTrigger = executedTrigger
        self.waitingForGesture = waitingForGesture
        self.gestureFinished = gestureFinished
    }
}

/// The engine owns this state on its input thread and serializes updates.
public struct MouseRouter: Sendable {
    public var configuration: AppConfiguration {
        didSet { if !configuration.isEnabled { cancelPendingGestures() } }
    }
    public var isCapturing = false {
        didSet { if isCapturing { cancelPendingGestures() } }
    }
    private enum Press: Sendable {
        case normal(suppress: Bool)
        case gesture(GesturePress)
    }
    private struct GesturePress: Sendable {
        let trigger: MouseTrigger
        let mappings: [MouseMapping]
        let threshold: Double
        var x = 0.0
        var y = 0.0
        var maximumDistance = 0.0
        var direction: MouseGesture?
        var cancelled = false

        mutating func move(x deltaX: Double, y deltaY: Double) {
            guard deltaX.isFinite, deltaY.isFinite, !cancelled else { return }
            x += deltaX; y += deltaY
            maximumDistance = max(maximumDistance, hypot(x, y))
            guard direction == nil, max(abs(x), abs(y)) >= threshold else { return }
            direction = abs(x) >= abs(y) ? (x < 0 ? .swipeLeft : .swipeRight) : (y < 0 ? .swipeUp : .swipeDown)
        }
    }
    private var heldButtons: [Int: Press] = [:]

    public init(configuration: AppConfiguration = .init()) { self.configuration = configuration }

    public var hasPendingGesture: Bool {
        heldButtons.values.contains { if case .gesture = $0 { return true }; return false }
    }

    public mutating func route(button: Int, modifiers: Modifiers, phase: MousePhase,
                               deltaX: Double = 0, deltaY: Double = 0) -> RoutingResult {
        guard (2...31).contains(button) else { return .init() }
        switch phase {
        case .up:
            guard let press = heldButtons.removeValue(forKey: button) else { return .init() }
            switch press {
            case .normal(let suppress): return .init(suppress: suppress)
            case .gesture(let gesture): return finish(gesture)
            }
        case .dragged:
            guard let press = heldButtons[button] else { return .init() }
            switch press {
            case .normal(let suppress): return .init(suppress: suppress)
            case .gesture(var gesture):
                gesture.move(x: deltaX, y: deltaY)
                heldButtons[button] = .gesture(gesture)
                return .init(suppress: true)
            }
        case .down:
            if let held = heldButtons[button] {
                switch held {
                case .normal(let suppress): return .init(suppress: suppress)
                case .gesture: return .init(suppress: true)
                }
            }
            let trigger = MouseTrigger(button: button, modifiers: modifiers.intersection(.supported))
            if isCapturing {
                isCapturing = false
                heldButtons[button] = .normal(suppress: true)
                return .init(suppress: true, capturedTrigger: trigger)
            }
            let matching = configuration.mappings.filter {
                $0.isEnabled && $0.isValid && $0.trigger.button == button && $0.trigger.modifiers == trigger.modifiers
            }
            if configuration.isEnabled && matching.contains(where: { $0.trigger.gesture != .click }) {
                heldButtons[button] = .gesture(.init(trigger: trigger, mappings: matching, threshold: configuration.gestureThreshold))
                return .init(suppress: true, waitingForGesture: true)
            }
            guard configuration.isEnabled,
                  let mapping = matching.first(where: { $0.trigger.gesture == .click }),
                  let shortcut = mapping.effectiveShortcut else {
                heldButtons[button] = .normal(suppress: false)
                return .init()
            }
            heldButtons[button] = .normal(suppress: true)
            return .init(suppress: true, shortcut: shortcut, action: mapping.action, executedTrigger: mapping.trigger)
        }
    }

    /// Drivers can emit mouseMoved as well as otherMouseDragged while held.
    public mutating func routeMovement(deltaX: Double, deltaY: Double) -> RoutingResult {
        var handled = false
        for button in Array(heldButtons.keys) {
            if case .gesture(var gesture) = heldButtons[button] {
                gesture.move(x: deltaX, y: deltaY)
                heldButtons[button] = .gesture(gesture)
                handled = true
            }
        }
        return .init(suppress: handled)
    }

    private func finish(_ gesture: GesturePress) -> RoutingResult {
        let cancelled = RoutingResult(suppress: true, gestureFinished: true)
        guard !gesture.cancelled, configuration.isEnabled, !isCapturing else { return cancelled }
        let motion: MouseGesture
        if let direction = gesture.direction { motion = direction }
        else if gesture.maximumDistance <= min(10, gesture.threshold / 3) { motion = .click }
        else { return cancelled }
        guard let mapping = gesture.mappings.first(where: { $0.trigger.gesture == motion }),
              configuration.mappings.contains(mapping), let shortcut = mapping.effectiveShortcut else { return cancelled }
        return .init(suppress: true, shortcut: shortcut, action: mapping.action,
                     executedTrigger: mapping.trigger, gestureFinished: true)
    }

    private mutating func cancelPendingGestures() {
        for button in Array(heldButtons.keys) {
            if case .gesture(var gesture) = heldButtons[button] {
                gesture.cancelled = true
                heldButtons[button] = .gesture(gesture)
            }
        }
    }

    public mutating func resetPressedButtons() { heldButtons.removeAll() }
}

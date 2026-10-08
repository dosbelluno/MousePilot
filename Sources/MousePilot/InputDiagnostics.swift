import Foundation

/// A temporary, opt-in buffer. Normal input handling never populates it.
struct InputDiagnostics {
    private(set) var isEnabled = false
    private(set) var activities: [MouseActivity] = []

    mutating func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if !enabled { activities.removeAll(keepingCapacity: false) }
    }

    mutating func record(_ activity: MouseActivity) {
        guard isEnabled else { return }
        activities.insert(activity, at: 0)
        if activities.count > 40 { activities.removeLast(activities.count - 40) }
    }

    mutating func clear() { activities.removeAll(keepingCapacity: false) }
}

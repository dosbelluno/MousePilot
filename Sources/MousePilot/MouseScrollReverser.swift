import CoreGraphics
import Foundation

/// Only discrete hardware wheel events qualify. Continuous/pixel scrolling,
/// touch phases, momentum, and software-generated events are preserved.
enum MouseScrollReverser {
    static let integerFields: [CGEventField] = [
        .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
        .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2
    ]
    static let fixedFields: [CGEventField] = [
        .scrollWheelEventFixedPtDeltaAxis1, .scrollWheelEventFixedPtDeltaAxis2
    ]

    static func isHardwareWheel(_ event: CGEvent) -> Bool {
        event.type == .scrollWheel
            && event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0
            && event.getIntegerValueField(.scrollWheelEventScrollPhase) == 0
            && event.getIntegerValueField(.scrollWheelEventMomentumPhase) == 0
            && event.getIntegerValueField(.eventSourceUnixProcessID) == 0
    }

    /// The replacement is returned through the existing tap. No input is posted
    /// and no system preferences are changed. A fresh Quartz scroll event also
    /// avoids carrying an attached HID payload with the old, unreversed deltas.
    static func transform(_ event: CGEvent, enabled: Bool) -> CGEvent {
        guard enabled, isHardwareWheel(event) else { return event }
        let integers = integerFields.map { event.getIntegerValueField($0) }
        let fixed = fixedFields.map { event.getDoubleValueField($0) }
        guard integers.allSatisfy({ $0 > Int64(Int32.min) && $0 <= Int64(Int32.max) }),
              fixed.allSatisfy({ $0.isFinite && abs($0) < 32768 }) else { return event }
        let thirdAxis = event.getIntegerValueField(.scrollWheelEventDeltaAxis3)
        guard let third = Int32(exactly: thirdAxis),
              let replacement = CGEvent(scrollWheelEvent2Source: CGEventSource(event: event),
                units: .line, wheelCount: 3, wheel1: Int32(-integers[0]),
                wheel2: Int32(-integers[1]), wheel3: third) else { return event }

        for (field, value) in zip(integerFields, integers) {
            replacement.setIntegerValueField(field, value: -value)
        }
        for (field, value) in zip(fixedFields, fixed) {
            replacement.setDoubleValueField(field, value: -value)
        }
        // Preserve location, modifiers, acceleration/count metadata, and the
        // unused third axis; only vertical and horizontal directions change.
        replacement.location = event.location
        replacement.flags = event.flags
        replacement.timestamp = event.timestamp
        for field in [CGEventField.scrollWheelEventScrollCount, .scrollWheelEventInstantMouser,
                      .scrollWheelEventPointDeltaAxis3, .eventSourceUserData] {
            replacement.setIntegerValueField(field, value: event.getIntegerValueField(field))
        }
        replacement.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis3,
                                       value: event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis3))
        return replacement
    }
}

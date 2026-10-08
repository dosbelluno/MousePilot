import CoreGraphics
import Foundation
import MousePilotCore
import XCTest
@testable import MousePilot

final class MouseScrollReverserTests: XCTestCase {
    private func wheel() -> CGEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                            wheelCount: 3, wheel1: 3, wheel2: -2, wheel3: 7)!
        // Fixtures emulate hardware metadata; no event is ever posted.
        event.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 0)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 0)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 33)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -22)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 1.5)
        event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -2.25)
        return event
    }

    func testHardwareWheelReversesAllDeltaRepresentationsOnBothAxes() {
        let input = wheel()
        let output = MouseScrollReverser.transform(input, enabled: true)
        XCTAssertFalse(input === output)
        for field in MouseScrollReverser.integerFields {
            XCTAssertEqual(output.getIntegerValueField(field), -input.getIntegerValueField(field))
        }
        for field in MouseScrollReverser.fixedFields {
            XCTAssertEqual(output.getDoubleValueField(field), -input.getDoubleValueField(field))
        }
        XCTAssertEqual(input.getIntegerValueField(.scrollWheelEventDeltaAxis1), 3)
        XCTAssertEqual(output.getIntegerValueField(.scrollWheelEventIsContinuous), 0)
    }

    func testTrackpadContinuousScrollingIsPreservedExactly() {
        let input = wheel()
        input.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        let before = input.data as Data?
        let output = MouseScrollReverser.transform(input, enabled: true)
        XCTAssertTrue(input === output)
        XCTAssertEqual(output.data as Data?, before)
    }

    func testTouchPhasesAndMomentumArePreservedEvenIfContinuousBitIsMissing() {
        let cases: [(CGEventField, [Int64])] = [
            (.scrollWheelEventScrollPhase, [1, 2, 4, 8, 16, 128]),
            (.scrollWheelEventMomentumPhase, [1, 2, 3, 4, 8])
        ]
        for (field, phases) in cases {
            for phase in phases {
                let input = wheel()
                input.setIntegerValueField(field, value: phase)
                XCTAssertNotEqual(input.getIntegerValueField(field), 0, "Fixture must encode a real phase")
                let before = input.data as Data?
                XCTAssertTrue(MouseScrollReverser.transform(input, enabled: true) === input)
                XCTAssertEqual(input.data as Data?, before)
            }
        }
    }

    func testDisabledOptionAndSoftwareGeneratedScrollArePreserved() {
        let input = wheel()
        XCTAssertTrue(MouseScrollReverser.transform(input, enabled: false) === input)
        input.setIntegerValueField(.eventSourceUnixProcessID, value: 42)
        XCTAssertTrue(MouseScrollReverser.transform(input, enabled: true) === input)
    }

    func testModifiersPositionTimeAndThirdAxisArePreserved() {
        let input = wheel()
        input.flags = [.maskShift, .maskAlternate]
        input.location = CGPoint(x: 123, y: 456)
        input.timestamp = 123456789
        input.setIntegerValueField(.scrollWheelEventScrollCount, value: 5)
        input.setIntegerValueField(.eventSourceUserData, value: 123)
        let output = MouseScrollReverser.transform(input, enabled: true)
        XCTAssertEqual(output.flags, input.flags)
        XCTAssertEqual(output.location, input.location)
        XCTAssertEqual(output.timestamp, input.timestamp)
        for field in [CGEventField.scrollWheelEventDeltaAxis3, .scrollWheelEventPointDeltaAxis3,
                      .scrollWheelEventScrollCount, .eventSourceUserData] {
            XCTAssertEqual(output.getIntegerValueField(field), input.getIntegerValueField(field))
        }
        XCTAssertEqual(output.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis3),
                       input.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis3))
    }

    func testUnrelatedInputAndUnsafeDeltasPassThrough() {
        let input = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                            mouseCursorPosition: .zero, mouseButton: .left)!
        XCTAssertTrue(MouseScrollReverser.transform(input, enabled: true) === input)
        let invalid = wheel()
        invalid.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(Int32.min))
        XCTAssertTrue(MouseScrollReverser.transform(invalid, enabled: true) === invalid)
    }

    func testPreferencePersistsAndOldSettingsDefaultToDisabledWithoutChangingMappings() throws {
        let config = AppConfiguration(isEnabled: true, gestureThreshold: 84, reverseMouseScroll: true)
        let encoded = try JSONEncoder().encode(config)
        XCTAssertEqual(try JSONDecoder().decode(AppConfiguration.self, from: encoded), config)
        var old = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        old.removeValue(forKey: "reverseMouseScroll")
        let loaded = try JSONDecoder().decode(AppConfiguration.self,
            from: JSONSerialization.data(withJSONObject: old))
        XCTAssertFalse(loaded.reverseMouseScroll)
        XCTAssertEqual(loaded.mappings, config.mappings)
        XCTAssertEqual(loaded.gestureThreshold, 84)
        XCTAssertTrue(loaded.isEnabled)
    }
}

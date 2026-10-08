import CoreGraphics
import MousePilotCore
import XCTest
@testable import MousePilot

final class KeyEventSenderTests: XCTestCase {
    func testSystemShortcutsUseSessionSourceAndCompleteNativeControlFlags() throws {
        for action in [ActionKind.desktopLeft, .desktopRight, .missionControl, .appWindows] {
            let shortcut = action.defaultShortcut!
            let prepared = try KeyEventSender.prepare(shortcut)
            let events = prepared.steps.map(\.event)
            XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [59, Int64(shortcut.keyCode), Int64(shortcut.keyCode), 59])
            XCTAssertEqual(events.map(\.type), [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
            XCTAssertTrue(events[0].flags.contains(.maskControl))
            XCTAssertNotEqual(events[0].flags.rawValue & 1, 0, "Keep the native left-Control device bit")
            XCTAssertNotEqual(events[1].flags.rawValue & 1, 0)
            XCTAssertTrue(events[1].flags.contains(.maskControl))
            XCTAssertTrue(events[1].flags.contains(.maskSecondaryFn), "Keep native arrow-key flags")
            XCTAssertTrue(events[1].flags.contains(.maskNumericPad))
            XCTAssertFalse(events.last!.flags.contains(.maskControl))
            for event in events {
                XCTAssertEqual(event.getIntegerValueField(.eventSourceStateID), 0)
                XCTAssertEqual(event.getIntegerValueField(.eventSourceUserData), KeyEventSender.eventMarker)
            }
        }
    }

    func testFakeTransportVerifiesOrderingAndKeyHoldTimeWithoutPostingInput() throws {
        let prepared = try KeyEventSender.prepare(ActionKind.missionControl.defaultShortcut!)
        var emitted: [CGEventType] = []
        var waits: [TimeInterval] = []
        KeyEventSender.transmit(prepared, physicalNow: { .init() },
            post: { emitted.append($0.type) }, wait: { waits.append($0) })
        XCTAssertEqual(emitted, [.flagsChanged, .keyDown, .keyUp, .flagsChanged])
        XCTAssertEqual(waits.count, 4)
        XCTAssertGreaterThanOrEqual(waits[1], 0.040)
        XCTAssertTrue(waits.allSatisfy { $0 > 0 })
    }

    func testGestureModifierIsSuspendedAndRestoredOnlyIfStillPhysicallyHeld() throws {
        let physical = PhysicalModifierState(keys: [58])
        let prepared = try KeyEventSender.prepare(ActionKind.desktopLeft.defaultShortcut!, physical: physical)
        XCTAssertEqual(prepared.steps.first!.event.getIntegerValueField(.keyboardEventKeycode), 58)
        XCTAssertFalse(prepared.steps.first!.event.flags.contains(.maskAlternate))
        var heldEvents: [CGEvent] = []
        KeyEventSender.transmit(prepared, physicalNow: { physical }, post: { heldEvents.append($0.copy()!) }, wait: { _ in })
        XCTAssertEqual(heldEvents.last!.getIntegerValueField(.keyboardEventKeycode), 58)
        XCTAssertTrue(heldEvents.last!.flags.contains(.maskAlternate))
        var releasedEvents: [CGEvent] = []
        KeyEventSender.transmit(prepared, physicalNow: { .init() }, post: { releasedEvents.append($0.copy()!) }, wait: { _ in })
        XCTAssertEqual(releasedEvents.count, prepared.steps.count)
        XCTAssertFalse(releasedEvents.last!.flags.contains(.maskAlternate))
    }

    func testHeldRightControlIsPreservedAndItsReleaseIsNotReintroduced() throws {
        let prepared = try KeyEventSender.prepare(ActionKind.desktopRight.defaultShortcut!, physical: .init(keys: [62]))
        XCTAssertEqual(prepared.steps.count, 2)
        XCTAssertNotEqual(prepared.steps[0].event.flags.rawValue & 0x2000, 0)
        var emitted: [CGEvent] = []
        KeyEventSender.transmit(prepared, physicalNow: { .init() }, post: { emitted.append($0.copy()!) }, wait: { _ in })
        XCTAssertEqual(emitted.count, 3)
        XCTAssertEqual(emitted.last!.getIntegerValueField(.keyboardEventKeycode), 62)
        XCTAssertFalse(emitted.last!.flags.contains(.maskControl))
    }

    func testNewPhysicalModifierPressedDuringOutputIsRestoredAtEnd() throws {
        let prepared = try KeyEventSender.prepare(ActionKind.missionControl.defaultShortcut!)
        var emitted: [CGEvent] = []
        KeyEventSender.transmit(prepared, physicalNow: { .init(keys: [60]) },
            post: { emitted.append($0.copy()!) }, wait: { _ in })
        XCTAssertEqual(emitted.last!.getIntegerValueField(.keyboardEventKeycode), 60)
        XCTAssertTrue(emitted.last!.flags.contains(.maskShift))
        XCTAssertFalse(emitted.last!.flags.contains(.maskControl))
    }

    func testCommandTabReleasesSyntheticCommandAndCapsLockIsPreserved() throws {
        let prepared = try KeyEventSender.prepare(ActionKind.previousApp.defaultShortcut!, physical: .init(capsLock: true))
        XCTAssertEqual(prepared.steps.map { $0.event.getIntegerValueField(.keyboardEventKeycode) }, [55, 48, 48, 55])
        XCTAssertTrue(prepared.steps[1].event.flags.contains(.maskCommand))
        XCTAssertNotEqual(prepared.steps[1].event.flags.rawValue & 8, 0)
        XCTAssertFalse(prepared.steps.last!.event.flags.contains(.maskCommand))
        XCTAssertTrue(prepared.steps.allSatisfy { $0.event.flags.contains(.maskAlphaShift) })
    }
}

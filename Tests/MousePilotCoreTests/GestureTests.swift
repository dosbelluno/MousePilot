import Foundation
import XCTest
import MousePilotCore

final class GestureTests: XCTestCase {
    func testFourDirectionsExecuteOnceOnReleaseAndNeverOnPressOrMovement() {
        let cases: [(Double, Double, MouseGesture, ActionKind)] = [
            (-80, 0, .swipeLeft, .desktopLeft), (80, 0, .swipeRight, .desktopRight),
            (0, -80, .swipeUp, .missionControl), (0, 80, .swipeDown, .appWindows)
        ]
        for (x, y, gesture, action) in cases {
            var router = MouseRouter(configuration: .init(isEnabled: true))
            let down = router.route(button: 2, modifiers: [], phase: .down)
            XCTAssertTrue(down.suppress)
            XCTAssertTrue(down.waitingForGesture)
            XCTAssertNil(down.shortcut)
            let move = router.route(button: 2, modifiers: [], phase: .dragged, deltaX: x, deltaY: y)
            XCTAssertTrue(move.suppress)
            XCTAssertNil(move.shortcut)
            let up = router.route(button: 2, modifiers: [], phase: .up)
            XCTAssertEqual(up.action, action)
            XCTAssertEqual(up.executedTrigger?.gesture, gesture)
            XCTAssertTrue(up.gestureFinished)
            XCTAssertNil(router.route(button: 2, modifiers: [], phase: .up).shortcut)
        }
    }

    func testOrdinaryMovementPassesAndMouseMovedDeltasAccumulateOnlyWhileHeld() {
        var router = MouseRouter(configuration: .init(isEnabled: true))
        XCTAssertFalse(router.routeMovement(deltaX: -200, deltaY: 0).suppress)
        _ = router.route(button: 2, modifiers: [], phase: .down)
        for _ in 0..<4 { XCTAssertTrue(router.routeMovement(deltaX: -20, deltaY: 0).suppress) }
        XCTAssertEqual(router.route(button: 2, modifiers: [], phase: .up).action, .desktopLeft)
        XCTAssertFalse(router.routeMovement(deltaX: -200, deltaY: 0).suppress)
    }

    func testSmallClickJitterUsesClickMappingAndIncompleteSwipeDoesNotOpenMissionControl() {
        var router = MouseRouter(configuration: .init(isEnabled: true))
        _ = router.route(button: 2, modifiers: [], phase: .down)
        _ = router.routeMovement(deltaX: 3, deltaY: 2)
        XCTAssertEqual(router.route(button: 2, modifiers: [], phase: .up).action, .missionControl)
        _ = router.route(button: 2, modifiers: [], phase: .down)
        _ = router.routeMovement(deltaX: 30, deltaY: 0)
        let incomplete = router.route(button: 2, modifiers: [], phase: .up)
        XCTAssertNil(incomplete.shortcut)
        XCTAssertTrue(incomplete.suppress)
        XCTAssertTrue(incomplete.gestureFinished)
    }

    func testDirectionLocksAtFirstThresholdCrossingDespiteReturnMovement() {
        var router = MouseRouter(configuration: .init(isEnabled: true))
        _ = router.route(button: 2, modifiers: [], phase: .down)
        _ = router.routeMovement(deltaX: -70, deltaY: 5)
        _ = router.routeMovement(deltaX: 200, deltaY: -500)
        XCTAssertEqual(router.route(button: 2, modifiers: [], phase: .up).action, .desktopLeft)
    }

    func testSideAndPrimaryButtonsKeepTheirOriginalActionsInGestureDefaults() {
        var router = MouseRouter(configuration: .init(isEnabled: true))
        for button in [0, 1, 3, 4] {
            XCTAssertFalse(router.route(button: button, modifiers: [], phase: .down).suppress)
            XCTAssertFalse(router.route(button: button, modifiers: [], phase: .dragged, deltaX: 200).suppress)
            XCTAssertFalse(router.route(button: button, modifiers: [], phase: .up).suppress)
        }
    }

    func testPauseThenResumeWhileHeldCancelsGestureAndStillConsumesRelease() {
        var router = MouseRouter(configuration: .init(isEnabled: true))
        _ = router.route(button: 2, modifiers: [], phase: .down)
        _ = router.routeMovement(deltaX: 100, deltaY: 0)
        router.configuration.isEnabled = false
        router.configuration.isEnabled = true
        let up = router.route(button: 2, modifiers: [], phase: .up)
        XCTAssertTrue(up.suppress)
        XCTAssertNil(up.shortcut)
        XCTAssertFalse(router.hasPendingGesture)
    }

    func testChangingSelectedMappingWhileHeldDoesNotExecuteOldAction() {
        var router = MouseRouter(configuration: .init(isEnabled: true))
        _ = router.route(button: 2, modifiers: [], phase: .down)
        _ = router.routeMovement(deltaX: -100, deltaY: 0)
        let left = router.configuration.mappings.firstIndex { $0.trigger.gesture == .swipeLeft }!
        router.configuration.mappings[left].action = .spotlight
        XCTAssertNil(router.route(button: 2, modifiers: [], phase: .up).shortcut)
    }

    func testRecordingButtonNeverArmsOrExecutesGesture() {
        var router = MouseRouter(configuration: .init(isEnabled: true))
        router.isCapturing = true
        let captured = router.route(button: 2, modifiers: [], phase: .down)
        XCTAssertEqual(captured.capturedTrigger, .init(button: 2))
        XCTAssertFalse(router.hasPendingGesture)
        XCTAssertFalse(router.routeMovement(deltaX: 200, deltaY: 0).suppress)
        let up = router.route(button: 2, modifiers: [], phase: .up)
        XCTAssertTrue(up.suppress)
        XCTAssertNil(up.shortcut)
    }

    func testDisabledDirectionDoesNotFallBackToClick() {
        var config = AppConfiguration(isEnabled: true)
        let left = config.mappings.firstIndex { $0.trigger.gesture == .swipeLeft }!
        config.mappings[left].isEnabled = false
        var router = MouseRouter(configuration: config)
        _ = router.route(button: 2, modifiers: [], phase: .down)
        _ = router.routeMovement(deltaX: -100, deltaY: 0)
        XCTAssertNil(router.route(button: 2, modifiers: [], phase: .up).shortcut)
    }

    func testInitialModifierCombinationIsUsedThroughRelease() {
        var config = AppConfiguration(isEnabled: true)
        for index in config.mappings.indices { config.mappings[index].trigger.modifiers = .shift }
        var router = MouseRouter(configuration: config)
        XCTAssertFalse(router.route(button: 2, modifiers: [], phase: .down).suppress)
        _ = router.route(button: 2, modifiers: [], phase: .up)
        XCTAssertTrue(router.route(button: 2, modifiers: .shift, phase: .down).waitingForGesture)
        _ = router.routeMovement(deltaX: 100, deltaY: 0)
        let up = router.route(button: 2, modifiers: [], phase: .up)
        XCTAssertEqual(up.action, .desktopRight)
        XCTAssertEqual(up.shortcut?.modifiers, .control)
    }

    func testSensitivityChangesRecognitionAndRejectsUnsafeValues() throws {
        var sensitive = MouseRouter(configuration: .init(isEnabled: true, gestureThreshold: 16))
        _ = sensitive.route(button: 2, modifiers: [], phase: .down)
        _ = sensitive.routeMovement(deltaX: 32, deltaY: 0)
        XCTAssertEqual(sensitive.route(button: 2, modifiers: [], phase: .up).action, .desktopRight)
        var deliberate = MouseRouter(configuration: .init(isEnabled: true, gestureThreshold: 120))
        _ = deliberate.route(button: 2, modifiers: [], phase: .down)
        _ = deliberate.routeMovement(deltaX: 32, deltaY: 0)
        XCTAssertNil(deliberate.route(button: 2, modifiers: [], phase: .up).shortcut)
        for threshold in [0.0, 500.0, .infinity, .nan] {
            XCTAssertThrowsError(try AppConfiguration(gestureThreshold: threshold).validated())
        }
    }

    func testOldSavedConfigurationMigratesWithBackupAndPreservesCustomShortcut() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MousePilotMigration-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var legacy = AppConfiguration(isEnabled: true, mappings: MousePreset.fiveButton.mappings)
        legacy.schemaVersion = 1
        let custom = MouseMapping(trigger: .init(button: 8, modifiers: .option), action: .spotlight)
        legacy.mappings.append(custom)
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(legacy)) as! [String: Any]
        json.removeValue(forKey: "gestureThreshold")
        var entries = json["mappings"] as! [[String: Any]]
        for index in entries.indices {
            var trigger = entries[index]["trigger"] as! [String: Any]
            trigger.removeValue(forKey: "gesture")
            entries[index]["trigger"] = trigger
        }
        json["mappings"] = entries
        let original = try JSONSerialization.data(withJSONObject: json)
        let store = ConfigurationStore(url: directory.appendingPathComponent("settings.json"))
        try original.write(to: store.url)
        let loaded = try store.load()
        XCTAssertEqual(loaded.configuration.schemaVersion, 2)
        XCTAssertTrue(loaded.configuration.isEnabled)
        XCTAssertTrue(loaded.configuration.mappings.contains(custom))
        XCTAssertEqual(loaded.configuration.mappings.filter { $0.trigger.button == 2 }.count, 5)
        XCTAssertFalse(loaded.configuration.mappings.contains { [3, 4].contains($0.trigger.button) })
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("before-gestures") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0]), original)
        XCTAssertNil(try store.load().warning)
    }
}

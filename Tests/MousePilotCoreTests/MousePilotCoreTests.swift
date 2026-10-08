import Foundation
import MousePilotCore
import XCTest

final class MousePilotCoreTests: XCTestCase {
    func testMappedPressConsumesDragAndReleaseEvenAfterPausing() {
        var router = MouseRouter(configuration: .init(isEnabled: true, mappings: MousePreset.fiveButton.mappings))
        let press = router.route(button: 3, modifiers: [], phase: .down)
        XCTAssertTrue(press.suppress)
        XCTAssertEqual(press.action, .desktopLeft)
        router.configuration.isEnabled = false
        XCTAssertTrue(router.route(button: 3, modifiers: .shift, phase: .dragged).suppress)
        XCTAssertTrue(router.route(button: 3, modifiers: .shift, phase: .up).suppress)
        XCTAssertFalse(router.route(button: 3, modifiers: [], phase: .down).suppress)
        XCTAssertFalse(router.route(button: 3, modifiers: [], phase: .up).suppress)
    }

    func testUnmappedPressIsNotConsumedIfMappingIsEnabledBeforeRelease() {
        var router = MouseRouter(configuration: .init(isEnabled: false, mappings: MousePreset.fiveButton.mappings))
        XCTAssertFalse(router.route(button: 2, modifiers: [], phase: .down).suppress)
        router.configuration.isEnabled = true
        XCTAssertFalse(router.route(button: 2, modifiers: [], phase: .dragged).suppress)
        XCTAssertFalse(router.route(button: 2, modifiers: [], phase: .up).suppress)
        XCTAssertTrue(router.route(button: 2, modifiers: [], phase: .down).suppress)
    }

    func testPrimaryButtonsCannotBeSuppressedEvenWithMalformedConfiguration() {
        var router = MouseRouter(configuration: .init(isEnabled: true, mappings: [
            .init(trigger: .init(button: 0), action: .missionControl),
            .init(trigger: .init(button: 1), action: .missionControl)
        ]))
        router.isCapturing = true
        for button in [0, 1, -1, 32] {
            for phase in [MousePhase.down, .dragged, .up] {
                XCTAssertEqual(router.route(button: button, modifiers: [], phase: phase), .init())
            }
        }
        XCTAssertTrue(router.isCapturing)
    }

    func testModifierMatchingDoesNotFallBackToPlainClick() {
        var router = MouseRouter(configuration: .init(isEnabled: true, mappings: MousePreset.threeButton.mappings))
        XCTAssertFalse(router.route(button: 2, modifiers: .command, phase: .down).suppress)
        _ = router.route(button: 2, modifiers: .command, phase: .up)
        let option = router.route(button: 2, modifiers: .option, phase: .down)
        XCTAssertEqual(option.action, .desktopLeft)
        XCTAssertEqual(option.shortcut?.modifiers, .control)
        _ = router.route(button: 2, modifiers: [], phase: .up)
        XCTAssertFalse(router.route(button: 2, modifiers: [.option, .shift], phase: .down).suppress)
    }

    func testCaptureIsOneShotAndDoesNotExecuteExistingAction() {
        var router = MouseRouter(configuration: .init(isEnabled: true, mappings: MousePreset.fiveButton.mappings))
        router.isCapturing = true
        let captured = router.route(button: 3, modifiers: .option, phase: .down)
        XCTAssertTrue(captured.suppress)
        XCTAssertEqual(captured.capturedTrigger, .init(button: 3, modifiers: .option))
        XCTAssertNil(captured.shortcut)
        XCTAssertFalse(router.isCapturing)
        XCTAssertNil(router.route(button: 4, modifiers: [], phase: .down).capturedTrigger)
        XCTAssertTrue(router.route(button: 3, modifiers: [], phase: .up).suppress)
    }

    func testCaptureWorksWhileMappingIsPausedAndRepeatedPressFiresOnce() {
        var router = MouseRouter(configuration: .init(isEnabled: false, mappings: MousePreset.fiveButton.mappings))
        router.isCapturing = true
        XCTAssertNotNil(router.route(button: 9, modifiers: .command, phase: .down).capturedTrigger)
        let repeatPress = router.route(button: 9, modifiers: .command, phase: .down)
        XCTAssertTrue(repeatPress.suppress)
        XCTAssertNil(repeatPress.capturedTrigger)
        XCTAssertTrue(router.route(button: 9, modifiers: [], phase: .up).suppress)
        XCTAssertFalse(router.route(button: 9, modifiers: [], phase: .down).suppress)
    }

    func testMappingFiresOnlyOnceUntilButtonReleasedAndCanRecoverAfterTapReset() {
        var router = MouseRouter(configuration: .init(isEnabled: true, mappings: MousePreset.fiveButton.mappings))
        XCTAssertNotNil(router.route(button: 2, modifiers: [], phase: .down).shortcut)
        XCTAssertNil(router.route(button: 2, modifiers: [], phase: .down).shortcut)
        router.resetPressedButtons()
        XCTAssertNotNil(router.route(button: 2, modifiers: [], phase: .down).shortcut)
    }

    func testDisabledMappingAndUnmatchedButtonPreserveOriginalBehavior() {
        var configuration = AppConfiguration(isEnabled: true, mappings: MousePreset.fiveButton.mappings)
        configuration.mappings[0].isEnabled = false
        var router = MouseRouter(configuration: configuration)
        XCTAssertFalse(router.route(button: 2, modifiers: [], phase: .down).suppress)
        XCTAssertFalse(router.route(button: 2, modifiers: [], phase: .up).suppress)
        XCTAssertFalse(router.route(button: 6, modifiers: [], phase: .down).suppress)
    }

    func testCustomShortcutOverrideIsExecutedAndRoundTripsOnDisk() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("settings.json"))
        let shortcut = KeyboardShortcut(keyCode: 0, modifiers: [.command, .shift], keyLabel: "A")
        let config = AppConfiguration(isEnabled: true, mappings: [
            .init(trigger: .init(button: 7, modifiers: .control), action: .missionControl, shortcutOverride: shortcut)
        ])
        try store.save(config)
        let loaded = try store.load()
        XCTAssertEqual(loaded.configuration, config)
        XCTAssertNil(loaded.warning)
        var router = MouseRouter(configuration: loaded.configuration)
        XCTAssertEqual(router.route(button: 7, modifiers: .control, phase: .down).shortcut, shortcut)
    }

    func testCorruptedConfigurationIsPreservedBeforeDefaultsAreUsed() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("settings.json")
        let corrupt = Data("{broken json".utf8)
        try corrupt.write(to: url)
        let store = ConfigurationStore(url: url)
        let loaded = try store.load()
        XCTAssertFalse(loaded.configuration.isEnabled)
        XCTAssertNotNil(loaded.warning)
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.contains("invalid-") }
        XCTAssertEqual(backups.count, 1)
        XCTAssertEqual(try Data(contentsOf: backups[0]), corrupt)
        try store.save(loaded.configuration)
        XCTAssertEqual(try Data(contentsOf: backups[0]), corrupt)
    }

    func testDuplicateOrUnsafeMappingsNeverOverwriteSavedConfiguration() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ConfigurationStore(url: directory.appendingPathComponent("settings.json"))
        let valid = AppConfiguration()
        try store.save(valid)
        var duplicate = valid
        duplicate.mappings.append(.init(trigger: valid.mappings[0].trigger, action: .spotlight))
        XCTAssertThrowsError(try store.save(duplicate))
        var unsafe = valid
        unsafe.mappings[0].trigger.button = 0
        XCTAssertThrowsError(try store.save(unsafe))
        XCTAssertEqual(try store.load().configuration, valid)
    }

    func testInvalidShortcutAndFutureSchemaAreRejected() throws {
        XCTAssertFalse(KeyboardShortcut(keyCode: 55, modifiers: .command, keyLabel: "⌘").isValid)
        XCTAssertFalse(KeyboardShortcut(keyCode: 200, keyLabel: "Unknown").isValid)
        XCTAssertFalse(KeyboardShortcut(keyCode: 0, modifiers: .init(rawValue: 128), keyLabel: "A").isValid)
        XCTAssertFalse(MouseMapping(trigger: .init(button: 2), action: .customShortcut).isValid)
        var configuration = AppConfiguration()
        configuration.schemaVersion = 3
        XCTAssertThrowsError(try configuration.validated())
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("MousePilotTests-\(UUID().uuidString)")
    }
}

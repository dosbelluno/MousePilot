import XCTest
import MousePilotCore
@testable import MousePilot

final class InputDiagnosticsTests: XCTestCase {
    private func activity() -> MouseActivity {
        .init(trigger: .init(button: 2), action: nil, shortcut: nil, captured: false)
    }

    func testNormalUseStoresNoInputHistory() {
        var diagnostics = InputDiagnostics()
        XCTAssertFalse(diagnostics.isEnabled)
        for _ in 0..<100 { diagnostics.record(activity()) }
        XCTAssertTrue(diagnostics.activities.isEmpty)
    }

    func testEnabledSessionIsBoundedAndTurningItOffDeletesHistory() {
        var diagnostics = InputDiagnostics()
        diagnostics.setEnabled(true)
        let events = (0..<60).map { _ in activity() }
        for event in events { diagnostics.record(event) }
        XCTAssertEqual(diagnostics.activities.count, 40)
        XCTAssertEqual(diagnostics.activities.first?.id, events.last?.id)
        diagnostics.setEnabled(false)
        XCTAssertTrue(diagnostics.activities.isEmpty)
        // Ignore an event that was already queued when collection was disabled.
        diagnostics.record(activity())
        XCTAssertTrue(diagnostics.activities.isEmpty)
        diagnostics.setEnabled(true)
        XCTAssertTrue(diagnostics.activities.isEmpty)
    }

    func testNewSessionAndNavigationHaveNoAlwaysOnMonitor() {
        var previous = InputDiagnostics()
        previous.setEnabled(true)
        previous.record(activity())
        let next = InputDiagnostics()
        XCTAssertFalse(next.isEnabled)
        XCTAssertTrue(next.activities.isEmpty)
        XCTAssertEqual(NavigationPage.allCases.map(\.rawValue), ["mappings", "settings"])
    }
}

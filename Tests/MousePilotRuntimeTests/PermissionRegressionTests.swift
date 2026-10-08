import XCTest
@testable import MousePilot

final class PermissionRegressionTests: XCTestCase {
    func testMouseMapperIsNotBlockedByKeyboardInputMonitoringPermission() {
        let access = PermissionState(accessibility: true, inputMonitoring: false, postEvents: true)
        XCTAssertTrue(access.isReady,
                      "A mouse-only filtering tap must not be gated by ListenEvent preflight.")
    }

    func testMouseMapperStillRequiresAccessibilityAndPostingAccess() {
        XCTAssertFalse(PermissionState(accessibility: false, inputMonitoring: true, postEvents: true).isReady)
        XCTAssertFalse(PermissionState(accessibility: true, inputMonitoring: true, postEvents: false).isReady)
    }
}

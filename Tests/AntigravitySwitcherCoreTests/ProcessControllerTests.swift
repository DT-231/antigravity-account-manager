import XCTest
@testable import AntigravitySwitcherCore

final class ProcessControllerTests: XCTestCase {
    @MainActor
    func testMissingApplicationDoesNotRequireQuitOrActivate() async throws {
        let bundleID = "com.antigravityswitcher.tests.missing.\(UUID().uuidString)"
        let controller = ProcessController()

        XCTAssertFalse(controller.activateRunning(bundleId: bundleID))
        let didQuit = try await controller.quitAsync(bundleId: bundleID, timeout: 0.01)
        XCTAssertFalse(didQuit)
    }

    func testWaitForMissingApplicationTimesOut() async {
        let bundleID = "com.antigravityswitcher.tests.missing.\(UUID().uuidString)"
        do {
            try await ProcessController().waitUntilRunningAsync(bundleId: bundleID, timeout: 0)
            XCTFail("Expected readiness timeout")
        } catch let error as ProcessControllerError {
            guard case .readinessTimedOut = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

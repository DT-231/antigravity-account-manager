import Foundation
import XCTest
@testable import AntigravitySwitcherCore

final class QuotaTests: XCTestCase {
    func testLanguageServerArgumentsAreParsedWithoutSkippingFlags() {
        let arguments = AntigravityProcessDiscovery.parseArguments(
            "/Applications/Antigravity/language_server_macos_arm "
                + "--csrf_token test-csrf "
                + "--extension_server_port 63819 "
                + "--cloud_code_endpoint=https://example.invalid "
                + "--subclient_type ide "
                + "--enable_lsp"
        )

        XCTAssertEqual(arguments["csrf_token"], "test-csrf")
        XCTAssertEqual(arguments["extension_server_port"], "63819")
        XCTAssertEqual(arguments["cloud_code_endpoint"], "https://example.invalid")
        XCTAssertEqual(arguments["subclient_type"], "ide")
        XCTAssertNil(arguments["enable_lsp"])
    }

    func testParserNormalizesCreditsAndDynamicModels() throws {
        let response: [String: Any] = [
            "userStatus": [
                "name": "Test User",
                "email": "test@example.com",
                "planStatus": ["planInfo": [
                    "planName": "Pro", "teamsTier": "TEAMS_TIER_PRO",
                    "monthlyPromptCredits": 500, "monthlyFlowCredits": 100
                ]],
                "availablePromptCredits": 421,
                "availableFlowCredits": 88,
                "cascadeModelConfigData": ["clientModelConfigs": [
                    ["label": "Dynamic Model", "modelId": "dynamic-1",
                     "modelOrAlias": ["model": "provider/dynamic-1"],
                     "quotaInfo": ["remainingFraction": 0.82, "resetTime": "2026-10-01T12:00:00Z"]],
                    ["label": "No Quota", "modelId": "dynamic-2"]
                ]]
            ]
        ]
        let server = AntigravityRuntimeServer(pid: 123, rpcPort: 456, csrfToken: "test")
        let result = try AntigravityQuotaParser.parse(response, server: server)

        XCTAssertEqual(result.email, "test@example.com")
        XCTAssertEqual(result.planName, "Pro")
        XCTAssertEqual(result.availablePromptCredits, 421)
        XCTAssertEqual(result.models.count, 2)
        XCTAssertEqual(result.models[0].remainingPercent ?? 0, 82, accuracy: 0.001)
        XCTAssertNil(result.models[1].remainingFraction)
        XCTAssertEqual(result.server.rpcPort, 456)
    }

    func testQuotaSnapshotPersistsWithoutRuntimeSecrets() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-snapshot-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        let fileURL = temporaryDirectory.appendingPathComponent("snapshots.json")
        let store = QuotaSnapshotStore(fileURL: fileURL)
        let response: [String: Any] = [
            "userStatus": [
                "email": "cached@example.com",
                "planStatus": ["planInfo": ["planName": "Pro"]],
                "cascadeModelConfigData": ["clientModelConfigs": [[
                    "label": "Cached Model", "modelId": "cached-model",
                    "quotaInfo": ["remainingFraction": 0.5, "resetTime": "2026-10-02T12:00:00Z"]
                ]]]
            ]
        ]
        let quota = try AntigravityQuotaParser.parse(
            response,
            server: AntigravityRuntimeServer(pid: 99, rpcPort: 12345, csrfToken: "must-not-persist")
        )

        try store.save(AntigravityQuotaSnapshot(profileID: "work", quota: quota))
        let loaded = try store.loadAll()["work"]
        XCTAssertEqual(loaded?.email, "cached@example.com")
        XCTAssertEqual(loaded?.models.first?.remainingPercent ?? 0, 50, accuracy: 0.001)

        let rawFile = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(rawFile.contains("must-not-persist"))
        XCTAssertFalse(rawFile.contains("12345"))
    }
}

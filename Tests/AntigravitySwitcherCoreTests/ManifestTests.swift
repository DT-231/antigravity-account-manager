import XCTest
@testable import AntigravitySwitcherCore

final class ManifestTests: XCTestCase {
    func testBundledManifestUsesUserDataDirStrategy() throws {
        let manifest = try ManifestLoader().loadDefault()
        XCTAssertEqual(manifest.strategy, .userDataDir)
        XCTAssertEqual(manifest.compat.verified, ["2.5.5"])
        XCTAssertNoThrow(try manifest.validate())
    }

    func testUnknownVersionIsUntested() throws {
        let manifest = try ManifestLoader().loadDefault()
        XCTAssertEqual(VersionGate().status(version: "future", compatibility: manifest.compat), .untested)
    }

    func testInvalidOverrideFallsBackToBundledManifest() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("{}".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let manifest = try ManifestLoader().loadDefault(overrideURL: url)
        XCTAssertEqual(manifest.adapterId, "antigravity-ide")
        XCTAssertEqual(manifest.strategy, .userDataDir)
    }

    func testSelfTestWarnsForUnknownVersionAndPendingSwitch() throws {
        let manifest = try ManifestLoader().loadDefault()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("selftest-profile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = AccountProfile(id: "test", name: "Test", userDataDir: directory.path)
        let pending = PendingSwitch(previousProfileID: nil, targetProfileID: "test")

        let report = ProfileSelfTester().run(
            manifest: manifest,
            ideVersion: "future-version",
            profiles: [profile],
            activeProfileID: "test",
            pendingSwitch: pending
        )

        XCTAssertEqual(report.checks.first(where: { $0.id == "version" })?.status, .warning)
        XCTAssertEqual(report.checks.first(where: { $0.id == "pending-switch" })?.status, .warning)
    }
}

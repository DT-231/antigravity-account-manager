import Foundation
import XCTest
@testable import AntigravitySwitcherCore

final class ProfileStoreTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("profile-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testProfileStoreCRUD() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profileDirectory = directory.appendingPathComponent("profile", isDirectory: true)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        let store = ProfileStore(fileURL: directory.appendingPathComponent("profiles.json"))
        let profile = AccountProfile(id: "work", name: "Work", userDataDir: profileDirectory.path)

        try store.add(profile)
        XCTAssertEqual(try store.profile(id: "work"), profile)
        XCTAssertThrowsError(try store.add(profile))

        try store.rename(id: "work", name: "Work Updated")
        XCTAssertEqual(try store.profile(id: "work").name, "Work Updated")

        try store.remove(id: "work")
        XCTAssertTrue(try store.list().isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: profileDirectory.path))
    }

    func testProfileStoreRefusesUnsafeDataDeletion() {
        let profile = AccountProfile(id: "unsafe", name: "Unsafe", userDataDir: "/")
        XCTAssertThrowsError(try ProfileStore().removeData(for: profile))
    }

    func testSwitchStateRoundTrip() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SwitchStateStore(directoryURL: directory)
        let pending = PendingSwitch(previousProfileID: "personal", targetProfileID: "work")

        try store.setActiveProfileID("personal")
        try store.begin(pending)
        XCTAssertEqual(try store.activeProfileID(), "personal")
        XCTAssertEqual(try store.pendingSwitch(), pending)

        try store.clearPending()
        XCTAssertNil(try store.pendingSwitch())
    }

    func testProfileUsageStorePersistsAndRemovesTimestamp() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileUsageStore(fileURL: directory.appendingPathComponent("usage.json"))
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        try store.markUsed(profileID: "work", at: date)
        XCTAssertEqual(try store.loadAll()["work"], date)

        try store.remove(profileID: "work")
        XCTAssertNil(try store.loadAll()["work"])
    }

    func testAccountProfileLinksAreExplicitAndRemovable() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AccountProfileLinkStore(fileURL: directory.appendingPathComponent("links.json"))
        let accountID = UUID()

        try store.setProfileID("work", for: accountID)
        XCTAssertEqual(try store.loadAll()[accountID], "work")

        try store.removeLinks(toProfileID: "work")
        XCTAssertNil(try store.loadAll()[accountID])
    }

    func testProfileProvisionerCreatesIsolatedStableProfile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ProfileStore(fileURL: directory.appendingPathComponent("profiles.json"))
        let profilesDirectory = directory.appendingPathComponent("profiles", isDirectory: true)
        let provisioner = ProfileProvisioner(
            profileStore: store,
            baseDirectory: profilesDirectory
        )
        let account = ManagedAccount(
            displayName: "Personal",
            email: "Hoang.Test+AG@gmail.com",
            googleAccountID: "google-1",
            tokenKeychainReference: "account.test.oauth"
        )

        let first = try provisioner.createProfile(for: account)
        let second = try provisioner.createProfile(for: account)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.name, "Hoang.Test+AG@gmail.com")
        XCTAssertTrue(first.id.hasPrefix("google-hoang-test-ag-gmail-com"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.userDataDir))
        XCTAssertEqual(try store.list(), [first])
    }

    func testProfileProvisionerRejectsMismatchedIDEIdentity() throws {
        let account = ManagedAccount(
            displayName: "Work",
            email: "work@example.com",
            googleAccountID: "google-work",
            tokenKeychainReference: "account.work.oauth"
        )

        XCTAssertNoThrow(try ProfileProvisioner.validateIDEIdentity(
            account: account,
            authenticatedEmail: " WORK@example.com "
        ))
        XCTAssertThrowsError(try ProfileProvisioner.validateIDEIdentity(
            account: account,
            authenticatedEmail: "personal@example.com"
        )) { error in
            XCTAssertEqual(
                error as? ProfileProvisioningError,
                .accountMismatch(expected: "work@example.com", authenticated: "personal@example.com")
            )
        }
        XCTAssertThrowsError(try ProfileProvisioner.validateIDEIdentity(
            account: account,
            authenticatedEmail: nil
        ))
    }

    func testLaunchPlannerUsesManifestTemplate() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Antigravity IDE.app", isDirectory: true)
        let profileDirectory = directory.appendingPathComponent("profile", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        let manifest = makeManifest(appPath: app.path, template: ["--user-data-dir", "{path}"])

        let plan = try LaunchPlanner().plan(
            manifest: manifest,
            profile: AccountProfile(id: "work", name: "Work", userDataDir: profileDirectory.path)
        )

        XCTAssertEqual(plan.appPath, app.path)
        XCTAssertEqual(plan.arguments, ["--safe", "--user-data-dir", profileDirectory.path])
    }

    func testLaunchPlannerFailsClosedWithoutTemplate() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Antigravity IDE.app", isDirectory: true)
        let profileDirectory = directory.appendingPathComponent("profile", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        let manifest = makeManifest(appPath: app.path, template: nil)

        XCTAssertThrowsError(try LaunchPlanner().plan(
            manifest: manifest,
            profile: AccountProfile(id: "work", name: "Work", userDataDir: profileDirectory.path)
        ))
    }

    func testSelfTestWarnsForProfileWithoutStateDatabase() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let app = directory.appendingPathComponent("Antigravity IDE.app", isDirectory: true)
        let profileDirectory = directory.appendingPathComponent("profile", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profileDirectory, withIntermediateDirectories: true)
        let manifest = makeManifest(appPath: app.path, template: ["--user-data-dir={path}"])
        let profile = AccountProfile(id: "empty", name: "Empty", userDataDir: profileDirectory.path)

        let report = ProfileSelfTester().run(
            manifest: manifest,
            ideVersion: "2.5.5",
            profiles: [profile],
            activeProfileID: nil,
            pendingSwitch: nil
        )

        XCTAssertEqual(report.checks.first(where: { $0.id == "profile.empty" })?.status, .warning)
    }

    private func makeManifest(appPath: String, template: [String]?) -> AdapterManifest {
        AdapterManifest(
            adapterId: "test",
            schemaVersion: 1,
            strategy: .userDataDir,
            app: .init(pathCandidates: [appPath], bundleIdCandidates: ["test.bundle"]),
            storage: .init(
                dbPathCandidates: ["unused"],
                table: "ItemTable",
                keyColumn: "key",
                valueColumn: "value",
                identityKeys: .init(required: [], optional: []),
                includeSidecars: []
            ),
            process: .init(
                rootMatch: .init(bundleId: "test.bundle"),
                childNameHints: [],
                quitTimeoutSec: 1,
                readyTimeoutSec: 1
            ),
            launch: .init(
                extraArgs: ["--safe"],
                userDataDirArgTemplate: template,
                proxyArgTemplate: []
            ),
            compat: .init(verified: ["2.5.5"], unsupported: [])
        )
    }
}

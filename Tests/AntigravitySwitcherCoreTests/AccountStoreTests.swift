import Foundation
import XCTest
@testable import AntigravitySwitcherCore

final class AccountStoreTests: XCTestCase {
    func testSQLiteAccountStoreCRUDKeepsOnlyMetadata() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("account-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("accounts.sqlite")
        let store = try SQLiteAccountStore(url: databaseURL)
        var account = ManagedAccount(
            displayName: "Work",
            email: "work@example.com",
            googleAccountID: "google-work",
            tokenKeychainReference: "account.test.oauth"
        )

        try store.add(account)
        XCTAssertEqual(try store.fetch(id: account.id)?.email, "work@example.com")
        XCTAssertThrowsError(try store.add(account))

        account.displayName = "Work Updated"
        account.status = .needsReauthentication
        try store.update(account)
        XCTAssertEqual(try store.fetch(id: account.id)?.displayName, "Work Updated")
        XCTAssertEqual(try store.fetch(id: account.id)?.status, .needsReauthentication)

        try store.delete(id: account.id)
        XCTAssertNil(try store.fetch(id: account.id))

        let databaseBytes = try Data(contentsOf: databaseURL)
        XCTAssertFalse(String(decoding: databaseBytes, as: UTF8.self).contains("test-access-token"))
    }
}

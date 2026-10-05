import Foundation
import SQLite3

public protocol AccountStore {
    func add(_ account: ManagedAccount) throws
    func update(_ account: ManagedAccount) throws
    func delete(id: UUID) throws
    func fetchAll() throws -> [ManagedAccount]
    func fetch(id: UUID) throws -> ManagedAccount?
}

public enum AccountStoreError: LocalizedError { case database(String), duplicate, notFound
    public var errorDescription: String { switch self { case .database(let value): return "Account database error: \(value)"; case .duplicate: return "Google account already exists"; case .notFound: return "Account not found" } }
}

public final class SQLiteAccountStore: AccountStore {
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(url: URL) throws {
        if sqlite3_open(url.path, &db) != SQLITE_OK { throw AccountStoreError.database("open failed") }
        try execute("""
        CREATE TABLE IF NOT EXISTS accounts (
          id TEXT PRIMARY KEY, display_name TEXT NOT NULL, email TEXT, google_account_id TEXT,
          avatar_url TEXT, provider TEXT NOT NULL, keychain_reference TEXT NOT NULL UNIQUE,
          created_at REAL NOT NULL, updated_at REAL NOT NULL, last_login_at REAL,
          token_expires_at REAL, status TEXT NOT NULL
        );
        """)
        // Remove only legacy placeholder rows with no usable identity or
        // Keychain reference. Valid account metadata is never touched.
        try execute("""
        DELETE FROM accounts
        WHERE length(COALESCE(id, '')) = 0
           OR length(COALESCE(display_name, '')) = 0
           OR length(COALESCE(provider, '')) = 0
           OR length(COALESCE(keychain_reference, '')) = 0
           OR length(COALESCE(status, '')) = 0;
        """)
    }

    deinit { sqlite3_close(db) }

    public func add(_ account: ManagedAccount) throws {
        if try fetch(id: account.id) != nil { throw AccountStoreError.duplicate }
        try execute("INSERT INTO accounts VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);", values: values(account))
    }

    public func update(_ account: ManagedAccount) throws {
        try execute("""
        UPDATE accounts SET display_name=?, email=?, google_account_id=?, avatar_url=?, provider=?,
        keychain_reference=?, created_at=?, updated_at=?, last_login_at=?, token_expires_at=?, status=? WHERE id=?;
        """, values: Array(values(account).dropFirst()) + [account.id.uuidString])
    }

    public func delete(id: UUID) throws { try execute("DELETE FROM accounts WHERE id=?;", values: [id.uuidString]) }

    public func fetchAll() throws -> [ManagedAccount] {
        let statement = try prepare("""
        SELECT * FROM accounts
        WHERE length(COALESCE(id, '')) > 0
          AND length(COALESCE(display_name, '')) > 0
          AND length(COALESCE(provider, '')) > 0
          AND length(COALESCE(keychain_reference, '')) > 0
          AND length(COALESCE(status, '')) > 0
        ORDER BY created_at;
        """)
        defer { sqlite3_finalize(statement) }
        var result: [ManagedAccount] = []
        while sqlite3_step(statement) == SQLITE_ROW { result.append(try decode(statement)) }
        return result
    }

    public func fetch(id: UUID) throws -> ManagedAccount? {
        let statement = try prepare("SELECT * FROM accounts WHERE id=?;")
        defer { sqlite3_finalize(statement) }
        try bind([id.uuidString], to: statement)
        return sqlite3_step(statement) == SQLITE_ROW ? try decode(statement) : nil
    }

    private func values(_ account: ManagedAccount) -> [Any] {
        [account.id.uuidString, account.displayName, account.email ?? NSNull(), account.googleAccountID ?? NSNull(),
         account.avatarURL?.absoluteString ?? NSNull(), account.provider.rawValue, account.tokenKeychainReference,
         account.createdAt.timeIntervalSince1970, account.updatedAt.timeIntervalSince1970,
         account.lastLoginAt?.timeIntervalSince1970 ?? NSNull(), account.tokenExpiresAt?.timeIntervalSince1970 ?? NSNull(), account.status.rawValue]
    }

    private func decode(_ statement: OpaquePointer) throws -> ManagedAccount {
        func text(_ index: Int32) -> String? { guard let value = sqlite3_column_text(statement, index) else { return nil }; return String(cString: value) }
        guard let id = text(0).flatMap(UUID.init), let name = text(1), let provider = text(5).flatMap(AccountProvider.init(rawValue:)), let reference = text(6), let status = text(11).flatMap(AccountStatus.init(rawValue:)) else { throw AccountStoreError.database("invalid row") }
        let date: (Int32) -> Date? = { index in sqlite3_column_type(statement, index) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(statement, index)) }
        return ManagedAccount(id: id, displayName: name, email: text(2), googleAccountID: text(3), avatarURL: text(4).flatMap(URL.init(string:)), provider: provider, tokenKeychainReference: reference, createdAt: date(7) ?? Date(), updatedAt: date(8) ?? Date(), lastLoginAt: date(9), tokenExpiresAt: date(10), status: status)
    }

    private func execute(_ sql: String, values: [Any] = []) throws {
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }; try bind(values, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw AccountStoreError.database(String(cString: sqlite3_errmsg(db))) }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?; guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw AccountStoreError.database(String(cString: sqlite3_errmsg(db))) }; return statement
    }

    private func bind(_ values: [Any], to statement: OpaquePointer) throws {
        // SQLite must copy Swift string storage before the temporary String
        // value goes out of scope. Passing nil here means SQLITE_STATIC and
        // caused account metadata to be persisted as empty/corrupt values.
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            if value is NSNull { sqlite3_bind_null(statement, index) }
            else if let string = value as? String {
                sqlite3_bind_text(statement, index, string, Int32(string.utf8.count), transient)
            }
            else if let number = value as? Double { sqlite3_bind_double(statement, index, number) }
            else { sqlite3_bind_null(statement, index) }
        }
    }
}

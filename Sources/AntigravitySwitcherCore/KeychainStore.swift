import Foundation
import Security

public protocol KeychainStore {
    func saveSecret(_ data: Data, service: String, account: String) throws
    func loadSecret(service: String, account: String) throws -> Data
    func deleteSecret(service: String, account: String) throws
}

public enum KeychainError: LocalizedError {
    case status(OSStatus)
    case notFound
    public var errorDescription: String {
        switch self { case .status(let status): return "Keychain operation failed (\(status))"; case .notFound: return "Keychain item not found" }
    }
}

public struct MacKeychainStore: KeychainStore {
    public static let service = "com.antigravityswitcher.accounts"
    public static let legacyServices = [
        "com.yourcompany.AntigravityAccountManager.accounts"
    ]
    public init() {}

    /// Moves an existing credential to the current service name without ever
    /// exposing its contents outside Keychain-backed memory.
    public func migrateLegacySecretIfNeeded(account: String) throws {
        if (try? loadSecret(service: Self.service, account: account)) != nil { return }
        for legacyService in Self.legacyServices {
            guard let data = try? loadSecret(service: legacyService, account: account) else { continue }
            try saveSecret(data, service: Self.service, account: account)
            try deleteSecret(service: legacyService, account: account)
            return
        }
    }

    public func saveSecret(_ data: Data, service: String = MacKeychainStore.service, account: String) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        let attributes: [CFString: Any] = [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecSuccess {
            let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else { throw KeychainError.status(updateStatus) }
        } else if status == errSecItemNotFound {
            var add = query; attributes.forEach { add[$0.key] = $0.value }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
        } else { throw KeychainError.status(status) }
    }

    public func loadSecret(service: String = MacKeychainStore.service, account: String) throws -> Data {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecReturnData: true]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw KeychainError.notFound }
        guard status == errSecSuccess, let data = result as? Data else { throw KeychainError.status(status) }
        return data
    }

    public func deleteSecret(service: String = MacKeychainStore.service, account: String) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError.status(status) }
    }
}

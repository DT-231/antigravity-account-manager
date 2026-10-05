import Foundation

public struct OAuthLocalClientConfiguration: Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String?

    public init(clientID: String, clientSecret: String?) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

/// Stores local OAuth client configuration in Keychain. This is intended for
/// a private, single-Mac build and keeps the client secret out of the app
/// bundle, shell arguments and plaintext configuration files.
public struct OAuthLocalConfigurationStore {
    public static let service = "com.antigravityswitcher.oauth-client"
    private static let clientIDAccount = "google.client-id"
    private static let clientSecretAccount = "google.client-secret"
    private let keychain: any KeychainStore

    public init(keychain: any KeychainStore = MacKeychainStore()) {
        self.keychain = keychain
    }

    public func load() -> OAuthLocalClientConfiguration? {
        guard let idData = try? keychain.loadSecret(
            service: Self.service,
            account: Self.clientIDAccount
        ), let clientID = String(data: idData, encoding: .utf8), !clientID.isEmpty else {
            return nil
        }
        let secret = (try? keychain.loadSecret(
            service: Self.service,
            account: Self.clientSecretAccount
        )).flatMap { String(data: $0, encoding: .utf8) }
        return OAuthLocalClientConfiguration(clientID: clientID, clientSecret: secret)
    }

    public func save(clientID: String, clientSecret: String) throws {
        let normalizedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedSecret = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            throw OAuthError.configurationMissing("Google OAuth client ID")
        }
        guard !normalizedSecret.isEmpty else {
            throw OAuthError.configurationMissing("Google OAuth client secret")
        }
        try keychain.saveSecret(
            Data(normalizedID.utf8),
            service: Self.service,
            account: Self.clientIDAccount
        )
        do {
            try keychain.saveSecret(
                Data(normalizedSecret.utf8),
                service: Self.service,
                account: Self.clientSecretAccount
            )
        } catch {
            try? keychain.deleteSecret(service: Self.service, account: Self.clientIDAccount)
            throw error
        }
    }

    public func delete() throws {
        try keychain.deleteSecret(service: Self.service, account: Self.clientIDAccount)
        try keychain.deleteSecret(service: Self.service, account: Self.clientSecretAccount)
    }
}

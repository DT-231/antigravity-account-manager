import Foundation

public enum AccountProvider: String, Codable, Sendable { case antigravity }
public enum AccountStatus: String, Codable, Sendable {
    case authenticated, expired, needsReauthentication, error
}

public struct ManagedAccount: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var displayName: String
    public var email: String?
    public var googleAccountID: String?
    public var avatarURL: URL?
    public var provider: AccountProvider
    public var tokenKeychainReference: String
    public var createdAt: Date
    public var updatedAt: Date
    public var lastLoginAt: Date?
    public var tokenExpiresAt: Date?
    public var status: AccountStatus

    public init(
        id: UUID = UUID(), displayName: String, email: String? = nil,
        googleAccountID: String? = nil, avatarURL: URL? = nil,
        provider: AccountProvider = .antigravity,
        tokenKeychainReference: String, createdAt: Date = Date(),
        updatedAt: Date = Date(), lastLoginAt: Date? = nil,
        tokenExpiresAt: Date? = nil, status: AccountStatus = .authenticated
    ) {
        self.id = id; self.displayName = displayName; self.email = email
        self.googleAccountID = googleAccountID; self.avatarURL = avatarURL
        self.provider = provider; self.tokenKeychainReference = tokenKeychainReference
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.lastLoginAt = lastLoginAt
        self.tokenExpiresAt = tokenExpiresAt; self.status = status
    }
}

public struct StoredGoogleCredential: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let expiresAt: Date?
}

public struct GoogleOAuthConfiguration: Sendable {
    public static let infoPlistClientIDKey = "GoogleOAuthClientID"
    public let clientID: String
    public let clientSecret: String?
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let userInfoEndpoint: URL
    public let redirectURI: URL
    public let scopes: [String]

    public init(
        clientID: String,
        clientSecret: String? = nil,
        redirectURI: URL? = nil,
        scopes: [String]
    ) throws {
        guard !clientID.isEmpty else { throw OAuthError.configurationMissing("client ID") }
        guard let redirect = redirectURI ?? URL(string: "http://localhost:1455/auth/callback"),
              ["localhost", "127.0.0.1"].contains(redirect.host?.lowercased() ?? ""),
              redirect.port != nil,
              redirect.path == "/auth/callback" else {
            throw OAuthError.configurationMissing("redirect URI")
        }
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        self.tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
        self.userInfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
        self.redirectURI = redirect
        self.scopes = scopes
    }

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> Self {
        guard let clientID = environment["GOOGLE_OAUTH_CLIENT_ID"], !clientID.isEmpty else {
            throw OAuthError.configurationMissing("GOOGLE_OAUTH_CLIENT_ID")
        }
        let secret = environment["GOOGLE_OAUTH_CLIENT_SECRET"].flatMap { $0.isEmpty ? nil : $0 }
        return try Self(clientID: clientID, clientSecret: secret, scopes: [
            "openid", "email", "profile"
        ])
    }

    /// Resolves the public OAuth client ID from the development environment
    /// first, then from the packaged application's Info.plist. Client secrets
    /// are intentionally never loaded from an application bundle.
    public static func fromApplication(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        localConfiguration: OAuthLocalClientConfiguration? = OAuthLocalConfigurationStore().load()
    ) throws -> Self {
        let environmentClientID = environment["GOOGLE_OAUTH_CLIENT_ID"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bundledClientID = (infoDictionary[infoPlistClientIDKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let localClientID = localConfiguration?.clientID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let clientID = [environmentClientID, localClientID, bundledClientID]
            .compactMap({ $0 })
            .first(where: { !$0.isEmpty }) else {
            throw OAuthError.configurationMissing(
                "GOOGLE_OAUTH_CLIENT_ID or Info.plist key \(infoPlistClientIDKey)"
            )
        }
        let secret = environment["GOOGLE_OAUTH_CLIENT_SECRET"]
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? localConfiguration?.clientSecret
        return try Self(clientID: clientID, clientSecret: secret, scopes: [
            "openid", "email", "profile"
        ])
    }
}

public struct GoogleTokenResponse: Decodable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let idToken: String?
    public let expiresIn: Int?

    enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", idToken = "id_token", expiresIn = "expires_in" }
}

public struct GoogleAccountIdentity: Decodable, Equatable, Sendable {
    public let id: String
    public let email: String?
    public let picture: URL?

    enum CodingKeys: String, CodingKey { case id, email, picture }
}

public struct OAuthCallback: Equatable, Sendable {
    public let code: String
    public let state: String
}

public enum OAuthError: LocalizedError, Equatable, Sendable {
    case configurationMissing(String)
    case invalidAuthorizationURL
    case callbackServerFailed(String)
    case callbackInvalid
    case stateMismatch
    case authorizationDenied
    case authorizationCodeMissing
    case tokenExchangeFailed
    case invalidIdentity
    case accountAlreadyExists
    case keychainFailure
    case accountStoreFailure
    case timeout
    case cancelled

    public var errorDescription: String {
        switch self {
        case .configurationMissing(let value): return "OAuth configuration missing: \(value)"
        case .invalidAuthorizationURL: return "Could not create Google authorization URL"
        case .callbackServerFailed(let value): return "OAuth callback server failed: \(value)"
        case .callbackInvalid: return "Invalid OAuth callback"
        case .stateMismatch: return "OAuth state validation failed"
        case .authorizationDenied: return "Google authorization was denied"
        case .authorizationCodeMissing: return "Google authorization code was missing"
        case .tokenExchangeFailed: return "Google token exchange failed"
        case .invalidIdentity: return "Could not identify the Google account"
        case .accountAlreadyExists: return "This Google account is already managed"
        case .keychainFailure: return "Could not save credentials to Keychain"
        case .accountStoreFailure: return "Could not save account metadata"
        case .timeout: return "Google sign-in timed out"
        case .cancelled: return "Google sign-in was cancelled"
        }
    }
}

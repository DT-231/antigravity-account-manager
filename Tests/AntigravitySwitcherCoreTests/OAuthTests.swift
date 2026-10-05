import CryptoKit
import XCTest
@testable import AntigravitySwitcherCore

final class OAuthTests: XCTestCase {
    private final class MemoryKeychain: KeychainStore {
        var values: [String: Data] = [:]
        private func key(service: String, account: String) -> String { "\(service)|\(account)" }
        func saveSecret(_ data: Data, service: String, account: String) throws {
            values[key(service: service, account: account)] = data
        }
        func loadSecret(service: String, account: String) throws -> Data {
            guard let data = values[key(service: service, account: account)] else {
                throw KeychainError.notFound
            }
            return data
        }
        func deleteSecret(service: String, account: String) throws {
            values.removeValue(forKey: key(service: service, account: account))
        }
    }

    func testKeychainServiceUsesApplicationNamespace() {
        XCTAssertEqual(MacKeychainStore.service, "com.antigravityswitcher.accounts")
        XCTAssertFalse(MacKeychainStore.service.contains("yourcompany"))
        XCTAssertTrue(MacKeychainStore.legacyServices.contains(
            "com.yourcompany.AntigravityAccountManager.accounts"
        ))
    }

    func testApplicationOAuthConfigurationFallsBackToInfoPlistClientID() throws {
        let configuration = try GoogleOAuthConfiguration.fromApplication(
            environment: [:],
            infoDictionary: [GoogleOAuthConfiguration.infoPlistClientIDKey: "test-client-id"],
            localConfiguration: nil
        )

        XCTAssertEqual(configuration.clientID, "test-client-id")
        XCTAssertNil(configuration.clientSecret)
    }

    func testEnvironmentOAuthConfigurationOverridesInfoPlist() throws {
        let configuration = try GoogleOAuthConfiguration.fromApplication(
            environment: [
                "GOOGLE_OAUTH_CLIENT_ID": "environment-client-id",
                "GOOGLE_OAUTH_CLIENT_SECRET": "test-client-secret"
            ],
            infoDictionary: [GoogleOAuthConfiguration.infoPlistClientIDKey: "bundled-client-id"],
            localConfiguration: OAuthLocalClientConfiguration(
                clientID: "local-client-id",
                clientSecret: "local-client-secret"
            )
        )

        XCTAssertEqual(configuration.clientID, "environment-client-id")
        XCTAssertEqual(configuration.clientSecret, "test-client-secret")
    }

    func testLocalOAuthConfigurationUsesKeychainOnly() throws {
        let keychain = MemoryKeychain()
        let store = OAuthLocalConfigurationStore(keychain: keychain)

        try store.save(clientID: "local-client-id", clientSecret: "local-client-secret")
        XCTAssertEqual(
            store.load(),
            OAuthLocalClientConfiguration(
                clientID: "local-client-id",
                clientSecret: "local-client-secret"
            )
        )
        try store.delete()
        XCTAssertNil(store.load())
    }

    func testPKCEIsRandomAndURLSafe() {
        let first = PKCEPair.generate()
        let second = PKCEPair.generate()
        XCTAssertFalse(first.verifier.isEmpty)
        XCTAssertNotEqual(first.verifier, second.verifier)
        XCTAssertFalse(first.challenge.contains("+"))
        XCTAssertFalse(first.challenge.contains("/"))
        XCTAssertFalse(first.challenge.contains("="))
    }

    func testPKCEChallengeIsDeterministicSHA256() {
        let pair = PKCEPair(verifier: "test-verifier")
        let digest = SHA256.hash(data: Data("test-verifier".utf8))
        let expected = Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(pair.challenge, expected)
    }

    func testCallbackParserAcceptsLoopbackGET() throws {
        let callback = try OAuthCallbackParser.parse(
            method: "GET", host: "localhost:1455", path: "/auth/callback", query: "code=abc&state=xyz"
        )
        XCTAssertEqual(callback, OAuthCallback(code: "abc", state: "xyz"))
    }

    func testCallbackParserSupportsConfiguredLoopbackPort() throws {
        let callback = try OAuthCallbackParser.parse(
            method: "GET",
            host: "127.0.0.1:9876",
            path: "/auth/callback",
            query: "code=abc&state=xyz",
            expectedPort: 9876
        )
        XCTAssertEqual(callback, OAuthCallback(code: "abc", state: "xyz"))
    }

    func testCallbackServerTimesOutWithoutRequest() async throws {
        let server = try OAuthCallbackServer(port: 0)
        do {
            _ = try await server.waitForCallback(timeout: 0.05)
            XCTFail("Expected callback timeout")
        } catch let error as OAuthError {
            XCTAssertEqual(error, .timeout)
        }
    }

    func testCallbackParserRejectsInvalidRequests() {
        XCTAssertThrowsError(try OAuthCallbackParser.parse(method: "POST", host: "localhost:1455", path: "/auth/callback", query: "code=abc&state=xyz"))
        XCTAssertThrowsError(try OAuthCallbackParser.parse(method: "GET", host: "example.com:1455", path: "/auth/callback", query: "code=abc&state=xyz"))
        XCTAssertThrowsError(try OAuthCallbackParser.parse(method: "GET", host: "localhost:1455", path: "/wrong", query: "code=abc&state=xyz"))
        XCTAssertThrowsError(try OAuthCallbackParser.parse(method: "GET", host: "localhost:1455", path: "/auth/callback", query: "code=abc"))
    }
}

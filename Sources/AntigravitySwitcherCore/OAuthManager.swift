import AppKit
import Combine
import Foundation

public enum OAuthUIState: Equatable, Sendable { case idle, starting, waitingForBrowser, waitingForCallback, exchangingCode, identifyingAccount, savingAccount, completed, failed(String) }

@MainActor
public final class OAuthManager: ObservableObject {
    @Published public private(set) var state: OAuthUIState = .idle
    private let provider: GoogleOAuthProvider
    private let keychain: any KeychainStore
    private let accountStore: any AccountStore
    private var callbackServer: OAuthCallbackServer?
    public init(provider: GoogleOAuthProvider, keychain: any KeychainStore, accountStore: any AccountStore) {
        self.provider = provider; self.keychain = keychain; self.accountStore = accountStore
    }

    public func cancel() {
        OAuthDiagnostics.info("OAuth flow cancelled")
        callbackServer?.cancel(); callbackServer = nil; state = .idle
    }

    public func startGoogleLogin(displayName: String) async throws -> ManagedAccount {
        OAuthDiagnostics.info("OAuth flow started")
        state = .starting
        let pkce = PKCEPair.generate()
        let stateValue = PKCEPair.generate().verifier
        let server: OAuthCallbackServer
        do {
            guard let configuredPort = provider.configuration.redirectURI.port,
                  let callbackPort = UInt16(exactly: configuredPort) else {
                throw OAuthError.configurationMissing("loopback redirect port")
            }
            server = try OAuthCallbackServer(port: callbackPort)
        } catch {
            OAuthDiagnostics.error("Callback server could not start: \(error.localizedDescription)")
            state = .failed("callback server failed")
            throw error
        }
        callbackServer = server
        let url: URL
        do {
            url = try provider.authorizationURL(state: stateValue, pkce: pkce)
        } catch {
            OAuthDiagnostics.error("Authorization URL could not be created: \(error.localizedDescription)")
            state = .failed("authorization URL failed")
            throw error
        }
        guard NSWorkspace.shared.open(url) else {
            OAuthDiagnostics.error("Default browser could not be opened")
            state = .failed("browser launch failed")
            throw OAuthError.cancelled
        }
        OAuthDiagnostics.info("OAuth browser opened; waiting for callback on configured loopback port")
        state = .waitingForCallback
        let callback: OAuthCallback
        do {
            callback = try await server.waitForCallback()
        } catch {
            OAuthDiagnostics.error("OAuth callback failed: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
            throw error
        }
        OAuthDiagnostics.info("OAuth callback received; validating state")
        guard callback.state == stateValue else {
            OAuthDiagnostics.error("OAuth state mismatch")
            state = .failed("state mismatch")
            throw OAuthError.stateMismatch
        }
        OAuthDiagnostics.info("OAuth state validated")
        state = .exchangingCode
        let tokens: GoogleTokenResponse
        do {
            tokens = try await provider.exchange(code: callback.code, verifier: pkce.verifier)
            OAuthDiagnostics.info("OAuth token exchange succeeded")
        } catch {
            OAuthDiagnostics.error("OAuth token exchange failed: \(error.localizedDescription)")
            state = .failed("token exchange failed")
            throw error
        }
        state = .identifyingAccount
        let identity: GoogleAccountIdentity
        do {
            identity = try await provider.identity(accessToken: tokens.accessToken)
            OAuthDiagnostics.info("Google identity resolved: \(identity.email ?? "no email")")
        } catch {
            OAuthDiagnostics.error("Google identity lookup failed: \(error.localizedDescription)")
            state = .failed("identity lookup failed")
            throw error
        }
        let existing: [ManagedAccount]
        do {
            existing = try accountStore.fetchAll()
        } catch {
            OAuthDiagnostics.error("Account store read failed: \(error.localizedDescription)")
            state = .failed("account store failed")
            throw OAuthError.accountStoreFailure
        }
        if existing.contains(where: { $0.googleAccountID == identity.id || ($0.email?.lowercased() == identity.email?.lowercased() && identity.email != nil) }) {
            OAuthDiagnostics.error("Account already exists: \(identity.email ?? "unknown email")")
            state = .failed("account already exists"); throw OAuthError.accountAlreadyExists
        }
        state = .savingAccount
        // Google email is the stable, recognizable profile label. The caller's
        // display name remains a fallback for providers that return no email.
        let profileName = identity.email ?? displayName
        let account = ManagedAccount(displayName: profileName, email: identity.email, googleAccountID: identity.id, avatarURL: identity.picture, tokenKeychainReference: "account.\(UUID().uuidString).oauth", lastLoginAt: Date(), tokenExpiresAt: tokens.expiresIn.map { Date().addingTimeInterval(TimeInterval($0)) })
        let credential = StoredGoogleCredential(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken, idToken: tokens.idToken, expiresAt: account.tokenExpiresAt)
        do {
            let data = try JSONEncoder().encode(credential)
            try keychain.saveSecret(data, service: MacKeychainStore.service, account: account.tokenKeychainReference)
            try accountStore.add(account)
        } catch {
            try? keychain.deleteSecret(service: MacKeychainStore.service, account: account.tokenKeychainReference)
            OAuthDiagnostics.error("Secure account save failed: \(error.localizedDescription)")
            state = .failed("secure account save failed")
            throw OAuthError.accountStoreFailure
        }
        callbackServer = nil
        state = .completed
        OAuthDiagnostics.info("OAuth account saved successfully: \(identity.email ?? "unknown email")")
        return account
    }
}

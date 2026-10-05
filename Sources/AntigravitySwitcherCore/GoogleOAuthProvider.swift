import Foundation

public struct GoogleOAuthProvider: Sendable {
    public let configuration: GoogleOAuthConfiguration
    private let session: URLSession

    public init(configuration: GoogleOAuthConfiguration, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func authorizationURL(state: String, pkce: PKCEPair, loginHint: String? = nil) throws -> URL {
        var components = URLComponents(url: configuration.authorizationEndpoint, resolvingAgainstBaseURL: false)
        var items = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "select_account consent")
        ]
        if let loginHint { items.append(URLQueryItem(name: "login_hint", value: loginHint)) }
        components?.queryItems = items
        guard let url = components?.url else { throw OAuthError.invalidAuthorizationURL }
        return url
    }

    public func exchange(code: String, verifier: String) async throws -> GoogleTokenResponse {
        OAuthDiagnostics.info("Sending authorization-code exchange request")
        var request = URLRequest(url: configuration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var fields = [
            "grant_type": "authorization_code", "client_id": configuration.clientID,
            "code": code, "code_verifier": verifier,
            "redirect_uri": configuration.redirectURI.absoluteString
        ]
        if let secret = configuration.clientSecret { fields["client_secret"] = secret }
        request.httpBody = formEncoded(fields)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            OAuthDiagnostics.error("Token endpoint network error: \(error.localizedDescription)")
            throw OAuthError.tokenExchangeFailed
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            OAuthDiagnostics.error("Token endpoint returned HTTP \(status): \(safeOAuthError(from: data))")
            throw OAuthError.tokenExchangeFailed
        }
        do { return try JSONDecoder().decode(GoogleTokenResponse.self, from: data) }
        catch {
            OAuthDiagnostics.error("Token endpoint returned an unexpected response (body suppressed)")
            throw OAuthError.tokenExchangeFailed
        }
    }

    public func identity(accessToken: String) async throws -> GoogleAccountIdentity {
        var request = URLRequest(url: configuration.userInfoEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        OAuthDiagnostics.info("Requesting Google account identity")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            OAuthDiagnostics.error("Google identity network error: \(error.localizedDescription)")
            throw OAuthError.invalidIdentity
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            OAuthDiagnostics.error("Google identity endpoint returned HTTP \(status) (response body suppressed)")
            throw OAuthError.invalidIdentity
        }
        do { return try JSONDecoder().decode(GoogleAccountIdentity.self, from: data) }
        catch {
            OAuthDiagnostics.error("Google identity response was invalid (body suppressed)")
            throw OAuthError.invalidIdentity
        }
    }

    private func formEncoded(_ fields: [String: String]) -> Data {
        let body = fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value.formURLEncoded)" }.joined(separator: "&")
        return Data(body.utf8)
    }

    private func safeOAuthError(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "provider error details unavailable"
        }
        let code = object["error"] as? String ?? "unknown_provider_error"
        let description = object["error_description"] as? String
        guard let description, !description.isEmpty else { return code }
        let oneLine = description
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        let limited = String(oneLine.prefix(200))
        return "\(code) (\(limited))"
    }
}

private extension String {
    var formURLEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.union(CharacterSet(charactersIn: "-._* ")))?.replacingOccurrences(of: " ", with: "+") ?? self
    }
}

import Foundation

public enum OAuthCallbackParser {
    public static func parse(
        method: String,
        host: String,
        path: String,
        query: String,
        expectedPort: UInt16 = 1455
    ) throws -> OAuthCallback {
        let acceptedHosts = ["localhost:\(expectedPort)", "127.0.0.1:\(expectedPort)"]
        guard method.uppercased() == "GET",
              acceptedHosts.contains(host.lowercased()),
              path == "/auth/callback",
              query.utf8.count <= 4096,
              let components = URLComponents(string: "http://localhost\(path)?\(query)"),
              let items = components.queryItems else { throw OAuthError.callbackInvalid }
        if items.first(where: { $0.name == "error" }) != nil { throw OAuthError.authorizationDenied }
        guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty,
              let state = items.first(where: { $0.name == "state" })?.value, !state.isEmpty else {
            throw OAuthError.callbackInvalid
        }
        return OAuthCallback(code: code, state: state)
    }
}

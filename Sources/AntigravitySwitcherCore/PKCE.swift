import CryptoKit
import Foundation

public struct PKCEPair: Equatable, Sendable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        let digest = SHA256.hash(data: Data(verifier.utf8))
        self.challenge = Data(digest).base64URLEncodedString()
    }

    public static func generate() -> Self {
        var bytes = [UInt8](repeating: 0, count: 64)
        for index in bytes.indices { bytes[index] = UInt8.random(in: .min ... .max) }
        return Self(verifier: Data(bytes).base64URLEncodedString())
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

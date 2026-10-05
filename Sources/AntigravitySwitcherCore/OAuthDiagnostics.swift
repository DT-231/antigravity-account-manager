import Foundation
import OSLog

/// Safe OAuth diagnostics for development. Never include credentials, codes,
/// state, PKCE values, or raw authorization URLs in these messages.
public enum OAuthDiagnostics {
    private static let logger = Logger(
        subsystem: "com.antigravityswitcher",
        category: "oauth"
    )

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        write("INFO", message)
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
        write("ERROR", message)
    }

    private static func write(_ level: String, _ message: String) {
#if DEBUG
        let line = "[oauth] \(level): \(message)\n"
        FileHandle.standardError.write(Data(line.utf8))
#endif
    }
}

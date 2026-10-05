import Foundation

public enum AdapterStrategy: String, Codable, Sendable {
    case userDataDir = "user-data-dir"
    case sqliteKeys = "sqlite-keys"
    case fileSwap = "file-swap"
}

public struct AdapterManifest: Codable, Sendable {
    public struct App: Codable, Sendable {
        public let pathCandidates: [String]
        public let bundleIdCandidates: [String]
    }

    public struct IdentityKeys: Codable, Sendable {
        public let required: [String]
        public let optional: [String]
    }

    public struct Storage: Codable, Sendable {
        public let dbPathCandidates: [String]
        public let table: String
        public let keyColumn: String
        public let valueColumn: String
        public let identityKeys: IdentityKeys
        public let includeSidecars: [String]
    }

    public struct Process: Codable, Sendable {
        public struct RootMatch: Codable, Sendable { public let bundleId: String }
        public let rootMatch: RootMatch
        public let childNameHints: [String]
        public let quitTimeoutSec: Int
        public let readyTimeoutSec: Int
    }

    public struct Launch: Codable, Sendable {
        public let extraArgs: [String]
        public let userDataDirArgTemplate: [String]?
        public let proxyArgTemplate: [String]
    }

    public struct Compatibility: Codable, Sendable {
        public let verified: [String]
        public let unsupported: [String]
    }

    public let adapterId: String
    public let schemaVersion: Int
    public let strategy: AdapterStrategy
    public let app: App
    public let storage: Storage
    public let process: Process
    public let launch: Launch
    public let compat: Compatibility

    public func validate() throws {
        guard schemaVersion == 1 else { throw ManifestError.unsupportedSchema(schemaVersion) }
        guard !adapterId.isEmpty else { throw ManifestError.invalid("adapterId is empty") }
        guard !app.pathCandidates.isEmpty else { throw ManifestError.invalid("app.pathCandidates is empty") }
        guard !app.bundleIdCandidates.isEmpty else { throw ManifestError.invalid("app.bundleIdCandidates is empty") }
        guard !storage.dbPathCandidates.isEmpty else { throw ManifestError.invalid("storage.dbPathCandidates is empty") }
        guard process.quitTimeoutSec > 0, process.readyTimeoutSec > 0 else {
            throw ManifestError.invalid("process timeouts must be positive")
        }
        if strategy == .userDataDir && (launch.userDataDirArgTemplate?.isEmpty ?? true) {
            throw ManifestError.invalid("user-data-dir strategy requires launch.userDataDirArgTemplate")
        }
    }
}

public enum ManifestError: LocalizedError, Equatable {
    case invalid(String)
    case unsupportedSchema(Int)
    case notFound(String)

    public var errorDescription: String {
        switch self {
        case .invalid(let message): return "Invalid manifest: \(message)"
        case .unsupportedSchema(let version): return "Unsupported manifest schema: \(version)"
        case .notFound(let path): return "Manifest not found: \(path)"
        }
    }
}

public struct ManifestLoader: Sendable {
    private let decoder = JSONDecoder()

    public init() {}

    public func loadDefault() throws -> AdapterManifest {
        guard let url = Bundle.module.url(forResource: "antigravity-ide.v1", withExtension: "json") else {
            throw ManifestError.notFound("bundled antigravity-ide.v1.json")
        }
        let manifest = try decoder.decode(AdapterManifest.self, from: Data(contentsOf: url))
        try manifest.validate()
        return manifest
    }

    /// Loads a user override when it is valid; otherwise safely falls back to
    /// the signed manifest bundled with the application.
    public func loadDefault(overrideURL: URL?) throws -> AdapterManifest {
        let bundled = try loadDefault()
        guard let overrideURL, FileManager.default.fileExists(atPath: overrideURL.path) else {
            return bundled
        }
        do {
            let override = try load(url: overrideURL)
            guard override.adapterId == bundled.adapterId else { return bundled }
            return override
        } catch {
            return bundled
        }
    }

    public func load(url: URL) throws -> AdapterManifest {
        let manifest = try decoder.decode(AdapterManifest.self, from: Data(contentsOf: url))
        try manifest.validate()
        return manifest
    }
}

public struct PathResolver: Sendable {
    public init() {}

    public func expand(_ path: String) -> String {
        (path as NSString).expandingTildeInPath
    }

    public func firstExistingPath(from candidates: [String], fileManager: FileManager = .default) -> String? {
        candidates.map(expand).first { fileManager.fileExists(atPath: $0) }
    }

    public func shortVersion(at appPath: String?) -> String? {
        guard let appPath else { return nil }
        let infoURL = URL(fileURLWithPath: appPath).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        return dictionary["CFBundleShortVersionString"] as? String
    }
}

public enum VersionStatus: String, Codable, Sendable { case verified, untested, unsupported }

public struct VersionGate: Sendable {
    public init() {}

    public func status(version: String, compatibility: AdapterManifest.Compatibility) -> VersionStatus {
        if compatibility.unsupported.contains(version) { return .unsupported }
        if compatibility.verified.contains(version) { return .verified }
        return .untested
    }
}

public struct DoctorReport: Codable, Sendable {
    public let adapterId: String
    public let strategy: AdapterStrategy
    public let appPath: String?
    public let databasePath: String?
    public let ideVersion: String
    public let versionStatus: VersionStatus
    public let requiredIdentityKeyCount: Int
    public let profiles: [AccountProfile]
    public let activeProfileID: String?
    public let pendingTargetProfileID: String?
}

public struct Doctor {
    public init() {}

    public func report(
        manifest: AdapterManifest,
        ideVersion: String,
        resolver: PathResolver = .init(),
        profiles: [AccountProfile] = [],
        activeProfileID: String? = nil,
        pendingTargetProfileID: String? = nil
    ) -> DoctorReport {
        DoctorReport(
            adapterId: manifest.adapterId,
            strategy: manifest.strategy,
            appPath: resolver.firstExistingPath(from: manifest.app.pathCandidates),
            databasePath: resolver.firstExistingPath(from: manifest.storage.dbPathCandidates),
            ideVersion: ideVersion,
            versionStatus: VersionGate().status(version: ideVersion, compatibility: manifest.compat),
            requiredIdentityKeyCount: manifest.storage.identityKeys.required.count,
            profiles: profiles,
            activeProfileID: activeProfileID,
            pendingTargetProfileID: pendingTargetProfileID
        )
    }
}

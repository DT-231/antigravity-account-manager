import Foundation

public struct AccountProfile: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var userDataDir: String

    public init(id: String, name: String, userDataDir: String) {
        self.id = id
        self.name = name
        self.userDataDir = userDataDir
    }
}

public enum ProfileStoreError: LocalizedError {
    case duplicateID(String)
    case missingProfile(String)
    case invalidProfile(String)
    case activeProfile(String)
    case unsafeDeletion(String)

    public var errorDescription: String {
        switch self {
        case .duplicateID(let id): return "Profile already exists: \(id)"
        case .missingProfile(let id): return "Profile not found: \(id)"
        case .invalidProfile(let message): return "Invalid profile: \(message)"
        case .activeProfile(let id): return "Cannot remove active profile: \(id)"
        case .unsafeDeletion(let path): return "Refusing to delete unsafe profile path: \(path)"
        }
    }
}

public struct ProfileStore {
    public let fileURL: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.fileURL = fileURL ?? Self.defaultURL(fileManager: fileManager)
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
    }

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("AntigravitySwitcher/profiles.json")
    }

    public func list() throws -> [AccountProfile] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }
        return try decoder.decode([AccountProfile].self, from: Data(contentsOf: fileURL))
    }

    public func profile(id: String) throws -> AccountProfile {
        guard let profile = try list().first(where: { $0.id == id }) else {
            throw ProfileStoreError.missingProfile(id)
        }
        return profile
    }

    public func add(_ profile: AccountProfile) throws {
        guard !profile.id.isEmpty, !profile.name.isEmpty, !profile.userDataDir.isEmpty else {
            throw ProfileStoreError.invalidProfile("id, name and userDataDir are required")
        }
        var profiles = try list()
        guard !profiles.contains(where: { $0.id == profile.id }) else {
            throw ProfileStoreError.duplicateID(profile.id)
        }
        profiles.append(profile)
        try write(profiles)
    }

    public func rename(id: String, name: String) throws {
        guard !name.isEmpty else { throw ProfileStoreError.invalidProfile("name is empty") }
        var profiles = try list()
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            throw ProfileStoreError.missingProfile(id)
        }
        profiles[index].name = name
        try write(profiles)
    }

    /// Removes only the registry entry. The user-data directory is never deleted.
    public func remove(id: String) throws {
        var profiles = try list()
        guard profiles.contains(where: { $0.id == id }) else {
            throw ProfileStoreError.missingProfile(id)
        }
        profiles.removeAll { $0.id == id }
        try write(profiles)
    }

    public func removeData(for profile: AccountProfile) throws {
        let path = (profile.userDataDir as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let home = URL(fileURLWithPath: NSHomeDirectory()).standardizedFileURL
        guard url.path != "/", url.path != home.path, url.path.count > 8 else {
            throw ProfileStoreError.unsafeDeletion(url.path)
        }
        guard fileManager.fileExists(atPath: url.path) else { return }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ProfileStoreError.unsafeDeletion(url.path)
        }
        // Keep destructive removal recoverable. This removes the directory
        // from its active location while allowing restoration from Trash.
        try fileManager.trashItem(at: url, resultingItemURL: nil)
    }

    private func write(_ profiles: [AccountProfile]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(profiles)
        let temporaryURL = directory.appendingPathComponent(".profiles-\(UUID().uuidString).tmp")
        try data.write(to: temporaryURL, options: .completeFileProtectionUnlessOpen)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporaryURL.path)
        if fileManager.fileExists(atPath: fileURL.path) { try fileManager.removeItem(at: fileURL) }
        try fileManager.moveItem(at: temporaryURL, to: fileURL)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

public struct LaunchPlan: Equatable, Sendable {
    public let appPath: String
    public let arguments: [String]

    public init(appPath: String, arguments: [String]) {
        self.appPath = appPath
        self.arguments = arguments
    }
}

public struct PendingSwitch: Codable, Equatable, Sendable {
    public let previousProfileID: String?
    public let targetProfileID: String
    public let startedAt: Date

    public init(previousProfileID: String?, targetProfileID: String, startedAt: Date = Date()) {
        self.previousProfileID = previousProfileID
        self.targetProfileID = targetProfileID
        self.startedAt = startedAt
    }
}

public struct SwitchStateStore {
    public let activeURL: URL
    public let pendingURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        let directory = directoryURL ?? ProfileStore.defaultURL(fileManager: fileManager).deletingLastPathComponent()
        self.activeURL = directory.appendingPathComponent("active-profile.json")
        self.pendingURL = directory.appendingPathComponent("pending-switch.json")
        self.fileManager = fileManager
    }

    public func activeProfileID() throws -> String? {
        guard fileManager.fileExists(atPath: activeURL.path) else { return nil }
        struct Value: Codable { let profileID: String }
        return try decoder.decode(Value.self, from: Data(contentsOf: activeURL)).profileID
    }

    public func setActiveProfileID(_ id: String) throws {
        try write(Data(try encoder.encode(["profileID": id])), to: activeURL)
    }

    public func pendingSwitch() throws -> PendingSwitch? {
        guard fileManager.fileExists(atPath: pendingURL.path) else { return nil }
        return try decoder.decode(PendingSwitch.self, from: Data(contentsOf: pendingURL))
    }

    public func begin(_ pending: PendingSwitch) throws {
        try write(try encoder.encode(pending), to: pendingURL)
    }

    public func clearPending() throws {
        if fileManager.fileExists(atPath: pendingURL.path) { try fileManager.removeItem(at: pendingURL) }
    }

    private func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .completeFileProtectionUnlessOpen)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        try fileManager.moveItem(at: temporary, to: url)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public enum LaunchPlanError: LocalizedError {
    case appNotFound
    case profileDirectoryMissing(String)
    case invalidManifest(String)
    case unsupportedStrategy(AdapterStrategy)

    public var errorDescription: String {
        switch self {
        case .appNotFound: return "Antigravity IDE app was not found"
        case .profileDirectoryMissing(let path): return "Profile directory does not exist: \(path)"
        case .invalidManifest(let message): return "Invalid launch manifest: \(message)"
        case .unsupportedStrategy(let strategy): return "Launch plan does not support strategy: \(strategy.rawValue)"
        }
    }
}

public struct LaunchPlanner: Sendable {
    private let resolver: PathResolver

    public init(resolver: PathResolver = .init()) { self.resolver = resolver }

    public func plan(manifest: AdapterManifest, profile: AccountProfile, fileManager: FileManager = .default) throws -> LaunchPlan {
        guard let appPath = resolver.firstExistingPath(from: manifest.app.pathCandidates, fileManager: fileManager) else {
            throw LaunchPlanError.appNotFound
        }
        guard manifest.strategy == .userDataDir else {
            throw LaunchPlanError.unsupportedStrategy(manifest.strategy)
        }
        let profilePath = resolver.expand(profile.userDataDir)
        guard fileManager.fileExists(atPath: profilePath) else {
            throw LaunchPlanError.profileDirectoryMissing(profilePath)
        }
        guard let template = manifest.launch.userDataDirArgTemplate, !template.isEmpty else {
            throw LaunchPlanError.invalidManifest("userDataDirArgTemplate is required")
        }
        let arguments = (manifest.launch.extraArgs + template).map {
            $0.replacingOccurrences(of: "{path}", with: profilePath)
        }
        return LaunchPlan(appPath: appPath, arguments: arguments)
    }
}

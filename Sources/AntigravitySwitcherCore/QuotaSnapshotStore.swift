import Foundation

public struct AntigravityQuotaSnapshot: Identifiable, Codable, Equatable, Sendable {
    public var id: String { profileID }
    public let profileID: String
    public let name: String?
    public let email: String?
    public let planName: String?
    public let planTier: String?
    public let monthlyPromptCredits: Double?
    public let monthlyFlowCredits: Double?
    public let availablePromptCredits: Double?
    public let availableFlowCredits: Double?
    public let models: [AntigravityModelQuota]
    public let capturedAt: Date

    public init(profileID: String, quota: AntigravityAccountQuota) {
        self.profileID = profileID
        name = quota.name
        email = quota.email
        planName = quota.planName
        planTier = quota.planTier
        monthlyPromptCredits = quota.monthlyPromptCredits
        monthlyFlowCredits = quota.monthlyFlowCredits
        availablePromptCredits = quota.availablePromptCredits
        availableFlowCredits = quota.availableFlowCredits
        models = quota.models
        capturedAt = quota.fetchedAt
    }

    public init(
        profileID: String,
        name: String? = nil,
        email: String? = nil,
        planName: String? = nil,
        planTier: String? = nil,
        monthlyPromptCredits: Double? = nil,
        monthlyFlowCredits: Double? = nil,
        availablePromptCredits: Double? = nil,
        availableFlowCredits: Double? = nil,
        models: [AntigravityModelQuota],
        capturedAt: Date
    ) {
        self.profileID = profileID
        self.name = name
        self.email = email
        self.planName = planName
        self.planTier = planTier
        self.monthlyPromptCredits = monthlyPromptCredits
        self.monthlyFlowCredits = monthlyFlowCredits
        self.availablePromptCredits = availablePromptCredits
        self.availableFlowCredits = availableFlowCredits
        self.models = models
        self.capturedAt = capturedAt
    }
}

public struct QuotaSnapshotStore {
    private struct StoreFile: Codable {
        var schemaVersion = 1
        var snapshots: [String: AntigravityQuotaSnapshot]
    }

    public let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.fileURL = support
                .appendingPathComponent("AntigravitySwitcher", isDirectory: true)
                .appendingPathComponent("quota-snapshots.json")
        }
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadAll() throws -> [String: AntigravityQuotaSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        return try decoder.decode(StoreFile.self, from: Data(contentsOf: fileURL)).snapshots
    }

    public func save(_ snapshot: AntigravityQuotaSnapshot) throws {
        var snapshots = try loadAll()
        snapshots[snapshot.profileID] = snapshot
        try write(snapshots)
    }

    public func remove(profileID: String) throws {
        var snapshots = try loadAll()
        guard snapshots.removeValue(forKey: profileID) != nil else { return }
        try write(snapshots)
    }

    private func write(_ snapshots: [String: AntigravityQuotaSnapshot]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(StoreFile(snapshots: snapshots))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

import Foundation

public struct ProfileUsageStore: Sendable {
    private struct StoreFile: Codable {
        var schemaVersion = 1
        var lastUsedAt: [String: Date]
    }

    public let fileURL: URL

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileURL = fileURL
            ?? ProfileStore.defaultURL(fileManager: fileManager)
                .deletingLastPathComponent()
                .appendingPathComponent("profile-usage.json")
    }

    public func loadAll() throws -> [String: Date] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(StoreFile.self, from: Data(contentsOf: fileURL)).lastUsedAt
    }

    public func markUsed(profileID: String, at date: Date = Date()) throws {
        var values = try loadAll()
        values[profileID] = date
        try write(values)
    }

    public func remove(profileID: String) throws {
        var values = try loadAll()
        guard values.removeValue(forKey: profileID) != nil else { return }
        try write(values)
    }

    private func write(_ values: [String: Date]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(StoreFile(lastUsedAt: values))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

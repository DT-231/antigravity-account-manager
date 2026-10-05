import Foundation

public struct AccountProfileLinkStore: Sendable {
    private struct StoreFile: Codable {
        var schemaVersion = 1
        var links: [String: String]
    }

    public let fileURL: URL

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileURL = fileURL
            ?? ProfileStore.defaultURL(fileManager: fileManager)
                .deletingLastPathComponent()
                .appendingPathComponent("account-profile-links.json")
    }

    public func loadAll() throws -> [UUID: String] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        let stored = try JSONDecoder().decode(StoreFile.self, from: Data(contentsOf: fileURL))
        return Dictionary(uniqueKeysWithValues: stored.links.compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        })
    }

    public func setProfileID(_ profileID: String?, for accountID: UUID) throws {
        var values = try loadAll()
        values[accountID] = profileID
        try write(values)
    }

    public func removeLinks(toProfileID profileID: String) throws {
        var values = try loadAll()
        values = values.filter { $0.value != profileID }
        try write(values)
    }

    private func write(_ values: [UUID: String]) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stored = Dictionary(uniqueKeysWithValues: values.map { ($0.key.uuidString, $0.value) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(StoreFile(links: stored))
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

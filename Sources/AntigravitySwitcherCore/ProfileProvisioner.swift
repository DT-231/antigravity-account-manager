import Foundation

public enum ProfileProvisioningError: LocalizedError, Equatable, Sendable {
    case missingAccountIdentity
    case ideIdentityUnavailable
    case accountMismatch(expected: String, authenticated: String)

    public var errorDescription: String? {
        switch self {
        case .missingAccountIdentity:
            return "Tài khoản Google chưa có email hoặc định danh hợp lệ."
        case .ideIdentityUnavailable:
            return "Antigravity IDE chưa trả về email. Hãy hoàn tất đăng nhập trong IDE rồi thử lại."
        case .accountMismatch(let expected, let authenticated):
            return "Tài khoản trong IDE không khớp. Mong đợi: \(expected). Đã đăng nhập: \(authenticated)."
        }
    }
}

/// Creates an isolated user-data directory and registry entry. It never reads,
/// copies or modifies credentials belonging to Antigravity IDE.
public struct ProfileProvisioner {
    private let profileStore: ProfileStore
    private let baseDirectory: URL
    private let fileManager: FileManager

    public init(
        profileStore: ProfileStore = .init(),
        baseDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.profileStore = profileStore
        self.fileManager = fileManager
        if let baseDirectory {
            self.baseDirectory = baseDirectory
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.baseDirectory = support
                .appendingPathComponent("AntigravitySwitcher", isDirectory: true)
                .appendingPathComponent("profiles", isDirectory: true)
        }
    }

    public func createProfile(for account: ManagedAccount) throws -> AccountProfile {
        let displayName = normalized(account.email) ?? normalized(account.displayName)
        guard let displayName else { throw ProfileProvisioningError.missingAccountIdentity }

        if let existing = try profileStore.list().first(where: {
            normalized($0.name)?.caseInsensitiveCompare(displayName) == .orderedSame
        }) {
            return existing
        }

        try fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        let stem = slug(displayName)
        let existingIDs = Set(try profileStore.list().map(\.id))
        var profileID = "google-\(stem)"
        var suffix = 2
        while existingIDs.contains(profileID)
            || fileManager.fileExists(atPath: baseDirectory.appendingPathComponent(profileID).path) {
            profileID = "google-\(stem)-\(suffix)"
            suffix += 1
        }

        let directory = baseDirectory.appendingPathComponent(profileID, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let profile = AccountProfile(id: profileID, name: displayName, userDataDir: directory.path)
        do {
            try profileStore.add(profile)
            return profile
        } catch {
            // This directory was created by this operation and contains no IDE
            // state yet, so cleanup cannot remove user-owned session data.
            if (try? fileManager.contentsOfDirectory(atPath: directory.path).isEmpty) == true {
                try? fileManager.removeItem(at: directory)
            }
            throw error
        }
    }

    public static func validateIDEIdentity(
        account: ManagedAccount,
        authenticatedEmail: String?
    ) throws {
        guard let expected = normalized(account.email) else {
            throw ProfileProvisioningError.missingAccountIdentity
        }
        guard let authenticated = normalized(authenticatedEmail) else {
            throw ProfileProvisioningError.ideIdentityUnavailable
        }
        guard expected.caseInsensitiveCompare(authenticated) == .orderedSame else {
            throw ProfileProvisioningError.accountMismatch(
                expected: expected,
                authenticated: authenticated
            )
        }
    }

    private func slug(_ value: String) -> String {
        let lowered = value.lowercased()
        var result = ""
        var lastWasSeparator = false
        for scalar in lowered.unicodeScalars {
            let allowed = CharacterSet.alphanumerics.contains(scalar)
            if allowed {
                result.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator, !result.isEmpty {
                result.append("-")
                lastWasSeparator = true
            }
        }
        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "account" : String(trimmed.prefix(64))
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalized(_ value: String?) -> String? {
        Self.normalized(value)
    }
}

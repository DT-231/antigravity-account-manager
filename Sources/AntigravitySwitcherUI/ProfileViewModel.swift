import AntigravitySwitcherCore
import Foundation
import SwiftUI

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var profiles: [AccountProfile] = []
    @Published var managedAccounts: [ManagedAccount] = []
    @Published var activeProfileID: String?
    @Published var status = "Sẵn sàng"
    @Published var quota: AntigravityAccountQuota?
    @Published var quotaStatus = "Chưa có dữ liệu"
    @Published var quotaSnapshots: [String: AntigravityQuotaSnapshot] = [:]
    @Published var liveQuotaProfileID: String?
    @Published var doctorReport: DoctorReport?
    @Published var selfTestReport: ProfileSelfTestReport?
    @Published var diagnosticsStatus = "Chưa chạy chẩn đoán"
    @Published var isSwitching = false
    @Published var switchStage = ""
    @Published var profileLastUsedAt: [String: Date] = [:]
    @Published var accountProfileLinks: [UUID: String] = [:]

    private let store = ProfileStore()
    private let state = SwitchStateStore()
    private let quotaService = AntigravityQuotaService()
    private let quotaSnapshotStore = QuotaSnapshotStore()
    private let profileUsageStore = ProfileUsageStore()
    private let accountProfileLinkStore = AccountProfileLinkStore()
    private lazy var profileProvisioner = ProfileProvisioner(profileStore: store)
    private let switchCoordinator: SwitchCoordinator
    private var quotaRefreshInFlight = false

    init(switchCoordinator: SwitchCoordinator) {
        self.switchCoordinator = switchCoordinator
        reload()
        runDoctor()
        refreshQuota()
    }

    func runDoctor() {
        do {
            let manifest = try ManifestLoader().loadDefault()
            let resolver = PathResolver()
            let appPath = resolver.firstExistingPath(from: manifest.app.pathCandidates)
            let version = resolver.shortVersion(at: appPath) ?? "unknown"
            doctorReport = Doctor().report(
                manifest: manifest,
                ideVersion: version,
                resolver: resolver,
                profiles: profiles,
                activeProfileID: activeProfileID,
                pendingTargetProfileID: try state.pendingSwitch()?.targetProfileID
            )
            diagnosticsStatus = "Doctor hoàn tất"
        } catch {
            doctorReport = nil
            diagnosticsStatus = "Doctor lỗi: \(error.localizedDescription)"
        }
    }

    func runSelfTest() {
        do {
            let manifest = try ManifestLoader().loadDefault()
            let resolver = PathResolver()
            let appPath = resolver.firstExistingPath(from: manifest.app.pathCandidates)
            let version = resolver.shortVersion(at: appPath) ?? "unknown"
            selfTestReport = ProfileSelfTester().run(
                manifest: manifest,
                ideVersion: version,
                profiles: profiles,
                activeProfileID: activeProfileID,
                pendingSwitch: try state.pendingSwitch(),
                resolver: resolver
            )
            diagnosticsStatus = selfTestReport?.passed == true ? "Selftest đạt" : "Selftest phát hiện lỗi"
        } catch {
            selfTestReport = nil
            diagnosticsStatus = "Selftest lỗi: \(error.localizedDescription)"
        }
    }

    func explainCalibration() {
        do {
            let manifest = try ManifestLoader().loadDefault()
            diagnosticsStatus = manifest.strategy == .userDataDir
                ? "Calibrate không cần thiết: mỗi account dùng user-data-dir riêng."
                : "Calibrate chưa khả dụng cho strategy \(manifest.strategy.rawValue)."
        } catch {
            diagnosticsStatus = error.localizedDescription
        }
    }

    func refreshQuota() {
        guard !quotaRefreshInFlight else { return }
        quotaRefreshInFlight = true
        Task { [weak self] in
            guard let self else { return }
            defer { quotaRefreshInFlight = false }
            do {
                let value = try await quotaService.fetchCurrentQuota()
                quota = value
                let normalizedEmail = value.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                let matchedProfileID = profiles.first {
                    $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedEmail
                }?.id
                let snapshotProfileID = matchedProfileID ?? activeProfileID
                if let snapshotProfileID {
                    let snapshot = AntigravityQuotaSnapshot(profileID: snapshotProfileID, quota: value)
                    liveQuotaProfileID = snapshotProfileID
                    quotaSnapshots[snapshotProfileID] = snapshot
                    do {
                        try quotaSnapshotStore.save(snapshot)
                    } catch {
                        status = "Quota live hoạt động nhưng chưa lưu được snapshot: \(error.localizedDescription)"
                    }
                }
                quotaStatus = "Đã cập nhật \(value.email ?? "tài khoản đang dùng")"
            } catch {
                quota = nil
                liveQuotaProfileID = nil
                quotaStatus = error.localizedDescription
            }
        }
    }

    func reload() {
        do {
            profiles = try store.list()
            activeProfileID = try state.activeProfileID()
            quotaSnapshots = (try? quotaSnapshotStore.loadAll()) ?? [:]
            profileLastUsedAt = (try? profileUsageStore.loadAll()) ?? [:]
            accountProfileLinks = (try? accountProfileLinkStore.loadAll()) ?? [:]
            refreshManagedAccounts()
            NotificationCenter.default.post(name: .agProfilesDidChange, object: nil)
        } catch {
            status = error.localizedDescription
        }
    }

    func refreshManagedAccounts() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let databaseURL = appSupport.appendingPathComponent("AntigravitySwitcher/accounts.sqlite")
        do {
            try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            managedAccounts = try SQLiteAccountStore(url: databaseURL).fetchAll()
            let keychain = MacKeychainStore()
            for account in managedAccounts {
                try? keychain.migrateLegacySecretIfNeeded(account: account.tokenKeychainReference)
            }
        } catch {
            managedAccounts = []
        }
    }

    func switchTo(_ profile: AccountProfile) {
        guard !isSwitching else { return }
        isSwitching = true
        switchStage = "Đang chuẩn bị…"
        status = "Đang chuyển sang \(profile.name)…"
        Task { [weak self] in
            guard let self else { return }
            defer {
                isSwitching = false
                switchStage = ""
            }
            do {
                let result = try await switchCoordinator.switchProfile(to: profile) { [weak self] stage in
                    self?.switchStage = stage.localizedDescription
                }
                activeProfileID = result.activeProfileID
                profileLastUsedAt = (try? profileUsageStore.loadAll()) ?? profileLastUsedAt
                selectedQuotaAfterSwitch()
                status = "Đang chạy: \(profile.name)"
                NotificationCenter.default.post(name: .agProfilesDidChange, object: nil)
            } catch {
                activeProfileID = try? state.activeProfileID()
                profileLastUsedAt = (try? profileUsageStore.loadAll()) ?? profileLastUsedAt
                status = "Chuyển profile thất bại: \(error.localizedDescription)"
            }
        }
    }

    func openIDE(with profile: AccountProfile) {
        guard !isSwitching else { return }
        guard activeProfileID == nil || profile.id == activeProfileID else {
            status = "Hãy chuyển sang profile này trước khi mở IDE."
            return
        }
        isSwitching = true
        switchStage = "Đang mở IDE…"
        status = "Đang mở IDE: \(profile.name)…"
        Task { [weak self] in
            guard let self else { return }
            defer {
                isSwitching = false
                switchStage = ""
            }
            do {
                try await switchCoordinator.openProfile(profile)
                activeProfileID = profile.id
                profileLastUsedAt = (try? profileUsageStore.loadAll()) ?? profileLastUsedAt
                status = "Đã mở IDE: \(profile.name)"
                NotificationCenter.default.post(name: .agProfilesDidChange, object: nil)
            } catch {
                status = "Không thể mở IDE: \(error.localizedDescription)"
            }
        }
    }

    func createProfile(for account: ManagedAccount) throws -> AccountProfile {
        if let linked = localProfile(for: account) { return linked }
        let profile = try profileProvisioner.createProfile(for: account)
        reload()
        status = "Đã tạo profile riêng cho \(account.email ?? account.displayName)"
        return profile
    }

    func activateProfileForSetup(_ profile: AccountProfile) async throws {
        guard !isSwitching else { throw SwitchCoordinatorError.alreadySwitching }
        isSwitching = true
        switchStage = "Đang mở profile mới…"
        status = "Đang mở IDE để đăng nhập: \(profile.name)…"
        defer {
            isSwitching = false
            switchStage = ""
        }

        if activeProfileID == profile.id {
            try await switchCoordinator.openProfile(profile)
        } else {
            let result = try await switchCoordinator.switchProfile(to: profile) { [weak self] stage in
                self?.switchStage = stage.localizedDescription
            }
            activeProfileID = result.activeProfileID
        }
        profileLastUsedAt = (try? profileUsageStore.loadAll()) ?? profileLastUsedAt
        selectedQuotaAfterSwitch()
        status = "Hãy hoàn tất đăng nhập trong Antigravity IDE"
        NotificationCenter.default.post(name: .agProfilesDidChange, object: nil)
    }

    @discardableResult
    func verifyIDELogin(
        account: ManagedAccount,
        profile: AccountProfile
    ) async throws -> AntigravityAccountQuota {
        await quotaService.invalidateRuntimeServer()
        guard let expectedEmail = account.email else {
            throw ProfileProvisioningError.missingAccountIdentity
        }
        let value = try await quotaService.fetchQuota(matchingEmail: expectedEmail)
        try ProfileProvisioner.validateIDEIdentity(
            account: account,
            authenticatedEmail: value.email
        )

        try accountProfileLinkStore.setProfileID(profile.id, for: account.id)
        accountProfileLinks = try accountProfileLinkStore.loadAll()
        let snapshot = AntigravityQuotaSnapshot(profileID: profile.id, quota: value)
        try quotaSnapshotStore.save(snapshot)
        quotaSnapshots[profile.id] = snapshot
        quota = value
        liveQuotaProfileID = profile.id
        quotaStatus = "Đã xác minh \(value.email ?? profile.name)"
        status = "Đã thêm và xác minh account: \(value.email ?? profile.name)"
        NotificationCenter.default.post(name: .agProfilesDidChange, object: nil)
        return value
    }

    private func selectedQuotaAfterSwitch() {
        liveQuotaProfileID = nil
        quota = nil
        quotaStatus = "Đang chờ quota của profile mới"
    }

    func rename(_ profile: AccountProfile, to name: String) {
        do { try store.rename(id: profile.id, name: name); reload() }
        catch { status = error.localizedDescription }
    }

    func deleteProfileAndData(_ profile: AccountProfile) {
        guard activeProfileID != profile.id else {
            status = "Không thể xóa profile đang dùng. Hãy chuyển sang profile khác trước."
            return
        }
        do {
            try store.removeData(for: profile)
            try store.remove(id: profile.id)
            try quotaSnapshotStore.remove(profileID: profile.id)
            try profileUsageStore.remove(profileID: profile.id)
            try accountProfileLinkStore.removeLinks(toProfileID: profile.id)
            reload()
            status = "Đã xóa profile; dữ liệu đã được chuyển vào Thùng rác: \(profile.name)"
        } catch {
            status = "Không thể xóa profile: \(error.localizedDescription)"
        }
    }

    func quotaSnapshot(for profileID: String?) -> AntigravityQuotaSnapshot? {
        guard let profileID else { return nil }
        return quotaSnapshots[profileID]
    }

    func removeManagedAccount(_ account: ManagedAccount) {
        do {
            let keychain = MacKeychainStore()
            try keychain.deleteSecret(service: MacKeychainStore.service, account: account.tokenKeychainReference)
            for legacyService in MacKeychainStore.legacyServices {
                try? keychain.deleteSecret(service: legacyService, account: account.tokenKeychainReference)
            }
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            let databaseURL = appSupport.appendingPathComponent("AntigravitySwitcher/accounts.sqlite")
            try SQLiteAccountStore(url: databaseURL).delete(id: account.id)
            try accountProfileLinkStore.setProfileID(nil, for: account.id)
            refreshManagedAccounts()
            status = "Đã xóa tài khoản Google: \(account.email ?? account.displayName)"
        } catch {
            status = "Không thể xóa tài khoản Google: \(error.localizedDescription)"
        }
    }

    func localProfile(for account: ManagedAccount) -> AccountProfile? {
        if let linkedID = accountProfileLinks[account.id],
           let linked = profiles.first(where: { $0.id == linkedID }) {
            return linked
        }
        return nil
    }

    func managedAccount(for profile: AccountProfile) -> ManagedAccount? {
        managedAccounts.first { localProfile(for: $0)?.id == profile.id }
    }

    func link(_ account: ManagedAccount, to profile: AccountProfile?) {
        do {
            try accountProfileLinkStore.setProfileID(profile?.id, for: account.id)
            accountProfileLinks = try accountProfileLinkStore.loadAll()
            status = profile.map { "Đã liên kết \(account.email ?? account.displayName) với \($0.name)" }
                ?? "Đã bỏ liên kết profile"
        } catch {
            status = "Không thể lưu liên kết profile: \(error.localizedDescription)"
        }
    }
}

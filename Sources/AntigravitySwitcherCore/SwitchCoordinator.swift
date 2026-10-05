import Foundation

public enum ProfileSwitchStage: String, Sendable {
    case validating
    case recovering
    case quitting
    case launching
    case waitingUntilReady
    case rollingBack
    case completed

    public var localizedDescription: String {
        switch self {
        case .validating: return "Đang kiểm tra cấu hình…"
        case .recovering: return "Đang khôi phục lần chuyển trước…"
        case .quitting: return "Đang đóng Antigravity IDE…"
        case .launching: return "Đang mở profile…"
        case .waitingUntilReady: return "Đang chờ IDE sẵn sàng…"
        case .rollingBack: return "Có lỗi · đang hoàn tác…"
        case .completed: return "Đã chuyển profile"
        }
    }
}

public struct ProfileSwitchResult: Equatable, Sendable {
    public let previousProfileID: String?
    public let activeProfileID: String

    public init(previousProfileID: String?, activeProfileID: String) {
        self.previousProfileID = previousProfileID
        self.activeProfileID = activeProfileID
    }
}

public enum SwitchCoordinatorError: LocalizedError, Equatable, Sendable {
    case alreadySwitching
    case versionNotVerified(String)
    case profileSwitchRequired

    public var errorDescription: String? {
        switch self {
        case .alreadySwitching:
            return "Một lần chuyển profile khác đang chạy"
        case .versionNotVerified(let version):
            return "Phiên bản Antigravity IDE \(version) chưa được kiểm chứng"
        case .profileSwitchRequired:
            return "Hãy chuyển sang profile này trước khi mở IDE"
        }
    }
}

/// Owns the complete switch transaction for the native UI and menu bar.
/// The CLI uses the synchronous entry point below but shares the same
/// validation, pending-state, rollback and usage-update rules.
@MainActor
public final class SwitchCoordinator {
    private let profileStore: ProfileStore
    private let stateStore: SwitchStateStore
    private let usageStore: ProfileUsageStore
    private let processController: ProcessController
    private var isSwitching = false

    public init(
        profileStore: ProfileStore = .init(),
        stateStore: SwitchStateStore = .init(),
        usageStore: ProfileUsageStore = .init(),
        processController: ProcessController = .init()
    ) {
        self.profileStore = profileStore
        self.stateStore = stateStore
        self.usageStore = usageStore
        self.processController = processController
    }

    public func switchProfile(
        to profile: AccountProfile,
        onStage: (ProfileSwitchStage) -> Void = { _ in }
    ) async throws -> ProfileSwitchResult {
        guard !isSwitching else { throw SwitchCoordinatorError.alreadySwitching }
        isSwitching = true
        defer { isSwitching = false }

        onStage(.validating)
        let prepared = try Self.prepare(profile: profile)
        try await recoverPendingIfNeeded(manifest: prepared.manifest, onStage: onStage)
        let previousID = try stateStore.activeProfileID()
        try stateStore.begin(PendingSwitch(previousProfileID: previousID, targetProfileID: profile.id))

        do {
            onStage(.quitting)
            _ = try await processController.quitAsync(
                bundleId: prepared.manifest.process.rootMatch.bundleId,
                timeout: TimeInterval(prepared.manifest.process.quitTimeoutSec),
                forceAfterTimeout: true
            )
            onStage(.launching)
            try await processController.launchAsync(
                appPath: prepared.plan.appPath,
                arguments: prepared.plan.arguments
            )
            onStage(.waitingUntilReady)
            try await processController.waitUntilRunningAsync(
                bundleId: prepared.manifest.process.rootMatch.bundleId,
                timeout: TimeInterval(prepared.manifest.process.readyTimeoutSec)
            )
            try stateStore.setActiveProfileID(profile.id)
            try stateStore.clearPending()
            try usageStore.markUsed(profileID: profile.id)
            onStage(.completed)
            return ProfileSwitchResult(previousProfileID: previousID, activeProfileID: profile.id)
        } catch {
            onStage(.rollingBack)
            await rollback(to: previousID, manifest: prepared.manifest)
            throw error
        }
    }

    /// Activates an existing IDE process or opens the active profile. It never
    /// opens a second profile beside a different active one.
    public func openProfile(_ profile: AccountProfile) async throws {
        let prepared = try Self.prepare(profile: profile)
        let activeID = try stateStore.activeProfileID()
        guard activeID == nil || activeID == profile.id else {
            throw SwitchCoordinatorError.profileSwitchRequired
        }
        if processController.activateRunning(bundleId: prepared.manifest.process.rootMatch.bundleId) {
            return
        }
        try await processController.launchAsync(
            appPath: prepared.plan.appPath,
            arguments: prepared.plan.arguments
        )
        try await processController.waitUntilRunningAsync(
            bundleId: prepared.manifest.process.rootMatch.bundleId,
            timeout: TimeInterval(prepared.manifest.process.readyTimeoutSec)
        )
        try stateStore.setActiveProfileID(profile.id)
        try usageStore.markUsed(profileID: profile.id)
    }

    public nonisolated static func switchSynchronously(
        to profile: AccountProfile,
        profileStore: ProfileStore = .init(),
        stateStore: SwitchStateStore = .init(),
        usageStore: ProfileUsageStore = .init(),
        processController: ProcessController = .init()
    ) throws -> ProfileSwitchResult {
        let prepared = try prepare(profile: profile)
        try recoverPendingSynchronously(
            manifest: prepared.manifest,
            profileStore: profileStore,
            stateStore: stateStore,
            usageStore: usageStore,
            processController: processController
        )
        let previousID = try stateStore.activeProfileID()
        try stateStore.begin(PendingSwitch(previousProfileID: previousID, targetProfileID: profile.id))
        do {
            _ = try processController.quit(
                bundleId: prepared.manifest.process.rootMatch.bundleId,
                timeout: TimeInterval(prepared.manifest.process.quitTimeoutSec),
                forceAfterTimeout: true
            )
            try processController.launch(appPath: prepared.plan.appPath, arguments: prepared.plan.arguments)
            try processController.waitUntilRunning(
                bundleId: prepared.manifest.process.rootMatch.bundleId,
                timeout: TimeInterval(prepared.manifest.process.readyTimeoutSec)
            )
            try stateStore.setActiveProfileID(profile.id)
            try stateStore.clearPending()
            try usageStore.markUsed(profileID: profile.id)
            return ProfileSwitchResult(previousProfileID: previousID, activeProfileID: profile.id)
        } catch {
            rollbackSynchronously(
                to: previousID,
                manifest: prepared.manifest,
                profileStore: profileStore,
                stateStore: stateStore,
                usageStore: usageStore,
                processController: processController
            )
            throw error
        }
    }

    public nonisolated static func validatedPlan(for profile: AccountProfile) throws -> LaunchPlan {
        try prepare(profile: profile).plan
    }

    private struct PreparedSwitch {
        let manifest: AdapterManifest
        let plan: LaunchPlan
    }

    private nonisolated static func prepare(profile: AccountProfile) throws -> PreparedSwitch {
        let manifest = try ManifestLoader().loadDefault()
        let resolver = PathResolver()
        let appPath = resolver.firstExistingPath(from: manifest.app.pathCandidates)
        let version = resolver.shortVersion(at: appPath) ?? "unknown"
        guard VersionGate().status(version: version, compatibility: manifest.compat) == .verified else {
            throw SwitchCoordinatorError.versionNotVerified(version)
        }
        return PreparedSwitch(
            manifest: manifest,
            plan: try LaunchPlanner().plan(manifest: manifest, profile: profile)
        )
    }

    private func recoverPendingIfNeeded(
        manifest: AdapterManifest,
        onStage: (ProfileSwitchStage) -> Void
    ) async throws {
        guard let pending = try stateStore.pendingSwitch() else { return }
        guard let previousID = pending.previousProfileID else {
            try stateStore.clearPending()
            return
        }
        onStage(.recovering)
        let previous = try profileStore.profile(id: previousID)
        let plan = try LaunchPlanner().plan(manifest: manifest, profile: previous)
        _ = try await processController.quitAsync(
            bundleId: manifest.process.rootMatch.bundleId,
            timeout: 5,
            forceAfterTimeout: true
        )
        try await processController.launchAsync(appPath: plan.appPath, arguments: plan.arguments)
        try await processController.waitUntilRunningAsync(
            bundleId: manifest.process.rootMatch.bundleId,
            timeout: 20
        )
        try stateStore.setActiveProfileID(previousID)
        try stateStore.clearPending()
        try usageStore.markUsed(profileID: previousID)
    }

    private func rollback(to previousID: String?, manifest: AdapterManifest) async {
        defer { try? stateStore.clearPending() }
        guard let previousID,
              let previous = try? profileStore.profile(id: previousID),
              let plan = try? LaunchPlanner().plan(manifest: manifest, profile: previous) else { return }
        _ = try? await processController.quitAsync(
            bundleId: manifest.process.rootMatch.bundleId,
            timeout: 5,
            forceAfterTimeout: true
        )
        try? await processController.launchAsync(appPath: plan.appPath, arguments: plan.arguments)
        try? await processController.waitUntilRunningAsync(
            bundleId: manifest.process.rootMatch.bundleId,
            timeout: 20
        )
        try? stateStore.setActiveProfileID(previousID)
        try? usageStore.markUsed(profileID: previousID)
    }

    private nonisolated static func recoverPendingSynchronously(
        manifest: AdapterManifest,
        profileStore: ProfileStore,
        stateStore: SwitchStateStore,
        usageStore: ProfileUsageStore,
        processController: ProcessController
    ) throws {
        guard let pending = try stateStore.pendingSwitch() else { return }
        guard let previousID = pending.previousProfileID else {
            try stateStore.clearPending()
            return
        }
        let previous = try profileStore.profile(id: previousID)
        let plan = try LaunchPlanner().plan(manifest: manifest, profile: previous)
        _ = try processController.quit(
            bundleId: manifest.process.rootMatch.bundleId,
            timeout: 5,
            forceAfterTimeout: true
        )
        try processController.launch(appPath: plan.appPath, arguments: plan.arguments)
        try processController.waitUntilRunning(
            bundleId: manifest.process.rootMatch.bundleId,
            timeout: 20
        )
        try stateStore.setActiveProfileID(previousID)
        try stateStore.clearPending()
        try usageStore.markUsed(profileID: previousID)
    }

    private nonisolated static func rollbackSynchronously(
        to previousID: String?,
        manifest: AdapterManifest,
        profileStore: ProfileStore,
        stateStore: SwitchStateStore,
        usageStore: ProfileUsageStore,
        processController: ProcessController
    ) {
        defer { try? stateStore.clearPending() }
        guard let previousID,
              let previous = try? profileStore.profile(id: previousID),
              let plan = try? LaunchPlanner().plan(manifest: manifest, profile: previous) else { return }
        _ = try? processController.quit(
            bundleId: manifest.process.rootMatch.bundleId,
            timeout: 5,
            forceAfterTimeout: true
        )
        try? processController.launch(appPath: plan.appPath, arguments: plan.arguments)
        try? processController.waitUntilRunning(
            bundleId: manifest.process.rootMatch.bundleId,
            timeout: 20
        )
        try? stateStore.setActiveProfileID(previousID)
        try? usageStore.markUsed(profileID: previousID)
    }
}

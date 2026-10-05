import Foundation

public enum DiagnosticCheckStatus: String, Codable, Sendable {
    case passed
    case warning
    case failed
}

public struct DiagnosticCheck: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let status: DiagnosticCheckStatus

    public init(id: String, title: String, detail: String, status: DiagnosticCheckStatus) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
    }
}

public struct ProfileSelfTestReport: Codable, Equatable, Sendable {
    public let ranAt: Date
    public let checks: [DiagnosticCheck]
    public var passed: Bool { !checks.contains { $0.status == .failed } }

    public init(ranAt: Date = Date(), checks: [DiagnosticCheck]) {
        self.ranAt = ranAt
        self.checks = checks
    }
}

public struct ProfileSelfTester: Sendable {
    public init() {}

    public func run(
        manifest: AdapterManifest,
        ideVersion: String,
        profiles: [AccountProfile],
        activeProfileID: String?,
        pendingSwitch: PendingSwitch?,
        resolver: PathResolver = .init(),
        fileManager: FileManager = .default
    ) -> ProfileSelfTestReport {
        var checks: [DiagnosticCheck] = []
        let appPath = resolver.firstExistingPath(from: manifest.app.pathCandidates, fileManager: fileManager)
        checks.append(DiagnosticCheck(
            id: "app",
            title: "Ứng dụng IDE",
            detail: appPath ?? "Không tìm thấy Antigravity IDE",
            status: appPath == nil ? .failed : .passed
        ))

        let versionStatus = VersionGate().status(version: ideVersion, compatibility: manifest.compat)
        checks.append(DiagnosticCheck(
            id: "version",
            title: "Phiên bản IDE",
            detail: "\(ideVersion) · \(versionStatus.rawValue)",
            status: versionStatus == .verified ? .passed : (versionStatus == .unsupported ? .failed : .warning)
        ))

        checks.append(DiagnosticCheck(
            id: "strategy",
            title: "Chiến lược profile",
            detail: manifest.strategy.rawValue,
            status: manifest.strategy == .userDataDir ? .passed : .warning
        ))

        checks.append(DiagnosticCheck(
            id: "profiles",
            title: "Local profiles",
            detail: "\(profiles.count) profile",
            status: profiles.isEmpty ? .warning : .passed
        ))

        for profile in profiles {
            let path = resolver.expand(profile.userDataDir)
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
            let planWorks = (try? LaunchPlanner(resolver: resolver).plan(
                manifest: manifest,
                profile: profile,
                fileManager: fileManager
            )) != nil
            let stateDatabase = URL(fileURLWithPath: path)
                .appendingPathComponent("User/globalStorage/state.vscdb")
            let hasStateDatabase = fileManager.fileExists(atPath: stateDatabase.path)
            let checkStatus: DiagnosticCheckStatus = !exists || !planWorks
                ? .failed
                : (hasStateDatabase ? .passed : .warning)
            let detail = !exists
                ? "Thiếu thư mục: \(path)"
                : (hasStateDatabase ? path : "Chưa có state.vscdb; profile có thể chưa đăng nhập")
            checks.append(DiagnosticCheck(
                id: "profile.\(profile.id)",
                title: profile.name,
                detail: detail,
                status: checkStatus
            ))
        }

        if let activeProfileID {
            let known = profiles.contains { $0.id == activeProfileID }
            checks.append(DiagnosticCheck(
                id: "active-profile",
                title: "Profile đang dùng",
                detail: activeProfileID,
                status: known ? .passed : .failed
            ))
        }

        checks.append(DiagnosticCheck(
            id: "pending-switch",
            title: "Switch dang dở",
            detail: pendingSwitch == nil ? "Không có" : "Đang chờ: \(pendingSwitch!.targetProfileID)",
            status: pendingSwitch == nil ? .passed : .warning
        ))

        return ProfileSelfTestReport(checks: checks)
    }
}

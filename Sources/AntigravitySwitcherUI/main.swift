import AppKit
import AntigravitySwitcherCore
import SwiftUI

func displayQuotaNumber(_ value: Double?) -> String {
    guard let value else { return "Chưa có số liệu" }
    return value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
}

extension Notification.Name {
    static let agProfilesDidChange = Notification.Name("AntigravitySwitcher.profilesDidChange")
}

struct StyledManagerView: View {
    @ObservedObject var model: ProfileViewModel
    @State private var selectedID: String?
    @State private var showAdd = false
    @State private var managedAccountToDelete: ManagedAccount?
    @State private var managedAccountToSetUp: ManagedAccount?
    @State private var profileToDelete: AccountProfile?
    @State private var profileToSwitch: AccountProfile?
    @State private var profileToRename: AccountProfile?
    @State private var renameValue = ""
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                brandIcon
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text("AG Switcher").font(.headline)
                    Text("Quản lý tài khoản Antigravity")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Picker("Khu vực", selection: $selectedTab) {
                    Text("Tổng quan").tag(0)
                    Text("Tài khoản").tag(1)
                    Text("Chẩn đoán").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)

                Spacer()

                Label(model.quota == nil ? "Chưa có quota" : "IDE đang hoạt động", systemImage: model.quota == nil ? "circle.dashed" : "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(model.quota == nil ? Color.secondary : Color.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background((model.quota == nil ? Color.gray : Color.green).opacity(0.10), in: Capsule())

                Button { startAdd() } label: {
                    Label("Thêm account", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .tint(AGTheme.accent)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(headerBackground)

            Divider()

            if let report = model.doctorReport, report.versionStatus != .verified {
                versionGateBanner(report)
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
            }

            Group {
                switch selectedTab {
                case 1: accounts
                case 2: diagnostics
                default: overview
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AGTheme.canvas)
        .frame(minWidth: 980, minHeight: 620)
        .preferredColorScheme(.light)
        .onAppear {
            if selectedID == nil { selectedID = model.activeProfileID ?? model.profiles.first?.id }
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { break }
                model.refreshQuota()
            }
        }
        .sheet(isPresented: $showAdd) { addAccountSheet }
        .sheet(item: $profileToRename) { profile in
            renameProfileSheet(profile)
        }
        .sheet(item: $managedAccountToSetUp) { account in
            AccountProfileSetupSheet(
                account: account,
                createProfile: { try model.createProfile(for: $0) },
                openProfile: { try await model.activateProfileForSetup($0) },
                verifyLogin: { try await model.verifyIDELogin(account: $0, profile: $1) },
                onComplete: { model.reload() }
            )
        }
        .alert(item: $managedAccountToDelete) { account in
            Alert(
                title: Text("Xóa tài khoản Google?"),
                message: Text("Thông tin tài khoản và credential đã lưu của \(account.email ?? account.displayName) sẽ bị xóa."),
                primaryButton: .destructive(Text("Xóa")) {
                    model.removeManagedAccount(account)
                },
                secondaryButton: .cancel()
            )
        }
        .alert(item: $profileToDelete) { profile in
            Alert(
                title: Text("Xóa profile \(profile.name)?"),
                message: Text("Thao tác này xóa đăng ký và chuyển toàn bộ dữ liệu tại:\n\(profile.userDataDir)\n\nvào Thùng rác để có thể khôi phục."),
                primaryButton: .destructive(Text("Xóa và chuyển vào Thùng rác")) {
                    model.deleteProfileAndData(profile)
                    if selectedID == profile.id {
                        selectedID = model.activeProfileID ?? model.profiles.first?.id
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .confirmationDialog(
            "Chuyển sang profile khác?",
            isPresented: Binding(
                get: { profileToSwitch != nil },
                set: { if !$0 { profileToSwitch = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let profile = profileToSwitch {
                Button("Đã lưu công việc · Chuyển sang \(profile.name)") {
                    profileToSwitch = nil
                    model.switchTo(profile)
                }
            }
            Button("Hủy", role: .cancel) { profileToSwitch = nil }
        } message: {
            Text("Antigravity IDE sẽ được đóng và mở lại. Hãy lưu mọi file đang chỉnh sửa trước khi tiếp tục.")
        }
    }

    @ViewBuilder
    private var brandIcon: some View {
        if let image = AGAssets.brandIcon {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(LinearGradient(colors: [AGTheme.accent, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder
    private var headerBackground: some View {
        ZStack {
            AGTheme.card
            if let image = AGAssets.splashHero {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .saturation(0.85)
                    .opacity(0.10)
                LinearGradient(
                    colors: [AGTheme.card.opacity(0.72), AGTheme.card.opacity(0.94)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        }
        .clipped()
    }

    private var selectedProfile: AccountProfile? {
        model.profiles.first { $0.id == selectedID }
    }

    private var linkedProfileIDs: Set<String> {
        Set(model.managedAccounts.compactMap { model.localProfile(for: $0)?.id })
    }

    private var unlinkedProfiles: [AccountProfile] {
        model.profiles.filter { !linkedProfileIDs.contains($0.id) }
    }

    private var selectedProfileIDForQuota: String? {
        selectedID ?? model.activeProfileID
    }

    private var selectedQuotaSnapshot: AntigravityQuotaSnapshot? {
        model.quotaSnapshot(for: selectedProfileIDForQuota)
    }

    private var selectedQuotaIsLive: Bool {
        selectedProfileIDForQuota != nil && selectedProfileIDForQuota == model.liveQuotaProfileID
    }

    private var ideStatusValue: String {
        guard let report = model.doctorReport else { return "Chưa xác định" }
        let label: String
        switch report.versionStatus {
        case .verified: label = "Đã kiểm chứng"
        case .untested: label = "Chưa kiểm chứng"
        case .unsupported: label = "Không hỗ trợ"
        }
        return "\(report.ideVersion) · \(label)"
    }

    private var ideStatusColor: Color {
        guard let status = model.doctorReport?.versionStatus else { return .secondary }
        switch status {
        case .verified: return .green
        case .untested: return .orange
        case .unsupported: return .red
        }
    }

    private var ideStatusIcon: String {
        model.doctorReport?.versionStatus == .verified
            ? "checkmark.shield.fill"
            : "exclamationmark.shield.fill"
    }

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tổng quan").font(.title2.bold())
                    Text("Theo dõi tài khoản và quota của Antigravity IDE")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    statusCard(title: "TÀI KHOẢN ĐANG CHỌN", value: selectedProfile?.name ?? "Chưa có", icon: "person.crop.circle.fill", color: AGTheme.accent)
                    statusCard(title: "IDE", value: ideStatusValue, icon: ideStatusIcon, color: ideStatusColor)
                    statusCard(title: "PHIÊN", value: selectedProfile == nil ? "Chưa cấu hình" : "Ổn định", icon: "lock.shield.fill", color: .blue)
                }
                QuotaSectionView(model: model, selectedProfileID: selectedProfileIDForQuota)

                HStack(alignment: .top, spacing: 10) {
                    sectionCard(title: "Trạng thái hệ thống", icon: "waveform.path.ecg") {
                        VStack(alignment: .leading, spacing: 6) {
                            diagnosticLine("Adapter", "antigravity-ide", true)
                            diagnosticLine("Strategy", "user-data-dir", true)
                            diagnosticLine("Profiles", "\(model.profiles.count)", true)
                            diagnosticLine("Thao tác gần nhất", model.status, true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    sectionCard(title: "Tài khoản Google", icon: "person.2.fill") {
                        if model.managedAccounts.isEmpty {
                            Text("Chưa có account OAuth")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(model.managedAccounts) { account in
                                    HStack {
                                        AccountAvatarView(
                                            name: account.email ?? account.displayName,
                                            avatarURL: account.avatarURL,
                                            size: 28
                                        )
                                        VStack(alignment: .leading) {
                                            Text(account.email ?? account.displayName).lineLimit(1)
                                            Text(account.status.rawValue).font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private var accounts: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TÀI KHOẢN").font(.caption.bold()).foregroundStyle(.secondary)
                    Spacer()
                    Button { startAdd() } label: { Image(systemName: "plus") }
                        .buttonStyle(.borderless)
                }
                if !model.managedAccounts.isEmpty {
                    Text("TÀI KHOẢN GOOGLE")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ForEach(model.managedAccounts) { account in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                AccountAvatarView(
                                    name: account.email ?? account.displayName,
                                    avatarURL: account.avatarURL,
                                    size: 30
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.email ?? account.displayName)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Text(account.status.rawValue)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Menu {
                                    if model.localProfile(for: account) == nil {
                                        Button {
                                            managedAccountToSetUp = account
                                        } label: {
                                            Label("Tạo profile và mở IDE", systemImage: "plus.rectangle.on.folder")
                                        }
                                        Divider()
                                    }
                                    Section("Liên kết profile") {
                                        ForEach(model.profiles) { profile in
                                            Button {
                                                model.link(account, to: profile)
                                            } label: {
                                                if model.accountProfileLinks[account.id] == profile.id {
                                                    Label(profile.name, systemImage: "checkmark")
                                                } else {
                                                    Text(profile.name)
                                                }
                                            }
                                        }
                                    }
                                    if model.accountProfileLinks[account.id] != nil {
                                        Button("Bỏ liên kết") { model.link(account, to: nil) }
                                    }
                                    Divider()
                                    Button("Xóa tài khoản Google", role: .destructive) {
                                        managedAccountToDelete = account
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }

                            if let profile = model.localProfile(for: account) {
                                Button {
                                    selectedID = profile.id
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "arrow.turn.down.right")
                                            .foregroundStyle(.secondary)
                                        Text(profile.name)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                        Spacer()
                                        if profile.id == model.activeProfileID {
                                            Circle().fill(.green).frame(width: 7, height: 7)
                                        }
                                    }
                                    .font(.caption)
                                    .padding(.leading, 14)
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text("Chưa liên kết profile")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                    .padding(.leading, 38)
                            }
                        }
                        .padding(.vertical, 5)
                        .contextMenu {
                            Button("Xóa tài khoản Google", role: .destructive) {
                                managedAccountToDelete = account
                            }
                        }
                    }
                    Divider()
                }
                if !unlinkedProfiles.isEmpty {
                    Text("PROFILES")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                    ForEach(unlinkedProfiles) { profile in
                        Button {
                            selectedID = profile.id
                        } label: {
                            accountRow(profile)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if model.profiles.isEmpty {
                    Text("Chưa có account")
                        .font(.caption).foregroundStyle(.secondary).padding(8)
                }
                Spacer()
                Button { startAdd() } label: {
                    Label("Thêm account", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(AGTheme.accent)
            }
            .padding(14)
            .frame(width: 300)
            .background(AGTheme.sidebar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let profile = selectedProfile {
                        profileActionsCard
                        detailHero(for: profile)
                        QuotaSectionView(model: model, selectedProfileID: selectedProfileIDForQuota)
                        detailInfoGrid(for: profile)
                        Text("Các thao tác profile nằm ở thanh phía trên. Không thể xóa profile đang dùng.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "person.2").font(.system(size: 28)).foregroundStyle(.secondary)
                            Text("Chưa có account").font(.headline)
                            Text("Bấm + để thêm bằng Google login").font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 420)
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(AGTheme.canvas)
        }
    }

    private var diagnostics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Chẩn đoán").font(.title2.bold())
                    Text("Kiểm tra kết nối với Antigravity IDE")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let report = model.doctorReport {
                    versionStatusBanner(report)
                }
                if let quota = model.quota {
                    diagnosticBanner(title: "Language server đang hoạt động", detail: "PID \(quota.server.pid) · RPC port \(quota.server.rpcPort)", color: .green, icon: "checkmark.circle.fill")
                } else {
                    diagnosticBanner(title: "Chưa lấy được quota", detail: model.quotaStatus, color: .orange, icon: "exclamationmark.triangle.fill")
                }
                sectionCard(title: "Kiểm tra hệ thống", icon: "checklist") {
                    if let report = model.doctorReport {
                        VStack(alignment: .leading, spacing: 10) {
                            diagnosticLine("Ứng dụng IDE", report.appPath ?? "Không tìm thấy", report.appPath != nil)
                            diagnosticLine("Phiên bản", "\(report.ideVersion) · \(report.versionStatus.rawValue)", report.versionStatus == .verified)
                            diagnosticLine("Strategy", report.strategy.rawValue, true)
                            diagnosticLine("Database", report.databasePath ?? "Không tìm thấy", report.databasePath != nil || report.strategy == .userDataDir)
                            diagnosticLine("Profiles", "\(report.profiles.count)", !report.profiles.isEmpty)
                            diagnosticLine(
                                "Identity keys",
                                report.strategy == .userDataDir
                                    ? "Không áp dụng với user-data-dir"
                                    : "\(report.requiredIdentityKeyCount) required",
                                true
                            )
                            diagnosticLine("Language server", model.quota == nil ? "Chưa phát hiện" : "Đã phát hiện", model.quota != nil)
                        }
                    } else {
                        Text(model.diagnosticsStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let selfTest = model.selfTestReport {
                    sectionCard(title: selfTest.passed ? "Selftest đạt" : "Selftest có lỗi", icon: selfTest.passed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill") {
                        VStack(alignment: .leading, spacing: 9) {
                            ForEach(selfTest.checks) { check in
                                HStack(spacing: 9) {
                                    Image(systemName: diagnosticIcon(check.status))
                                        .foregroundStyle(diagnosticColor(check.status))
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(check.title).font(.subheadline.weight(.medium))
                                        Text(check.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                }
                sectionCard(title: "Bảo mật", icon: "lock.shield.fill") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Quota chỉ đọc qua localhost của language server.")
                        Text("PID, port và CSRF chỉ tồn tại trong runtime; không hiển thị token.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
                HStack(spacing: 8) {
                    Button("Chạy Doctor") { model.runDoctor() }
                        .buttonStyle(.borderedProminent)
                        .tint(AGTheme.accent)
                    Button("Chạy Selftest") { model.runSelfTest() }
                        .buttonStyle(.bordered)
                    Button("Calibrate") { model.explainCalibration() }
                        .buttonStyle(.bordered)
                    Button("Làm mới quota") { model.refreshQuota() }
                        .buttonStyle(.bordered)
                    Spacer()
                    Text(model.diagnosticsStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
        }
    }

    private func versionGateBanner(_ report: DoctorReport) -> some View {
        let unsupported = report.versionStatus == .unsupported
        let color: Color = unsupported ? .red : .orange
        return HStack(spacing: 10) {
            Image(systemName: unsupported ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(color)
            Text(unsupported
                 ? "Antigravity IDE \(report.ideVersion) không được hỗ trợ. Chuyển profile đã bị khóa."
                 : "Antigravity IDE \(report.ideVersion) chưa được kiểm chứng. Chuyển profile đã bị khóa.")
                .font(.caption.weight(.medium))
            Spacer()
            Button("Mở Chẩn đoán") { selectedTab = 2 }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(10)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.25), lineWidth: 1) }
    }

    private func versionStatusBanner(_ report: DoctorReport) -> some View {
        let color: Color = report.versionStatus == .verified ? .green : (report.versionStatus == .unsupported ? .red : .orange)
        let title = report.versionStatus == .verified ? "IDE đã được kiểm chứng" : (report.versionStatus == .unsupported ? "IDE không được hỗ trợ" : "IDE chưa được kiểm chứng")
        return diagnosticBanner(
            title: title,
            detail: "Version \(report.ideVersion) · adapter \(report.adapterId)",
            color: color,
            icon: report.versionStatus == .verified ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
        )
    }

    private func diagnosticIcon(_ status: DiagnosticCheckStatus) -> String {
        switch status {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func diagnosticColor(_ status: DiagnosticCheckStatus) -> Color {
        switch status {
        case .passed: return .green
        case .warning: return .orange
        case .failed: return .red
        }
    }

    private func diagnosticBanner(title: String, detail: String, color: Color, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(AGTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.30), lineWidth: 1) }
    }

    private func detailHero(for profile: AccountProfile) -> some View {
        HStack(spacing: 14) {
            AccountAvatarView(
                name: profile.name,
                avatarURL: model.managedAccount(for: profile)?.avatarURL,
                size: 52
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.name)
                    .font(.title2.bold())
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(profile.name.contains("@") ? profile.name : "Profile cục bộ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            if model.activeProfileID == profile.id {
                Text("Đang dùng")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12), in: Capsule())
            }
        }
    }

    private func detailInfoGrid(for profile: AccountProfile) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            detailTile(title: "Phiên đăng nhập", value: "Đã lưu an toàn", detail: "Profile riêng")
            detailTile(title: "Proxy", value: "Chưa cấu hình", detail: "Kết nối trực tiếp")
            detailTile(
                title: "Lần dùng cuối",
                value: model.activeProfileID == profile.id ? "Đang hoạt động" : lastUsedText(for: profile.id),
                detail: model.profileLastUsedAt[profile.id].map(formattedSnapshotDate) ?? "Profile cục bộ"
            )
            detailTile(title: "Dữ liệu profile", value: "Tách biệt", detail: "Không sửa database dùng chung")
        }
    }

    private func lastUsedText(for profileID: String) -> String {
        guard let date = model.profileLastUsedAt[profileID] else { return "Chưa ghi nhận" }
        return relativeSnapshotAge(date)
    }

    private func detailTile(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AGTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AGTheme.border, lineWidth: 1)
        }
    }

    private func statusCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                Text(value).font(.subheadline.weight(.semibold)).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AGTheme.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).stroke(AGTheme.border, lineWidth: 1) }
    }

    private var profileActionsCard: some View {
        HStack(spacing: 12) {
            Label(selectedProfile?.name ?? "Profile", systemImage: "person.crop.rectangle.stack.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AGTheme.accent)
                .lineLimit(1)
                .truncationMode(.middle)

            if model.isSwitching {
                ProgressView()
                    .controlSize(.small)
                Text(model.switchStage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: 190, alignment: .leading)
            }

            Spacer()

            Button {
                if let profile = selectedProfile { profileToSwitch = profile }
            } label: {
                Label("Chuyển profile", systemImage: "arrow.left.arrow.right")
            }
            .buttonStyle(.borderedProminent)
            .tint(AGTheme.accent)
            .disabled(model.isSwitching || selectedProfile == nil || selectedProfile?.id == model.activeProfileID || model.doctorReport?.versionStatus != .verified)
            .help(model.doctorReport?.versionStatus == .verified ? "Chuyển sang profile đã chọn" : "Phiên bản IDE chưa được kiểm chứng")

            Button {
                guard let profile = selectedProfile else { return }
                if profile.id == model.activeProfileID || model.activeProfileID == nil {
                    model.openIDE(with: profile)
                } else {
                    profileToSwitch = profile
                }
            } label: {
                Label("Mở IDE", systemImage: "play.fill")
            }
            .buttonStyle(.bordered)
            .disabled(model.isSwitching || selectedProfile == nil || (selectedProfile?.id != model.activeProfileID && model.doctorReport?.versionStatus != .verified))

            Menu {
                Button {
                    guard let profile = selectedProfile else { return }
                    renameValue = profile.name
                    profileToRename = profile
                } label: {
                    Label("Đổi tên", systemImage: "pencil")
                }
                Button(role: .destructive) {
                    profileToDelete = selectedProfile
                } label: {
                    Label("Xóa profile", systemImage: "trash")
                }
                .disabled(selectedProfile?.id == model.activeProfileID)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.isSwitching || selectedProfile == nil)
            .help("Thao tác khác")
        }
        .padding(12)
        .background(AGTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(AGTheme.border, lineWidth: 1) }
    }

    private func sectionCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(AGTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(AGTheme.border, lineWidth: 1) }
    }

    private func relativeSnapshotAge(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func formattedSnapshotDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.dateFormat = "dd/MM HH:mm"
        return formatter.string(from: date)
    }

    private func diagnosticLine(_ label: String, _ value: String, _ ok: Bool) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value).font(.subheadline)
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(ok ? .green : .secondary)
        }
    }

    private func accountRow(_ profile: AccountProfile) -> some View {
        HStack(spacing: 8) {
            AccountAvatarView(
                name: profile.name,
                avatarURL: model.managedAccount(for: profile)?.avatarURL,
                size: 28
            )
            VStack(alignment: .leading) {
                Text(profile.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(profile.name.contains("@") ? (model.activeProfileID == profile.id ? "Đang dùng" : "Sẵn sàng") : "Profile cục bộ")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
            Spacer()
            Circle().fill(model.activeProfileID == profile.id ? .green : .gray).frame(width: 8, height: 8)
        }
        .padding(8)
        .background(selectedID == profile.id ? AGTheme.card : .clear)
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(selectedID == profile.id ? AGTheme.border : Color.clear, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func startAdd() {
        showAdd = true
    }

    private func renameProfileSheet(_ profile: AccountProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Đổi tên profile").font(.headline)
            Text(profile.userDataDir)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            TextField("Tên profile", text: $renameValue)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Hủy") { profileToRename = nil }
                Button("Lưu") {
                    let trimmed = renameValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    model.rename(profile, to: trimmed)
                    profileToRename = nil
                }
                .buttonStyle(.borderedProminent)
                .tint(AGTheme.accent)
                .disabled(renameValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private var addAccountSheet: some View {
        OAuthAddAccountSheet(
            createProfile: { try model.createProfile(for: $0) },
            openProfile: { try await model.activateProfileForSetup($0) },
            verifyLogin: { try await model.verifyIDELogin(account: $0, profile: $1) },
            onComplete: { model.reload() }
        )
    }
}

@main
struct AntigravitySwitcherUI: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

import AntigravitySwitcherCore
import SwiftUI

private enum AccountSetupStage: Equatable {
    case ready
    case openingIDE
    case waitingForLogin
    case verifying
    case completed
}

struct AccountProfileSetupPanel: View {
    let account: ManagedAccount
    let createProfile: (ManagedAccount) throws -> AccountProfile
    let openProfile: (AccountProfile) async throws -> Void
    let verifyLogin: (ManagedAccount, AccountProfile) async throws -> AntigravityAccountQuota
    let onDone: () -> Void

    @State private var stage: AccountSetupStage = .ready
    @State private var profile: AccountProfile?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 14) {
            AccountAvatarView(
                name: account.email ?? account.displayName,
                avatarURL: account.avatarURL,
                size: 48
            )
            Text(account.email ?? account.displayName)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            stageContent

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var stageContent: some View {
        switch stage {
        case .ready:
            VStack(spacing: 10) {
                Text("Bước tiếp theo tạo một profile Antigravity IDE riêng cho tài khoản này.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("IDE đang mở sẽ được khởi động lại. Hãy lưu công việc trước khi tiếp tục.")
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                Button("Đã lưu công việc · Tạo profile và mở IDE") {
                    createAndOpen()
                }
                .buttonStyle(.borderedProminent)
                .tint(AGTheme.accent)
            }

        case .openingIDE:
            VStack(spacing: 8) {
                ProgressView()
                Text("Đang tạo profile và mở Antigravity IDE…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .waitingForLogin:
            VStack(spacing: 10) {
                Label("Profile đã sẵn sàng", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Trong Antigravity IDE, hãy đăng nhập đúng tài khoản Google ở trên. Sau khi IDE tải xong, quay lại đây để xác minh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Tôi đã đăng nhập · Xác minh") {
                    verify()
                }
                .buttonStyle(.borderedProminent)
                .tint(AGTheme.accent)
                Button("Mở lại IDE") { reopen() }
                    .buttonStyle(.bordered)
            }

        case .verifying:
            VStack(spacing: 8) {
                ProgressView()
                Text("Đang đọc danh tính từ language server…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .completed:
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.green)
                Text("Account đã được thêm")
                    .font(.headline)
                Text("Email trong IDE đã khớp. Profile và snapshot quota đã được lưu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Hoàn tất") { onDone() }
                    .buttonStyle(.borderedProminent)
                    .tint(AGTheme.accent)
            }
        }
    }

    private func createAndOpen() {
        errorMessage = nil
        do {
            let target = try profile ?? createProfile(account)
            profile = target
            stage = .openingIDE
            Task {
                do {
                    try await openProfile(target)
                    stage = .waitingForLogin
                } catch {
                    errorMessage = error.localizedDescription
                    stage = .ready
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            stage = .ready
        }
    }

    private func reopen() {
        guard let profile else { return }
        errorMessage = nil
        stage = .openingIDE
        Task {
            do {
                try await openProfile(profile)
                stage = .waitingForLogin
            } catch {
                errorMessage = error.localizedDescription
                stage = .waitingForLogin
            }
        }
    }

    private func verify() {
        guard let profile else { return }
        errorMessage = nil
        stage = .verifying
        Task {
            do {
                _ = try await verifyLogin(account, profile)
                stage = .completed
            } catch {
                errorMessage = error.localizedDescription
                stage = .waitingForLogin
            }
        }
    }
}

struct AccountProfileSetupSheet: View {
    let account: ManagedAccount
    let createProfile: (ManagedAccount) throws -> AccountProfile
    let openProfile: (AccountProfile) async throws -> Void
    let verifyLogin: (ManagedAccount, AccountProfile) async throws -> AntigravityAccountQuota
    let onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Text("Thiết lập profile Antigravity")
                .font(.headline)
            AccountProfileSetupPanel(
                account: account,
                createProfile: createProfile,
                openProfile: openProfile,
                verifyLogin: verifyLogin
            ) {
                onComplete()
                dismiss()
            }
            Button("Đóng") { dismiss() }
                .buttonStyle(.borderless)
        }
        .padding(22)
        .frame(width: 430)
    }
}

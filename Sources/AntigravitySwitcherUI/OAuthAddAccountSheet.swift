import AntigravitySwitcherCore
import Foundation
import SwiftUI

struct OAuthAddAccountSheet: View {
    @StateObject private var model = OAuthAddAccountModel()
    @State private var displayName = ""
    @State private var showLocalOAuthConfiguration = false
    @State private var localClientID = ""
    @State private var localClientSecret = ""
    @State private var localConfigurationStatus = ""
    @Environment(\.dismiss) private var dismiss
    let createProfile: (ManagedAccount) throws -> AccountProfile
    let openProfile: (AccountProfile) async throws -> Void
    let verifyLogin: (ManagedAccount, AccountProfile) async throws -> AntigravityAccountQuota
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Text("Thêm tài khoản Antigravity").font(.headline)
            Text("Đăng nhập tài khoản Google trong trình duyệt mặc định.")
                .font(.caption).foregroundStyle(.secondary)
            if case .completed = model.state, let account = model.account {
                AccountProfileSetupPanel(
                    account: account,
                    createProfile: createProfile,
                    openProfile: openProfile,
                    verifyLogin: verifyLogin
                ) {
                    onComplete()
                    dismiss()
                }
            } else {
                DisclosureGroup("Cấu hình OAuth local", isExpanded: $showLocalOAuthConfiguration) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Dành cho bản đóng gói chạy riêng trên máy này. Client secret chỉ được lưu trong macOS Keychain.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        TextField("Google OAuth Client ID", text: $localClientID)
                            .textFieldStyle(.roundedBorder)
                        SecureField("Google OAuth Client Secret", text: $localClientSecret)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Lưu vào Keychain") { saveLocalOAuthConfiguration() }
                                .buttonStyle(.bordered)
                                .disabled(
                                    localClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    || localClientSecret.isEmpty
                                )
                            if !localConfigurationStatus.isEmpty {
                                Text(localConfigurationStatus)
                                    .font(.caption2)
                                    .foregroundStyle(localConfigurationStatus.hasPrefix("Đã") ? .green : .red)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.caption)
                TextField("Tên hiển thị", text: $displayName).textFieldStyle(.roundedBorder)
                if case .failed(let message) = model.state {
                    Text(message).foregroundStyle(.red).font(.caption)
                }
                if model.state == .idle || (model.state != .waitingForCallback && model.state != .exchangingCode && model.state != .identifyingAccount && model.state != .savingAccount) {
                    Button("Tiếp tục với Google") {
                        model.start(displayName: displayName.isEmpty ? "Tài khoản Google" : displayName)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    ProgressView("Hoàn tất đăng nhập trong trình duyệt…")
                    Button("Hủy") { model.cancel() }
                }
                Button("Đóng") { model.cancel() }
            }
        }
        .padding(22)
        .frame(width: 430)
        .onAppear { loadLocalOAuthConfigurationStatus() }
    }

    private func loadLocalOAuthConfigurationStatus() {
        if let local = OAuthLocalConfigurationStore().load() {
            localClientID = local.clientID
            localConfigurationStatus = local.clientSecret == nil ? "Thiếu client secret" : "Đã cấu hình"
            return
        }
        localClientID = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"]
            ?? (Bundle.main.infoDictionary?[GoogleOAuthConfiguration.infoPlistClientIDKey] as? String)
            ?? ""
    }

    private func saveLocalOAuthConfiguration() {
        do {
            try OAuthLocalConfigurationStore().save(
                clientID: localClientID,
                clientSecret: localClientSecret
            )
            localClientSecret = ""
            localConfigurationStatus = "Đã lưu an toàn"
        } catch {
            localConfigurationStatus = error.localizedDescription
        }
    }
}

@MainActor
final class OAuthAddAccountModel: ObservableObject {
    @Published var state: OAuthUIState = .idle
    @Published var account: ManagedAccount?
    private var manager: OAuthManager?

    func start(displayName: String) {
        Task {
            do {
                let configuration = try GoogleOAuthConfiguration.fromApplication()
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
                let directory = appSupport.appendingPathComponent("AntigravitySwitcher")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let store = try SQLiteAccountStore(url: directory.appendingPathComponent("accounts.sqlite"))
                let manager = OAuthManager(
                    provider: GoogleOAuthProvider(configuration: configuration),
                    keychain: MacKeychainStore(),
                    accountStore: store
                )
                self.manager = manager
                account = try await manager.startGoogleLogin(displayName: displayName)
                state = .completed
            } catch {
                OAuthDiagnostics.error("UI OAuth flow failed: \(error.localizedDescription)")
                state = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        manager?.cancel()
        state = .idle
    }
}

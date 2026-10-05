import AntigravitySwitcherCore
import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var model: ProfileViewModel
    let onSwitch: (AccountProfile) -> Void
    let onOpenManager: () -> Void
    let onQuit: () -> Void

    private var activeProfile: AccountProfile? {
        model.profiles.first { $0.id == model.activeProfileID }
    }

    private var activeSnapshot: AntigravityQuotaSnapshot? {
        model.quotaSnapshot(for: model.activeProfileID)
    }

    var body: some View {
        VStack(spacing: 0) {
            activeCard
                .padding(14)

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("CHUYỂN NHANH")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)

                if model.profiles.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 28))
                            .foregroundStyle(.secondary)
                        Text("Chưa có profile").font(.headline)
                        Text("Mở trình quản lý để thêm tài khoản đầu tiên.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 180)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(model.profiles.enumerated()), id: \.element.id) { index, profile in
                                profileRow(profile)
                                    .keyboardShortcut(
                                        KeyEquivalent(Character(String(index + 1))),
                                        modifiers: .command
                                    )
                                if index < model.profiles.count - 1 {
                                    Divider().padding(.leading, 49)
                                }
                            }
                        }
                        .background(AGTheme.card, in: RoundedRectangle(cornerRadius: 10))
                        .overlay { RoundedRectangle(cornerRadius: 10).stroke(AGTheme.border, lineWidth: 1) }
                    }
                }
            }
            .padding(14)
            .frame(maxHeight: .infinity)

            Divider()

            HStack(spacing: 8) {
                Button {
                    model.refreshQuota()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Làm mới quota")

                Text(model.status)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button("Mở đầy đủ") { onOpenManager() }
                    .buttonStyle(.borderedProminent)
                    .tint(AGTheme.accent)

                Menu {
                    Button("Thoát AG Switcher", role: .destructive) { onQuit() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(12)
        }
        .frame(width: 360, height: 500)
        .background(AGTheme.canvas)
        .preferredColorScheme(.light)
        .onAppear {
            model.reload()
            model.refreshQuota()
        }
    }

    // MARK: – Active card with ring gauges

    private var activeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                AccountAvatarView(
                    name: activeProfile?.name ?? "AG",
                    avatarURL: activeProfile.flatMap { model.managedAccount(for: $0)?.avatarURL },
                    size: 42
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeProfile?.name ?? "Chưa chọn profile")
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(activeProfile == nil ? "Mở trình quản lý để bắt đầu" : "Đang sử dụng")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.isSwitching {
                    ProgressView().controlSize(.small)
                } else if activeProfile != nil {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }

            // Compact ring gauges
            HStack(spacing: 10) {
                compactCreditGauge(
                    title: "Prompt",
                    available: activeSnapshot?.availablePromptCredits,
                    total: activeSnapshot?.monthlyPromptCredits,
                    color: Color(red: 0.42, green: 0.33, blue: 0.87)
                )
                compactCreditGauge(
                    title: "Flow",
                    available: activeSnapshot?.availableFlowCredits,
                    total: activeSnapshot?.monthlyFlowCredits,
                    color: Color(red: 0.92, green: 0.55, blue: 0.10)
                )
            }

            // Model summary chips
            if let snapshot = activeSnapshot, !snapshot.models.isEmpty {
                modelSummaryChips(snapshot)
            }

            if model.isSwitching {
                Text(model.switchStage)
                    .font(.caption)
                    .foregroundStyle(AGTheme.accent)
            } else if let capturedAt = activeSnapshot?.capturedAt {
                Text("Quota cập nhật \(relativeAge(capturedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(AGTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(AGTheme.border, lineWidth: 1) }
    }

    // MARK: – Compact credit gauge

    private func compactCreditGauge(title: String, available: Double?, total: Double?, color: Color) -> some View {
        let fraction: Double = {
            guard let a = available, let t = total, t > 0 else { return 0 }
            return min(max(a / t, 0), 1)
        }()
        let hasData = available != nil

        return HStack(spacing: 8) {
            // Mini ring
            ZStack {
                Circle()
                    .stroke(color.opacity(0.12), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
            .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                if hasData {
                    Text(String(format: "%.0f%%", fraction * 100))
                        .font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(color)
                } else {
                    Text("—")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(color.opacity(0.12), lineWidth: 1) }
    }

    // MARK: – Model summary chips

    private func modelSummaryChips(_ snapshot: AntigravityQuotaSnapshot) -> some View {
        let geminiModels = snapshot.models.filter { $0.label.localizedCaseInsensitiveContains("gemini") }
        let claudeModels = snapshot.models.filter { $0.label.localizedCaseInsensitiveContains("claude") }
        let otherModels  = snapshot.models.filter {
            !$0.label.localizedCaseInsensitiveContains("gemini")
            && !$0.label.localizedCaseInsensitiveContains("claude")
        }

        let groups: [(name: String, color: Color, models: [AntigravityModelQuota])] = [
            ("Gemini", Color(red: 0.13, green: 0.72, blue: 0.52), geminiModels),
            ("Claude", Color(red: 0.85, green: 0.45, blue: 0.20), claudeModels),
            ("Khác", .secondary, otherModels)
        ].filter { !$0.models.isEmpty }

        return HStack(spacing: 6) {
            ForEach(groups, id: \.name) { group in
                let minPercent = group.models.compactMap(\.remainingPercent).min()
                HStack(spacing: 4) {
                    Circle()
                        .fill(group.color)
                        .frame(width: 5, height: 5)
                    Text(group.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(minPercent.map { String(format: "%.0f%%", $0) } ?? "—")
                        .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                        .foregroundStyle(quotaColor(minPercent))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(group.color.opacity(0.06), in: Capsule())
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: – Profile row

    private func profileRow(_ profile: AccountProfile) -> some View {
        let isActive = profile.id == model.activeProfileID
        return Button {
            guard !isActive else { return }
            onSwitch(profile)
        } label: {
            HStack(spacing: 10) {
                AccountAvatarView(
                    name: profile.name,
                    avatarURL: model.managedAccount(for: profile)?.avatarURL,
                    size: 30
                )
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let snapshot = model.quotaSnapshot(for: profile.id) {
                        modelQuotaBar(snapshot)
                    } else {
                        Text(isActive ? "Đang lấy quota…" : "Quota sẽ hiển thị khi chuyển sang")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isActive {
                    Text("Đang dùng")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(isActive ? Color.green.opacity(0.07) : Color.clear)
        }
        .buttonStyle(.plain)
        .disabled(model.isSwitching || isActive)
    }

    // MARK: – Inline quota bar for profile rows

    private func modelQuotaBar(_ snapshot: AntigravityQuotaSnapshot) -> some View {
        let percentages = snapshot.models.compactMap(\.remainingPercent)
        let minimum = percentages.min() ?? 0
        let fraction = min(max(minimum / 100, 0), 1)
        let color = quotaColor(minimum)

        return HStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.10))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(width: 40, height: 3)

            Text(String(format: "%.0f%%", minimum))
                .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(color)
        }
    }

    // MARK: – Helpers

    private func quotaColor(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        if percent <= 20 { return .red }
        if percent <= 50 { return .orange }
        return Color(red: 0.13, green: 0.72, blue: 0.35)
    }

    private func relativeAge(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

import AntigravitySwitcherCore
import Foundation
import SwiftUI

struct QuotaSectionView: View {
    @ObservedObject var model: ProfileViewModel
    let selectedProfileID: String?
    @State private var expandedQuotaGroups: Set<String> = []

    private struct QuotaModelGroup: Identifiable {
        let id: String
        let name: String
        let variants: [AntigravityModelQuota]
    }

    // Accent colors per provider
    private static let geminiColor  = Color(red: 0.13, green: 0.72, blue: 0.52)
    private static let claudeColor  = Color(red: 0.85, green: 0.45, blue: 0.20)
    private static let promptColor  = Color(red: 0.42, green: 0.33, blue: 0.87)
    private static let flowColor    = Color(red: 0.92, green: 0.55, blue: 0.10)
    private static let goldColor    = Color(red: 0.88, green: 0.65, blue: 0.12)

    private var selectedProfileIDForQuota: String? {
        selectedProfileID ?? model.activeProfileID
    }

    private var selectedQuotaSnapshot: AntigravityQuotaSnapshot? {
        model.quotaSnapshot(for: selectedProfileIDForQuota)
    }

    private var selectedQuotaIsLive: Bool {
        selectedProfileIDForQuota != nil && selectedProfileIDForQuota == model.liveQuotaProfileID
    }

    var body: some View {
        quotaSection
    }

    // MARK: – Main section

    private var quotaSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Quota")
                        .font(.title3.weight(.bold))
                    if let snapshot = selectedQuotaSnapshot {
                        Text(snapshot.email ?? snapshot.name ?? "Account đã lưu")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Số liệu từ language server của IDE")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let snapshot = selectedQuotaSnapshot {
                    quotaFreshnessChip(snapshot: snapshot, isLive: selectedQuotaIsLive)
                }
                Button { model.refreshQuota() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedProfileIDForQuota != model.activeProfileID)
                .help(selectedProfileIDForQuota == model.activeProfileID
                      ? "Làm mới quota account đang chạy"
                      : "Quota account này sẽ tự cập nhật khi profile được mở")
            }

            if let snapshot = selectedQuotaSnapshot {
                // Credit cards with circular rings
                HStack(spacing: 10) {
                    creditRingCard(
                        title: "Prompt",
                        available: snapshot.availablePromptCredits,
                        total: snapshot.monthlyPromptCredits,
                        icon: "text.bubble.fill",
                        color: Self.promptColor
                    )
                    creditRingCard(
                        title: "Flow",
                        available: snapshot.availableFlowCredits,
                        total: snapshot.monthlyFlowCredits,
                        icon: "sparkles",
                        color: Self.flowColor
                    )
                }

                // Model card grid
                let geminiModels = snapshot.models.filter { $0.label.localizedCaseInsensitiveContains("gemini") }
                let claudeModels = snapshot.models.filter { $0.label.localizedCaseInsensitiveContains("claude") }
                let otherModels  = snapshot.models.filter {
                    !$0.label.localizedCaseInsensitiveContains("gemini")
                    && !$0.label.localizedCaseInsensitiveContains("claude")
                }
                let allSections: [(title: String, models: [AntigravityModelQuota])] = [
                    ("Gemini", geminiModels),
                    ("Claude", claudeModels),
                    ("Các model khác", otherModels)
                ].filter { !$0.models.isEmpty }

                modelCardGrid(sections: allSections)

                // Footer
                quotaFooter(snapshot: snapshot)

            } else {
                emptyQuotaState
            }
        }
        .padding(14)
        .background(AGTheme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(AGTheme.border, lineWidth: 1)
        }
    }

    // MARK: – Freshness chip

    private func quotaFreshnessChip(snapshot: AntigravityQuotaSnapshot, isLive: Bool) -> some View {
        let stale = Date().timeIntervalSince(snapshot.capturedAt) > 15 * 60
        let color: Color = isLive ? .green : (stale ? .orange : AGTheme.accent)
        let title = isLive ? "Live · tự động cập nhật" : "Đã lưu · \(relativeSnapshotAge(snapshot.capturedAt))"
        return Label(title, systemImage: isLive ? "checkmark.circle.fill" : "clock.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(color.opacity(0.10))
                    .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 1))
            )
    }

    // MARK: – Credit ring card

    private func creditRingCard(title: String, available: Double?, total: Double?, icon: String, color: Color) -> some View {
        let hasData  = available != nil
        let fraction: Double = {
            guard let t = total, let v = available, t > 0 else { return 0 }
            return min(max(v / t, 0), 1)
        }()
        let displayAvail = displayQuotaNumber(available)
        let displayTotal = displayQuotaNumber(total)

        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color.opacity(0.14))
                            .frame(width: 24, height: 24)
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(color)
                    }
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                }
                if hasData {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayAvail)
                            .font(.system(size: 20, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.primary)
                        if displayTotal != "Chưa có số liệu" {
                            Text("/ \(displayTotal)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Chưa có số liệu")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            // Circular ring
            ZStack {
                Circle()
                    .stroke(color.opacity(0.12), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(
                        AngularGradient(
                            colors: [color.opacity(0.6), color],
                            center: .center,
                            startAngle: .degrees(0),
                            endAngle: .degrees(360 * fraction)
                        ),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: fraction)
                Text(hasData ? String(format: "%.0f%%", fraction * 100) : "—")
                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(color)
            }
            .frame(width: 48, height: 48)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.06), color.opacity(0.02)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(color.opacity(0.18), lineWidth: 1))
        )
    }

    // MARK: – Model card grid

    private func modelCardGrid(sections: [(title: String, models: [AntigravityModelQuota])]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sections, id: \.title) { section in
                let groups       = groupedQuotaModels(section.models)
                let isExpanded   = expandedQuotaGroups.contains(section.title)
                let visibleGroups = isExpanded ? groups : Array(groups.prefix(4))

                // Provider header
                HStack(spacing: 6) {
                    providerIcon(for: section.title)
                    Text(section.title.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(providerColor(for: section.title).opacity(0.7))
                    Rectangle()
                        .fill(providerColor(for: section.title).opacity(0.12))
                        .frame(height: 1)
                    if groups.count > 4 {
                        Button(isExpanded ? "Thu gọn" : "Xem thêm \(groups.count - 4)") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isExpanded { expandedQuotaGroups.remove(section.title) }
                                else          { expandedQuotaGroups.insert(section.title) }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AGTheme.accent)
                    }
                }
                .padding(.horizontal, 4)

                // Grid of cards
                let columns = [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ]
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(visibleGroups) { group in
                        modelCard(group, providerTitle: section.title)
                    }
                }
            }
        }
    }

    private func providerColor(for title: String) -> Color {
        let lower = title.lowercased()
        if lower.contains("gemini") { return Self.geminiColor }
        if lower.contains("claude") { return Self.claudeColor }
        return .secondary
    }

    @ViewBuilder
    private func providerIcon(for title: String) -> some View {
        let lower = title.lowercased()
        if lower.contains("gemini") {
            Image(systemName: "sparkle")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Self.geminiColor)
        } else if lower.contains("claude") {
            Image(systemName: "cpu")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Self.claudeColor)
        } else {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: – Model card

    private func modelCard(_ group: QuotaModelGroup, providerTitle: String) -> some View {
        let percentages = group.variants.compactMap(\.remainingPercent)
        let summary     = percentages.min()
        let hasDiff     = Set(percentages.map { Int($0.rounded()) }).count > 1
        let reset       = group.variants.compactMap(\.resetTime).first
        let pColor      = providerColor(for: providerTitle)

        return VStack(alignment: .leading, spacing: 8) {
            // Top row: name + percent
            HStack {
                Text(group.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                Text(summary.map { String(format: "%.0f%%", $0) } ?? "—")
                    .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(quotaColor(summary))
            }

            // Progress bar
            GeometryReader { geo in
                let fraction = min(max((summary ?? 0) / 100, 0), 1)
                let color = quotaColor(summary)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.10))
                    Capsule()
                        .fill(LinearGradient(
                            colors: [color.opacity(0.60), color],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: geo.size.width * fraction)
                        .animation(.easeOut(duration: 0.35), value: fraction)
                }
            }
            .frame(height: 4)

            // Bottom row: reset time + variant info
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
                Text(resetCountdown(percent: summary, rawResetTime: reset))
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                if group.variants.count > 1, hasDiff {
                    Spacer(minLength: 2)
                    HStack(spacing: 3) {
                        ForEach(group.variants) { variant in
                            Circle()
                                .fill(quotaColor(variant.remainingPercent))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .help(group.variants.map { v in
                        "\(variantName(v.label, baseName: group.name)): \(v.remainingPercent.map { String(format: "%.0f%%", $0) } ?? "—")"
                    }.joined(separator: "\n"))
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(AGTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(pColor.opacity(0.12), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
    }

    // MARK: – Footer

    private func quotaFooter(snapshot: AntigravityQuotaSnapshot) -> some View {
        HStack(spacing: 8) {
            // Plan badge
            HStack(spacing: 5) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Self.goldColor)
                Text("Plan \(snapshot.planName ?? "Chưa xác định")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Self.goldColor)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Self.goldColor.opacity(0.10))
                    .overlay(Capsule().stroke(Self.goldColor.opacity(0.28), lineWidth: 1))
            )

            Spacer()

            if selectedQuotaIsLive, let quota = model.quota {
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Live · PID \(quota.server.pid) · Port \(quota.server.rpcPort)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Snapshot · \(formattedSnapshotDate(snapshot.capturedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: – Empty state

    private var emptyQuotaState: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.secondary.opacity(0.08))
                    .frame(width: 40, height: 40)
                Image(systemName: "chart.bar.xaxis")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Không có dữ liệu quota").font(.headline)
                Text(model.quotaStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Thử lại") { model.refreshQuota() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(14)
        .background(AGTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(AGTheme.border, lineWidth: 1) }
    }

    // MARK: – Helpers

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

    private func groupedQuotaModels(_ models: [AntigravityModelQuota]) -> [QuotaModelGroup] {
        var order: [String] = []
        var buckets: [String: [AntigravityModelQuota]] = [:]
        for model in models {
            let base = baseModelName(model.label)
            if buckets[base] == nil { order.append(base) }
            buckets[base, default: []].append(model)
        }
        return order.compactMap { name in
            guard let variants = buckets[name] else { return nil }
            return QuotaModelGroup(id: name, name: name, variants: variants)
        }
    }

    private func baseModelName(_ label: String) -> String {
        let suffixes = [" (Low)", " (Medium)", " (High)"]
        for suffix in suffixes where label.hasSuffix(suffix) {
            return String(label.dropLast(suffix.count))
        }
        return label
    }

    private func variantName(_ label: String, baseName: String) -> String {
        let prefix = baseName + " ("
        if label.hasPrefix(prefix), label.hasSuffix(")") {
            return String(label.dropFirst(prefix.count).dropLast())
        }
        return label
    }

    private func quotaColor(_ percent: Double?) -> Color {
        guard let percent else { return .secondary }
        if percent <= 20 { return .red }
        if percent <= 50 { return .orange }
        return Color(red: 0.13, green: 0.72, blue: 0.35)
    }

    private func resetCountdown(percent: Double?, rawResetTime: String?) -> String {
        guard let percent else { return "—" }
        if percent >= 99.5 { return "5h" }
        guard let rawResetTime else { return "—" }
        let parser = ISO8601DateFormatter()
        guard let resetDate = parser.date(from: rawResetTime) else { return "—" }
        let remaining = min(max(resetDate.timeIntervalSinceNow, 0), 5 * 60 * 60)
        let hours   = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }
}

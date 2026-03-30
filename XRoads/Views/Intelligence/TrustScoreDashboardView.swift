import SwiftUI

// MARK: - TrustScoreDashboardView

/// Trust matrix view showing agent trust scores across domains.
/// Color-coded grid with auto-merge indicators and per-agent detail stats.
///
/// Phase 6: Intelligence layer — trust score dashboard.
struct TrustScoreDashboardView: View {
    let trustScores: [TrustScore]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Trust Matrix Header
                HStack(spacing: 6) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentPrimary)

                    Text("TRUST MATRIX")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                }

                if trustScores.isEmpty {
                    VStack(spacing: Theme.Spacing.md) {
                        Spacer()
                        Image(systemName: "shield.slash")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.textTertiary)
                        Text("No trust scores computed yet")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                } else {
                    // Grid: agents x domains
                    trustMatrixGrid

                    Divider()

                    // Legend
                    legendSection

                    Divider()

                    // Per-Agent Detail
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.rectangle.stack")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.statusInfo)

                        Text("AGENT DETAIL")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)
                    }

                    agentDetailSection
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Color.bgCanvas)
    }

    // MARK: - Trust Matrix Grid

    @ViewBuilder
    private var trustMatrixGrid: some View {
        let agents = Array(Set(trustScores.map(\.agentType))).sorted()
        let domains = Array(Set(trustScores.map(\.domain))).sorted()
        let lookup = Dictionary(
            uniqueKeysWithValues: trustScores.map { ("\($0.agentType)|\($0.domain)", $0) }
        )

        VStack(alignment: .leading, spacing: 2) {
            // Header row
            HStack(spacing: 2) {
                Text("")
                    .frame(width: 70, alignment: .leading)

                ForEach(domains, id: \.self) { domain in
                    Text(domain.uppercased())
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
            }

            // Agent rows
            ForEach(agents, id: \.self) { agent in
                HStack(spacing: 2) {
                    Text(agent.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(agentColor(agent))
                        .frame(width: 70, alignment: .leading)

                    ForEach(domains, id: \.self) { domain in
                        let key = "\(agent)|\(domain)"
                        trustCell(trust: lookup[key])
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Color.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    @ViewBuilder
    private func trustCell(trust: TrustScore?) -> some View {
        if let trust {
            let pct = Int(trust.score * 100)
            VStack(spacing: 1) {
                Text("\(pct)%")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(trustColor(trust.score))

                if trust.autoMergeEnabled && trust.score >= trust.autoMergeThreshold {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.statusSuccess)
                } else if trust.autoMergeEnabled {
                    Image(systemName: "circle.dashed")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity)
            .background(trustColor(trust.score).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs))
        } else {
            Text("-")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
    }

    // MARK: - Legend

    @ViewBuilder
    private var legendSection: some View {
        HStack(spacing: Theme.Spacing.lg) {
            legendItem(color: Color.statusSuccess, label: ">= 80%")
            legendItem(color: Color.statusWarning, label: "50-79%")
            legendItem(color: Color.statusError, label: "< 50%")

            Spacer()

            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.statusSuccess)
                Text("Auto-merge active")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 10)

            Text(label)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textSecondary)
        }
    }

    // MARK: - Agent Detail

    @ViewBuilder
    private var agentDetailSection: some View {
        let grouped = Dictionary(grouping: trustScores, by: \.agentType)

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(grouped.keys.sorted(), id: \.self) { agent in
                if let scores = grouped[agent] {
                    let totalStories = scores.reduce(0) { $0 + $1.totalStories }
                    let successStories = scores.reduce(0) { $0 + $1.successfulStories }
                    let totalPassed = scores.reduce(0) { $0 + $1.totalTestsPassed }
                    let totalFailed = scores.reduce(0) { $0 + $1.totalTestsFailed }
                    let totalTests = totalPassed + totalFailed
                    let testPassRate = totalTests > 0 ? Double(totalPassed) / Double(totalTests) : 0

                    HStack(spacing: Theme.Spacing.md) {
                        Text(agent.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(agentColor(agent))
                            .frame(width: 60, alignment: .leading)

                        statPill(
                            label: "STORIES",
                            value: "\(totalStories)",
                            color: Color.textSecondary
                        )

                        statPill(
                            label: "SUCCESS",
                            value: totalStories > 0
                                ? String(format: "%.0f%%", Double(successStories) / Double(totalStories) * 100)
                                : "N/A",
                            color: Color.statusSuccess
                        )

                        statPill(
                            label: "TESTS",
                            value: String(format: "%.0f%%", testPassRate * 100),
                            color: Color.statusInfo
                        )

                        Spacer()
                    }
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Color.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    @ViewBuilder
    private func statPill(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.bgApp)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs))
    }

    // MARK: - Helpers

    private func trustColor(_ score: Double) -> Color {
        if score >= 0.8 { return Color.statusSuccess }
        if score >= 0.5 { return Color.statusWarning }
        return Color.statusError
    }

    private func agentColor(_ agentType: String) -> Color {
        switch agentType.lowercased() {
        case "claude": return Color.accentPrimary
        case "gemini": return Color.statusInfo
        case "codex": return Color.statusWarning
        default: return Color.textSecondary
        }
    }
}

// MARK: - Preview

#if DEBUG
struct TrustScoreDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        TrustScoreDashboardView(trustScores: [])
            .frame(width: 600, height: 500)
            .background(Color.bgApp)
    }
}
#endif

import SwiftUI

// MARK: - LearningDashboardView

/// Full learning analytics view showing agent performance profiles,
/// task categorization, time estimation accuracy, and recommendations.
///
/// Phase 6: Intelligence layer — learning analytics dashboard.
struct LearningDashboardView: View {
    let profiles: [PerformanceProfile]
    let records: [LearningRecord]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Agent Performance Comparison
                sectionHeader("AGENT PERFORMANCE", icon: "chart.bar.fill", color: Color.accentPrimary)
                agentPerformanceSection

                Divider()

                // Task Categorization Breakdown
                sectionHeader("TASK CATEGORIES", icon: "tag.fill", color: Color.statusInfo)
                taskCategorySection

                Divider()

                // Time Estimation Accuracy
                sectionHeader("DURATION ACCURACY", icon: "clock.fill", color: Color.terminalYellow)
                durationAccuracySection

                Divider()

                // Recommendations
                sectionHeader("RECOMMENDATIONS", icon: "lightbulb.fill", color: Color.statusSuccess)
                recommendationsSection

                Divider()

                // Recent Retro Summaries
                sectionHeader("RECENT RECORDS", icon: "doc.text.fill", color: Color.textSecondary)
                recentRecordsSection
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Color.bgCanvas)
    }

    // MARK: - Agent Performance

    @ViewBuilder
    private var agentPerformanceSection: some View {
        let grouped = Dictionary(grouping: profiles, by: \.agentType)

        if grouped.isEmpty {
            emptyPlaceholder("No performance profiles recorded yet")
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(grouped.keys.sorted(), id: \.self) { agentType in
                    if let agentProfiles = grouped[agentType] {
                        let avgSuccess = agentProfiles.reduce(0.0) { $0 + $1.successRate } / Double(agentProfiles.count)
                        let totalExecs = agentProfiles.reduce(0) { $0 + $1.totalExecutions }

                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            HStack {
                                agentBadge(agentType)

                                Spacer()

                                Text("\(totalExecs) executions")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.textTertiary)
                            }

                            // Success rate bar
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.bgApp)
                                        .frame(height: 8)

                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(successColor(avgSuccess))
                                        .frame(
                                            width: max(0, geometry.size.width * CGFloat(avgSuccess)),
                                            height: 8
                                        )
                                }
                            }
                            .frame(height: 8)

                            HStack {
                                Text(String(format: "%.0f%% success rate", avgSuccess * 100))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(successColor(avgSuccess))

                                Spacer()

                                let avgTestPass = agentProfiles.reduce(0.0) { $0 + $1.avgTestPassRate } / Double(agentProfiles.count)
                                Text(String(format: "%.0f%% test pass", avgTestPass * 100))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.textSecondary)
                            }
                        }
                        .padding(Theme.Spacing.sm)
                        .background(Color.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                }
            }
        }
    }

    // MARK: - Task Category

    @ViewBuilder
    private var taskCategorySection: some View {
        let grouped = Dictionary(grouping: profiles, by: \.taskCategory)

        if grouped.isEmpty {
            emptyPlaceholder("No task categories recorded yet")
        } else {
            let totalExecs = profiles.reduce(0) { $0 + $1.totalExecutions }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(grouped.keys.sorted(), id: \.self) { category in
                    if let catProfiles = grouped[category] {
                        let catExecs = catProfiles.reduce(0) { $0 + $1.totalExecutions }
                        let fraction = totalExecs > 0 ? Double(catExecs) / Double(totalExecs) : 0

                        HStack(spacing: Theme.Spacing.sm) {
                            Text(category)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.textPrimary)
                                .frame(width: 120, alignment: .leading)

                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.accentPrimary.opacity(0.7))
                                    .frame(width: max(0, geometry.size.width * CGFloat(fraction)), height: 6)
                            }
                            .frame(height: 6)

                            Text(String(format: "%d (%.0f%%)", catExecs, fraction * 100))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(Color.textSecondary)
                                .frame(width: 60, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.sm)
            .background(Color.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    // MARK: - Duration Accuracy

    @ViewBuilder
    private var durationAccuracySection: some View {
        let grouped = Dictionary(grouping: profiles, by: \.agentType)

        if grouped.isEmpty {
            emptyPlaceholder("No duration data available")
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(grouped.keys.sorted(), id: \.self) { agentType in
                    if let agentProfiles = grouped[agentType] {
                        ForEach(agentProfiles, id: \.id) { profile in
                            HStack(spacing: Theme.Spacing.sm) {
                                agentBadge(agentType)

                                Text(profile.taskCategory)
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.textSecondary)
                                    .frame(width: 100, alignment: .leading)

                                Spacer()

                                let avgMinutes = Double(profile.avgDurationMs) / 60_000.0
                                Text(String(format: "avg %.1f min", avgMinutes))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Color.textPrimary)

                                Text(String(format: "$%.2f avg", Double(profile.avgCostCents) / 100.0))
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundStyle(Color.statusWarning)
                            }
                        }
                    }
                }
            }
            .padding(Theme.Spacing.sm)
            .background(Color.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    // MARK: - Recommendations

    @ViewBuilder
    private var recommendationsSection: some View {
        let recommendations = generateRecommendations()

        if recommendations.isEmpty {
            emptyPlaceholder("Not enough data for recommendations")
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(Array(recommendations.enumerated()), id: \.offset) { _, rec in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.statusSuccess)

                        Text(rec)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.textPrimary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(Theme.Spacing.sm)
            .background(Color.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    // MARK: - Recent Records

    @ViewBuilder
    private var recentRecordsSection: some View {
        let recent = Array(records.prefix(10))

        if recent.isEmpty {
            emptyPlaceholder("No learning records yet")
        } else {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(recent, id: \.id) { record in
                    HStack(spacing: Theme.Spacing.sm) {
                        Circle()
                            .fill(record.success ? Color.statusSuccess : Color.statusError)
                            .frame(width: 6, height: 6)

                        agentBadge(record.agentType)

                        Text(record.storyTitle)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)
                            .lineLimit(1)

                        Spacer()

                        let minutes = Double(record.durationMs) / 60_000.0
                        Text(String(format: "%.1fm", minutes))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .padding(Theme.Spacing.sm)
            .background(Color.bgSurface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
        }
    }

    @ViewBuilder
    private func agentBadge(_ agentType: String) -> some View {
        Text(agentType.uppercased())
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(agentColor(agentType))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(agentColor(agentType).opacity(0.1))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func emptyPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(Color.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.md)
    }

    private func agentColor(_ agentType: String) -> Color {
        switch agentType.lowercased() {
        case "claude": return Color.accentPrimary
        case "gemini": return Color.statusInfo
        case "codex": return Color.statusWarning
        default: return Color.textSecondary
        }
    }

    private func successColor(_ rate: Double) -> Color {
        if rate >= 0.8 { return Color.statusSuccess }
        if rate >= 0.5 { return Color.statusWarning }
        return Color.statusError
    }

    /// Generate recommendations by comparing agent profiles per category.
    private func generateRecommendations() -> [String] {
        var recs: [String] = []
        let byCategory = Dictionary(grouping: profiles, by: \.taskCategory)

        for (category, catProfiles) in byCategory {
            guard catProfiles.count > 1 else { continue }

            // Find best agent by success rate
            if let best = catProfiles.max(by: { $0.successRate < $1.successRate }),
               let worst = catProfiles.min(by: { $0.successRate < $1.successRate }),
               best.successRate - worst.successRate > 0.1 {
                let pctDiff = Int((best.successRate - worst.successRate) * 100)
                recs.append("Use \(best.agentType) for \(category) (\(pctDiff)% higher success rate)")
            }

            // Find fastest agent
            if let fastest = catProfiles.min(by: { $0.avgDurationMs < $1.avgDurationMs }),
               let slowest = catProfiles.max(by: { $0.avgDurationMs < $1.avgDurationMs }),
               slowest.avgDurationMs > 0 {
                let pctFaster = Int((1.0 - Double(fastest.avgDurationMs) / Double(slowest.avgDurationMs)) * 100)
                if pctFaster > 10 {
                    recs.append("Use \(fastest.agentType) for \(category) (\(pctFaster)% faster)")
                }
            }
        }

        // Conflict warnings
        let highConflict = profiles.filter { $0.conflictRate > 0.3 }
        for profile in highConflict {
            recs.append("Avoid parallel \(profile.agentType) on \(profile.taskCategory) (conflict rate: \(Int(profile.conflictRate * 100))%)")
        }

        return Array(Set(recs)).sorted()
    }
}

// MARK: - Preview

#if DEBUG
struct LearningDashboardView_Previews: PreviewProvider {
    static var previews: some View {
        LearningDashboardView(profiles: [], records: [])
            .frame(width: 600, height: 500)
            .background(Color.bgApp)
    }
}
#endif

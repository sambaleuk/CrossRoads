import SwiftUI

// MARK: - ConflictPredictionView

/// Pre-dispatch conflict prediction view showing risky story pairs,
/// overlapping file patterns, and recommended resequencing.
///
/// Phase 6: Intelligence layer — conflict prediction dashboard.
struct ConflictPredictionView: View {
    let result: ConflictPreventionResult?
    var onApplyResequencing: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.statusWarning)

                    Text("CONFLICT PREDICTION")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)

                    Spacer()

                    if let result, !result.riskyPairs.isEmpty {
                        Text("\(result.riskyPairs.count) RISKY")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.statusError)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.statusError.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }

                if let result {
                    if result.riskyPairs.isEmpty && result.safePairs.isEmpty {
                        emptyState("No dispatch plan analyzed yet")
                    } else {
                        // Risky Pairs
                        if !result.riskyPairs.isEmpty {
                            sectionHeader("RISKY PAIRS", icon: "bolt.trianglebadge.exclamationmark.fill", color: Color.statusError)
                            riskyPairsSection(result.riskyPairs)
                        }

                        // Safe Pairs
                        if !result.safePairs.isEmpty {
                            Divider()
                            sectionHeader("SAFE PAIRS", icon: "checkmark.shield.fill", color: Color.statusSuccess)
                            safePairsSection(result.safePairs)
                        }

                        // Recommended Resequencing
                        if !result.recommendedResequencing.isEmpty {
                            Divider()
                            sectionHeader("RECOMMENDED SEQUENCE", icon: "arrow.triangle.swap", color: Color.accentPrimary)
                            resequencingSection(result.recommendedResequencing)

                            if let onApplyResequencing, !result.riskyPairs.isEmpty {
                                HStack {
                                    Spacer()
                                    Button {
                                        onApplyResequencing()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "arrow.triangle.swap")
                                                .font(.system(size: 10))
                                            Text("Apply Resequencing")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                                    .tint(Color.accentPrimary)
                                }
                            }
                        }
                    }
                } else {
                    emptyState("Run conflict analysis from the dispatch view")
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .background(Color.bgCanvas)
    }

    // MARK: - Risky Pairs

    @ViewBuilder
    private func riskyPairsSection(_ pairs: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                HStack(spacing: Theme.Spacing.sm) {
                    riskBadge("HIGH")

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(truncateStoryId(pair.0))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.textPrimary)

                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 7))
                                .foregroundStyle(Color.statusError)

                            Text(truncateStoryId(pair.1))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.textPrimary)
                        }

                        Text("Overlapping file patterns detected")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(Color.textTertiary)
                    }

                    Spacer()
                }
                .padding(Theme.Spacing.sm)
                .background(Color.statusError.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Color.statusError.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Safe Pairs

    @ViewBuilder
    private func safePairsSection(_ pairs: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ForEach(Array(pairs.prefix(10).enumerated()), id: \.offset) { _, pair in
                HStack(spacing: Theme.Spacing.sm) {
                    riskBadge("LOW")

                    Text(truncateStoryId(pair.0))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)

                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.statusSuccess)

                    Text(truncateStoryId(pair.1))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)

                    Spacer()
                }
            }

            if pairs.count > 10 {
                Text("+ \(pairs.count - 10) more safe pairs")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Color.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    // MARK: - Resequencing

    @ViewBuilder
    private func resequencingSection(_ layers: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(Array(layers.enumerated()), id: \.offset) { index, layer in
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    // Layer number
                    VStack {
                        Text("L\(index + 1)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.accentPrimary)
                            .frame(width: 24, height: 24)
                            .background(Color.accentPrimary.opacity(0.1))
                            .clipShape(Circle())

                        if index < layers.count - 1 {
                            Rectangle()
                                .fill(Color.borderMuted.opacity(0.4))
                                .frame(width: 1, height: 12)
                        }
                    }

                    // Stories in this layer
                    FlowLayout(spacing: 4) {
                        ForEach(layer, id: \.self) { story in
                            Text(truncateStoryId(story))
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.textPrimary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.bgSurface)
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xs))
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.Radius.xs)
                                        .stroke(Color.borderMuted.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Color.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    // MARK: - Helpers

    @ViewBuilder
    private func sectionHeader(_ title: String, icon: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)

            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
        }
    }

    @ViewBuilder
    private func riskBadge(_ level: String) -> some View {
        let color: Color = {
            switch level {
            case "HIGH": return Color.statusError
            case "MEDIUM": return Color.statusWarning
            default: return Color.statusSuccess
            }
        }()

        Text(level)
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func emptyState(_ message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Spacer()
            Image(systemName: "shield.checkered")
                .font(.system(size: 28))
                .foregroundStyle(Color.textTertiary)
            Text(message)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.textTertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }

    private func truncateStoryId(_ storyId: String) -> String {
        if storyId.count > 24 {
            return String(storyId.prefix(24)) + "..."
        }
        return storyId
    }
}

// MARK: - Preview

#if DEBUG
struct ConflictPredictionView_Previews: PreviewProvider {
    static var previews: some View {
        ConflictPredictionView(result: nil)
            .frame(width: 600, height: 500)
            .background(Color.bgApp)
    }
}
#endif

import SwiftUI

// MARK: - ModelRoutingView

/// Cockpit sidebar panel showing current model routing decision.
/// Displays recommended model, budget pressure, capability score, and cost estimate.
struct ModelRoutingView: View {

    let recommendation: BudgetService.ModelRecommendation?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.swap")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.accentPrimary)

                Text("MODEL ROUTING")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                if let rec = recommendation {
                    pressureBadge(rec.budgetPressure)
                }
            }

            if let rec = recommendation {
                // Current model
                HStack(spacing: Theme.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rec.recommendedModel)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)

                        Text(rec.provider)
                            .font(.system(size: 10))
                            .foregroundStyle(Color.textTertiary)
                    }

                    Spacer()

                    // Estimated cost
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("~\(rec.estimatedCostCents)¢")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(costColor(rec.estimatedCostCents))

                        Text("per story")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                // Capability score bar
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Capability")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Color.textTertiary)

                        Spacer()

                        Text("\(Int(rec.capabilityScore * 100))%")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.textSecondary)
                    }

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.bgElevated)
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(capabilityColor(rec.capabilityScore))
                                .frame(width: geo.size.width * rec.capabilityScore, height: 4)
                        }
                    }
                    .frame(height: 4)
                }

                // Reason
                Text(rec.reason)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(2)

                Divider()
                    .background(Color.borderMuted)

                // Model tier reference
                modelTierReference
            } else {
                // No recommendation yet
                VStack(spacing: Theme.Spacing.sm) {
                    Text("No active routing")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiary)

                    Text("Model routing activates during orchestration")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
            }
        }
        .padding(Theme.Spacing.sm)
    }

    // MARK: - Pressure Badge

    private func pressureBadge(_ pressure: String) -> some View {
        Text(pressure.uppercased())
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(pressureColor(pressure))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(pressureColor(pressure).opacity(0.15))
            .clipShape(Capsule())
    }

    // MARK: - Model Tier Reference

    private var modelTierReference: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Model Tiers")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textTertiary)

            ForEach(ModelRoutingView.modelTiers, id: \.name) { tier in
                HStack(spacing: 4) {
                    Text(tier.name)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .frame(width: 58, alignment: .leading)

                    Text(tier.provider)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)
                        .frame(width: 55, alignment: .leading)

                    Spacer()

                    Text("$\(String(format: "%.1f", tier.inputCost))/\(String(format: "%.1f", tier.outputCost))")
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)

                    // Capability mini bar
                    RoundedRectangle(cornerRadius: 1)
                        .fill(capabilityColor(tier.capability))
                        .frame(width: CGFloat(tier.capability * 30), height: 3)
                }
            }
        }
    }

    // MARK: - Colors

    private func pressureColor(_ pressure: String) -> Color {
        switch pressure {
        case "critical": return .statusError
        case "heavy": return .statusWarning
        case "light": return Color(hex: "#F7DC6F")
        default: return .statusSuccess
        }
    }

    private func costColor(_ cents: Int) -> Color {
        if cents > 50 { return .statusWarning }
        if cents > 20 { return .textSecondary }
        return .statusSuccess
    }

    private func capabilityColor(_ score: Double) -> Color {
        if score >= 0.9 { return .accentPrimary }
        if score >= 0.7 { return .statusSuccess }
        if score >= 0.5 { return .statusWarning }
        return .statusError
    }

    // MARK: - Static Data

    private struct ModelTierInfo: Hashable {
        let name: String
        let provider: String
        let inputCost: Double
        let outputCost: Double
        let capability: Double
    }

    private static let modelTiers: [ModelTierInfo] = [
        ModelTierInfo(name: "opus", provider: "anthropic", inputCost: 15.0, outputCost: 75.0, capability: 1.0),
        ModelTierInfo(name: "sonnet", provider: "anthropic", inputCost: 3.0, outputCost: 15.0, capability: 0.8),
        ModelTierInfo(name: "haiku", provider: "anthropic", inputCost: 0.25, outputCost: 1.25, capability: 0.5),
        ModelTierInfo(name: "gpt-4o", provider: "openai", inputCost: 2.5, outputCost: 10.0, capability: 0.85),
        ModelTierInfo(name: "o3", provider: "openai", inputCost: 10.0, outputCost: 40.0, capability: 0.95),
        ModelTierInfo(name: "gemini-2", provider: "google", inputCost: 0.50, outputCost: 1.50, capability: 0.7),
    ]
}

// MARK: - Preview

#if DEBUG
struct ModelRoutingView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ModelRoutingView(recommendation: BudgetService.ModelRecommendation(
                recommendedModel: "sonnet",
                provider: "anthropic",
                reason: "Budget healthy — sonnet selected for best capability",
                estimatedCostCents: 12,
                capabilityScore: 0.8,
                budgetPressure: "none"
            ))
            .frame(width: 260)

            ModelRoutingView(recommendation: nil)
                .frame(width: 260)
        }
        .background(Color.bgApp)
    }
}
#endif

import SwiftUI

// MARK: - BudgetPanelView

/// Compact budget health display for the cockpit sidebar.
/// Shows progress bar (green->yellow->red), spend vs budget, and burn rate.
///
/// Phase 5: Budget tracking integration into Cockpit sidebar.
struct BudgetPanelView: View {
    let budgetStatus: BudgetStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "dollarsign.gauge.chart.lefthalf.righthalf")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.statusWarning)

                Text("BUDGET")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                if let status = budgetStatus {
                    statusBadge(status)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Color.bgSurface)

            Divider()

            // Content
            if let status = budgetStatus {
                budgetContent(status)
                    .padding(Theme.Spacing.sm)
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    Spacer()
                    Text("No budget data")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
            }
        }
        .background(Color.bgCanvas)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Color.borderMuted.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Budget Content

    @ViewBuilder
    private func budgetContent(_ status: BudgetStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.bgApp)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(progressColor(status))
                        .frame(
                            width: min(geometry.size.width, geometry.size.width * CGFloat(status.percentUsed / 100.0)),
                            height: 6
                        )
                }
            }
            .frame(height: 6)

            // Spend text
            HStack {
                let spentDollars = Double(status.projectedTotal - status.remainingCents) / 100.0
                let budgetDollars = Double(status.projectedTotal - status.remainingCents + status.remainingCents) / 100.0
                Text(String(format: "$%.2f / $%.2f (%.\(0)f%%)", spentDollars, budgetDollars, status.percentUsed))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(progressColor(status))

                Spacer()
            }

            // Over-budget warning
            if status.status == "exceeded" {
                HStack(spacing: 3) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8))
                    Text("OVER BUDGET")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Color.statusError)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusBadge(_ status: BudgetStatus) -> some View {
        Text(status.status.uppercased())
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(progressColor(status))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(progressColor(status).opacity(0.1))
            .clipShape(Capsule())
    }

    private func progressColor(_ status: BudgetStatus) -> Color {
        switch status.status {
        case "exceeded":
            return Color.statusError
        case "warning":
            return Color.statusWarning
        default:
            return Color.statusSuccess
        }
    }
}

// MARK: - Preview

#if DEBUG
struct BudgetPanelView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Theme.Spacing.md) {
            BudgetPanelView(budgetStatus: BudgetStatus(
                status: "ok",
                percentUsed: 45.0,
                remainingCents: 550,
                projectedTotal: 1000
            ))

            BudgetPanelView(budgetStatus: BudgetStatus(
                status: "exceeded",
                percentUsed: 120.0,
                remainingCents: -200,
                projectedTotal: 1200
            ))

            BudgetPanelView(budgetStatus: nil)
        }
        .frame(width: 280)
        .padding()
        .background(Color.bgApp)
    }
}
#endif

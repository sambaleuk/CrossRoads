import SwiftUI

// MARK: - CockpitBrainPanelView

/// Cockpit Brain panel for the sidebar. Shows COP summary, META agent status,
/// deliverables browser, specialist status, and adaptation log placeholder.
///
/// Follows the same styling pattern as BudgetPanelView and HeartbeatPanelView.
struct CockpitBrainPanelView: View {
    let cop: CockpitOrchestrationPlan?
    let adaptationActions: [AdaptationAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.terminalCyan)

                Text("BRAIN")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                if cop != nil {
                    Text("ACTIVE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.statusSuccess)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.statusSuccess.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Color.bgSurface)

            Divider()

            // Content
            if let cop = cop {
                brainContent(cop)
                    .padding(Theme.Spacing.sm)
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    Spacer()
                    Text("No orchestration plan")
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

    // MARK: - Brain Content

    @ViewBuilder
    private func brainContent(_ cop: CockpitOrchestrationPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // COP Summary
            copSummarySection(cop)

            Divider()

            // META Agent Status
            metaAgentSection(cop)

            Divider()

            // Deliverables Browser
            deliverablesSection(cop)

            // Specialist Status
            if !cop.specialistTriggers.isEmpty {
                Divider()
                specialistSection(cop)
            }

            // Adaptation Actions
            if !adaptationActions.isEmpty {
                Divider()
                adaptationSection
            }
        }
    }

    // MARK: - COP Summary

    @ViewBuilder
    private func copSummarySection(_ cop: CockpitOrchestrationPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("PROJECT")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textTertiary)

            Text(cop.projectName)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            HStack(spacing: 4) {
                badgeView(text: cop.projectType, color: Color.statusInfo)
                badgeView(text: cop.domain, color: Color.terminalMagenta)
                badgeView(text: cop.marketContext, color: Color.terminalYellow)
            }
        }
    }

    // MARK: - META Agent Status

    @ViewBuilder
    private func metaAgentSection(_ cop: CockpitOrchestrationPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.statusSuccess)
                    .frame(width: 6, height: 6)
                    .shadow(color: Color.statusSuccess.opacity(0.6), radius: 2)

                Text("META AGENT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)

                Spacer()

                Text(cop.metaAgentConfig.autonomyLevel.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(cop.metaAgentConfig.autonomyLevel == "full" ? Color.statusSuccess : Color.statusWarning)
            }

            // Capabilities list
            FlowLayout(spacing: 3) {
                ForEach(cop.metaAgentConfig.capabilities, id: \.self) { capability in
                    Text(capability)
                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textSecondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.bgSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
        }
    }

    // MARK: - Deliverables Browser

    @ViewBuilder
    private func deliverablesSection(_ cop: CockpitOrchestrationPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("DELIVERABLES")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textTertiary)

            ForEach(cop.transverseProductions, id: \.category) { category in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(category.category.uppercased())
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.textPrimary)

                        priorityBadge(category.priority)

                        Spacer()

                        Text("\(category.deliverables.count)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                    }

                    ForEach(category.deliverables, id: \.self) { deliverable in
                        HStack(spacing: 3) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 7))
                                .foregroundStyle(Color.textTertiary)
                            Text(deliverable)
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundStyle(Color.textSecondary)
                                .lineLimit(1)
                        }
                        .padding(.leading, 6)
                    }
                }
            }
        }
    }

    // MARK: - Specialist Status

    @ViewBuilder
    private func specialistSection(_ cop: CockpitOrchestrationPlan) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("SPECIALISTS")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textTertiary)

            ForEach(cop.specialistTriggers, id: \.specialist) { trigger in
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.terminalYellow)
                        .frame(width: 5, height: 5)

                    Text(trigger.specialist)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text("READY")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.terminalYellow)
                }
            }
        }
    }

    // MARK: - Adaptation Log

    @ViewBuilder
    private var adaptationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text("ADAPTATIONS")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.textTertiary)

            ForEach(Array(adaptationActions.prefix(5).enumerated()), id: \.offset) { _, action in
                HStack(spacing: 4) {
                    Image(systemName: adaptationIcon(action.action))
                        .font(.system(size: 7))
                        .foregroundStyle(adaptationColor(action.action))

                    Text(action.action.replacingOccurrences(of: "_", with: " "))
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color.textPrimary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func badgeView(text: String, color: Color) -> some View {
        Text(text.uppercased())
            .font(.system(size: 7, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func priorityBadge(_ priority: String) -> some View {
        let color: Color = switch priority {
        case "high": Color.statusError
        case "medium": Color.statusWarning
        default: Color.textTertiary
        }

        Text(priority.uppercased())
            .font(.system(size: 6, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 3)
            .padding(.vertical, 1)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    // MARK: - Helpers

    private func adaptationIcon(_ action: String) -> String {
        switch action {
        case "focus_debugging": return "ladybug.fill"
        case "switch_model": return "arrow.triangle.2.circlepath"
        case "activate_transverse": return "play.fill"
        case "pause_and_resolve": return "pause.fill"
        case "restart_stalled": return "arrow.clockwise"
        default: return "circle.fill"
        }
    }

    private func adaptationColor(_ action: String) -> Color {
        switch action {
        case "focus_debugging": return Color.statusError
        case "switch_model": return Color.statusWarning
        case "activate_transverse": return Color.statusSuccess
        case "pause_and_resolve": return Color.terminalYellow
        case "restart_stalled": return Color.statusInfo
        default: return Color.textTertiary
        }
    }
}

// MARK: - Preview

#if DEBUG
struct CockpitBrainPanelView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: Theme.Spacing.md) {
            CockpitBrainPanelView(
                cop: CockpitOrchestrationPlan(
                    projectName: "my-saas",
                    projectType: "saas",
                    domain: "fintech",
                    marketContext: "competitive",
                    transverseProductions: [
                        TransverseCategory(
                            category: "documentation",
                            deliverables: ["README", "deploy-guide", "changelog"],
                            priority: "high"
                        ),
                        TransverseCategory(
                            category: "marketing",
                            deliverables: ["landing-page-copy", "value-proposition"],
                            priority: "high"
                        ),
                    ],
                    specialistTriggers: [
                        SpecialistTrigger(
                            condition: "domain contains payment",
                            specialist: "fintech-compliance",
                            reason: "Payment processing needs review"
                        ),
                    ],
                    metaAgentConfig: MetaAgentConfig(
                        capabilities: ["qa", "doc_gen", "git_master", "security_scan"],
                        monitoringIntervalMs: 30_000,
                        autonomyLevel: "full"
                    ),
                    deliverablesPath: "/tmp/d/",
                    createdAt: "2026-03-29T00:00:00Z"
                ),
                adaptationActions: [
                    AdaptationAction(action: "activate_transverse", targetSlot: nil, reason: "Coding 75% done"),
                ]
            )

            CockpitBrainPanelView(cop: nil, adaptationActions: [])
        }
        .frame(width: 280)
        .padding()
        .background(Color.bgApp)
    }
}
#endif

import SwiftUI

// MARK: - OrgChartPanelView

/// Displays the organizational role hierarchy for the active cockpit session.
/// Renders a mini tree with CEO at top, children indented below.
/// Each node shows role name, agent type badge, and status dot.
///
/// Phase 5: Org Chart integration into Cockpit sidebar.
struct OrgChartPanelView: View {
    let orgRoles: [OrgRole]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.terminalCyan)

                Text("ORG CHART")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                Text("\(orgRoles.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.bgApp)
                    .clipShape(Capsule())
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Color.bgSurface)

            Divider()

            // Tree content (flat list with computed depths)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(flatNodes, id: \.role.id) { node in
                        nodeRow(role: node.role, depth: node.depth)
                    }
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Color.bgCanvas)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Color.borderMuted.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Flat Tree

    private struct FlatNode {
        let role: OrgRole
        let depth: Int
    }

    /// Pre-order traversal producing a flat list with depth for indentation.
    private var flatNodes: [FlatNode] {
        var result: [FlatNode] = []
        let roots = orgRoles.filter { $0.parentRoleId == nil }
        for root in roots {
            appendNode(root, depth: 0, result: &result)
        }
        return result
    }

    private func appendNode(_ role: OrgRole, depth: Int, result: inout [FlatNode]) {
        result.append(FlatNode(role: role, depth: depth))
        let children = orgRoles.filter { $0.parentRoleId == role.id }
        for child in children {
            appendNode(child, depth: depth + 1, result: &result)
        }
    }

    // MARK: - Node Row

    @ViewBuilder
    private func nodeRow(role: OrgRole, depth: Int) -> some View {
        HStack(spacing: 4) {
            // Status dot
            Circle()
                .fill(roleStatusColor(role))
                .frame(width: 5, height: 5)
                .shadow(color: roleStatusColor(role).opacity(0.6), radius: 2)

            // Role name
            Text(role.name)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            // Agent type badge
            Text(role.roleType.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(roleTypeColor(role))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(roleTypeColor(role).opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.leading, CGFloat(depth) * 12)
    }

    // MARK: - Helpers

    private func roleStatusColor(_ role: OrgRole) -> Color {
        if role.assignedSlotId != nil {
            return Color.statusSuccess
        }
        return Color.textTertiary
    }

    private func roleTypeColor(_ role: OrgRole) -> Color {
        switch role.roleType.lowercased() {
        case "ceo", "lead":
            return Color.terminalYellow
        case "backend", "backend_lead":
            return Color.accentPrimary
        case "frontend", "frontend_lead":
            return Color.terminalMagenta
        case "qa", "testing":
            return Color.statusInfo
        case "devops", "infra":
            return Color.terminalGreen
        default:
            return Color.textSecondary
        }
    }
}

// MARK: - Preview

#if DEBUG
struct OrgChartPanelView_Previews: PreviewProvider {
    static var previews: some View {
        Text("OrgChartPanelView requires OrgRole data for preview")
            .foregroundStyle(Color.textTertiary)
            .frame(width: 280, height: 200)
            .background(Color.bgApp)
    }
}
#endif

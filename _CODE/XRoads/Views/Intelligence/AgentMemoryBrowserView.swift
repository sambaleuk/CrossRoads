import SwiftUI

// MARK: - AgentMemoryBrowserView

/// Browse and search persistent agent memories with filtering by agent type.
///
/// Phase 6: Intelligence layer — agent memory browser.
struct AgentMemoryBrowserView: View {
    let memories: [AgentMemory]
    var onClearOld: (() -> Void)?

    @State private var searchText: String = ""
    @State private var selectedFilter: AgentFilter = .all

    enum AgentFilter: String, CaseIterable {
        case all = "All"
        case claude = "Claude"
        case gemini = "Gemini"
        case codex = "Codex"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search and filter bar
            searchBar
                .padding(Theme.Spacing.sm)
                .background(Color.bgSurface)

            Divider()

            // Memory list
            if filteredMemories.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    Spacer()
                    Image(systemName: "brain")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.textTertiary)
                    Text("No memories found")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(filteredMemories, id: \.id) { memory in
                            memoryCard(memory)
                        }
                    }
                    .padding(Theme.Spacing.md)
                }
            }

            Divider()

            // Footer with clear button
            HStack {
                Text("\(filteredMemories.count) memories")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)

                Spacer()

                if let onClearOld {
                    Button {
                        onClearOld()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 9))
                            Text("Clear Old Memories")
                                .font(.system(size: 9, weight: .medium))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Color.bgSurface)
        }
        .background(Color.bgCanvas)
    }

    // MARK: - Search Bar

    @ViewBuilder
    private var searchBar: some View {
        VStack(spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.textTertiary)

                    TextField("Search memories...", text: $searchText)
                        .font(.system(size: 11, design: .monospaced))
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Color.bgApp)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Filter chips
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(AgentFilter.allCases, id: \.self) { filter in
                    filterChip(filter)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func filterChip(_ filter: AgentFilter) -> some View {
        let isSelected = selectedFilter == filter
        Button {
            selectedFilter = filter
        } label: {
            Text(filter.rawValue.uppercased())
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(isSelected ? Color.bgCanvas : agentColor(filter))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isSelected ? agentColor(filter) : agentColor(filter).opacity(0.1))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Memory Card

    @ViewBuilder
    private func memoryCard(_ memory: AgentMemory) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            // Top row: agent badge, domain, memory type
            HStack(spacing: Theme.Spacing.xs) {
                Text(memory.agentType.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(agentColor(for: memory.agentType))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(agentColor(for: memory.agentType).opacity(0.1))
                    .clipShape(Capsule())

                Text(memory.domain)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.statusInfo)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.statusInfo.opacity(0.1))
                    .clipShape(Capsule())

                Text(memory.memoryType.uppercased())
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textTertiary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.bgApp)
                    .clipShape(Capsule())

                Spacer()
            }

            // Content
            Text(memory.content)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.textPrimary)
                .lineLimit(3)

            // Bottom row: confidence, access count
            HStack(spacing: Theme.Spacing.sm) {
                // Confidence bar
                HStack(spacing: 4) {
                    Text("CONF")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.textTertiary)

                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.bgApp)
                                .frame(height: 4)

                            RoundedRectangle(cornerRadius: 2)
                                .fill(confidenceColor(memory.confidence))
                                .frame(width: max(0, geometry.size.width * CGFloat(memory.confidence)), height: 4)
                        }
                    }
                    .frame(width: 40, height: 4)

                    Text(String(format: "%.0f%%", memory.confidence * 100))
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(confidenceColor(memory.confidence))
                }

                Spacer()

                HStack(spacing: 2) {
                    Image(systemName: "eye")
                        .font(.system(size: 7))
                    Text("\(memory.accessCount)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Color.bgSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Color.borderMuted.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Filtering

    private var filteredMemories: [AgentMemory] {
        var result = memories

        // Filter by agent type
        if selectedFilter != .all {
            let filterType = selectedFilter.rawValue.lowercased()
            result = result.filter { $0.agentType.lowercased() == filterType }
        }

        // Filter by search text
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.content.lowercased().contains(query)
                    || $0.domain.lowercased().contains(query)
                    || $0.tags.lowercased().contains(query)
                    || $0.agentType.lowercased().contains(query)
            }
        }

        return result
    }

    // MARK: - Helpers

    private func agentColor(_ filter: AgentFilter) -> Color {
        switch filter {
        case .all: return Color.textSecondary
        case .claude: return Color.accentPrimary
        case .gemini: return Color.statusInfo
        case .codex: return Color.statusWarning
        }
    }

    private func agentColor(for agentType: String) -> Color {
        switch agentType.lowercased() {
        case "claude": return Color.accentPrimary
        case "gemini": return Color.statusInfo
        case "codex": return Color.statusWarning
        default: return Color.textSecondary
        }
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        if confidence >= 0.8 { return Color.statusSuccess }
        if confidence >= 0.5 { return Color.statusWarning }
        return Color.statusError
    }
}

// MARK: - Preview

#if DEBUG
struct AgentMemoryBrowserView_Previews: PreviewProvider {
    static var previews: some View {
        AgentMemoryBrowserView(memories: [])
            .frame(width: 600, height: 500)
            .background(Color.bgApp)
    }
}
#endif

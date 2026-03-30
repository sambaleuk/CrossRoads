import SwiftUI

// MARK: - IntelligenceSheetView

/// Container sheet with tabs for all Intelligence views: Learning, Memory,
/// Trust Scores, and Conflict Prediction.
///
/// Phase 6: Intelligence layer — sheet entry point.
struct IntelligenceSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: IntelligenceTab = .learning
    @State private var profiles: [PerformanceProfile] = []
    @State private var records: [LearningRecord] = []
    @State private var memories: [AgentMemory] = []
    @State private var trustScores: [TrustScore] = []
    @State private var isLoading: Bool = true
    @State private var loadError: String?

    enum IntelligenceTab: String, CaseIterable {
        case learning = "Learning"
        case memory = "Memory"
        case trust = "Trust"
        case conflicts = "Conflicts"

        var icon: String {
            switch self {
            case .learning: return "chart.bar.fill"
            case .memory: return "brain"
            case .trust: return "shield.checkered"
            case .conflicts: return "exclamationmark.triangle.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            sheetHeader

            Divider()

            // Tab bar
            tabBar

            Divider()

            // Content
            if isLoading {
                VStack(spacing: Theme.Spacing.md) {
                    Spacer()
                    ProgressView()
                        .controlSize(.regular)
                    Text("Loading intelligence data...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                VStack(spacing: Theme.Spacing.md) {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.statusError)
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.statusError)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                tabContent
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .background(Color.bgApp)
        .task {
            await loadData()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var sheetHeader: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentPrimary)

                Text("INTELLIGENCE")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
            }

            Spacer()

            Button {
                Task { await loadData() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Refresh data")

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Color.bgSurface)
    }

    // MARK: - Tab Bar

    @ViewBuilder
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(IntelligenceTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .background(Color.bgSurface)
    }

    @ViewBuilder
    private func tabButton(_ tab: IntelligenceTab) -> some View {
        let isSelected = selectedTab == tab
        Button {
            withAnimation(.easeInOut(duration: Theme.Animation.fast)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 9))
                Text(tab.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
            }
            .foregroundStyle(isSelected ? Color.accentPrimary : Color.textTertiary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(isSelected ? Color.accentPrimary.opacity(0.1) : Color.clear)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            if isSelected {
                Rectangle()
                    .fill(Color.accentPrimary)
                    .frame(height: 2)
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .learning:
            LearningDashboardView(profiles: profiles, records: records)
        case .memory:
            AgentMemoryBrowserView(memories: memories, onClearOld: {
                Task { await clearOldMemories() }
            })
        case .trust:
            TrustScoreDashboardView(trustScores: trustScores)
        case .conflicts:
            ConflictPredictionView(result: nil)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        loadError = nil

        do {
            let dbManager = try CockpitDatabaseManager(path: CockpitDatabaseManager.defaultPath())
            let dbQueue = await dbManager.dbQueue
            let learningRepo = LearningRepository(dbQueue: dbQueue)
            let memoryRepo = AgentMemoryRepository(dbQueue: dbQueue)
            let trustRepo = TrustScoreRepository(dbQueue: dbQueue, learningRepository: learningRepo)

            let fetchedProfiles = try await learningRepo.fetchAllProfiles()
            let fetchedRecords = try await learningRepo.fetchAllRecords()
            let fetchedMemories = try await memoryRepo.searchMemories(query: "")
            let fetchedTrust = try await trustRepo.fetchAllTrust()

            await MainActor.run {
                profiles = fetchedProfiles
                records = fetchedRecords
                memories = fetchedMemories
                trustScores = fetchedTrust
                isLoading = false
            }
        } catch {
            await MainActor.run {
                loadError = "Failed to load data: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func clearOldMemories() async {
        do {
            let dbManager = try CockpitDatabaseManager(path: CockpitDatabaseManager.defaultPath())
            let memoryRepo = await AgentMemoryRepository(databaseManager: dbManager)
            try await memoryRepo.forgetOld(olderThanDays: 30)
            await loadData()
        } catch {
            // Silently handle — data will refresh on next load
        }
    }
}

// MARK: - Preview

#if DEBUG
struct IntelligenceSheetView_Previews: PreviewProvider {
    static var previews: some View {
        IntelligenceSheetView()
            .frame(width: 700, height: 500)
    }
}
#endif

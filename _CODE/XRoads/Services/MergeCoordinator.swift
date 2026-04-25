import Foundation

/// Coordinates merging worktree branches back into the base branch.
actor MergeCoordinator {

    private let gitService: GitService
    /// Phase 5: Trust score repository for auto-merge policy (optional for backward compat)
    private let trustScoreRepo: TrustScoreRepository?

    init(gitService: GitService = GitService(), trustScoreRepo: TrustScoreRepository? = nil) {
        self.gitService = gitService
        self.trustScoreRepo = trustScoreRepo
    }

    func prepareMerge(
        assignments: [WorktreeAssignment],
        repoPath: URL,
        baseBranch: String? = nil
    ) async throws -> MergePlan {
        let base = try await resolveBaseBranch(baseBranch: baseBranch, repoPath: repoPath)
        guard !assignments.isEmpty else {
            return MergePlan(baseBranch: base, steps: [], createdAt: Date())
        }

        try await gitService.checkout(branch: base, repoPath: repoPath.path)

        var steps: [MergePlanStep] = []

        for assignment in assignments {
            var predictedConflicts: [String] = []
            var status: MergeStepStatus = .ready
            do {
                try await gitService.merge(
                    branch: assignment.branchName,
                    repoPath: repoPath.path,
                    noCommit: true,
                    noFastForward: true
                )
                try await gitService.resetHard(repoPath: repoPath.path)
            } catch GitError.commandFailed {
                predictedConflicts = try await gitService.listConflictedFiles(repoPath: repoPath.path)
                try? await gitService.abortMerge(repoPath: repoPath.path)
                status = .blocked
            }

            steps.append(
                MergePlanStep(
                    id: assignment.id,
                    assignment: assignment,
                    status: status,
                    predictedConflicts: predictedConflicts
                )
            )
        }

        return MergePlan(baseBranch: base, steps: steps, createdAt: Date())
    }

    func executeMerge(plan: MergePlan, repoPath: URL) async throws -> MergeResult {
        guard !plan.steps.isEmpty else {
            return MergeResult(baseBranch: plan.baseBranch, mergedBranches: [], conflicts: [], success: true, rolledBack: false)
        }

        try await gitService.checkout(branch: plan.baseBranch, repoPath: repoPath.path)

        // Capture base HEAD before any merges so we can fully roll back on partial failure
        let baseHeadBefore = try await gitService.getCurrentCommitHash(repoPath: repoPath.path)

        var mergedBranches: [String] = []
        var conflicts: [MergeConflict] = []
        var rolledBack = false

        for step in plan.steps {
            // WIRING 4: Check trust score to decide auto-merge vs human approval
            if let trustScoreRepo = trustScoreRepo {
                let agentType = step.assignment.agentType.rawValue
                let domain = "general" // Could be derived from file patterns in a future iteration
                let canAutoMerge = (try? await trustScoreRepo.shouldAutoMerge(agentType: agentType, domain: domain)) ?? false
                if !canAutoMerge {
                    // Trust too low for auto-merge — mark as blocked, require human review
                    conflicts.append(
                        MergeConflict(
                            branch: step.assignment.branchName,
                            files: [],
                            message: "Trust score too low for auto-merge (agent: \(agentType)). Requires human approval."
                        )
                    )
                    continue
                }
            }

            guard step.status == .ready else {
                conflicts.append(
                    MergeConflict(
                        branch: step.assignment.branchName,
                        files: step.predictedConflicts,
                        message: "Merge blocked during preparation"
                    )
                )
                continue
            }

            do {
                try await gitService.merge(
                    branch: step.assignment.branchName,
                    repoPath: repoPath.path,
                    noCommit: false,
                    noFastForward: true
                )
                mergedBranches.append(step.assignment.branchName)
            } catch GitError.commandFailed(_, _, let stderr) {
                let files = try await gitService.listConflictedFiles(repoPath: repoPath.path)
                conflicts.append(
                    MergeConflict(
                        branch: step.assignment.branchName,
                        files: files,
                        message: stderr
                    )
                )
                // Leave the merge in-progress so the user can resolve conflicts
                // via Keep Ours / Keep Theirs / manual editing in the UI.
                // Previously we aborted + reset here, which destroyed the merge
                // state and made the resolution buttons no-ops.
                break
            }
        }

        return MergeResult(
            baseBranch: plan.baseBranch,
            mergedBranches: mergedBranches,
            conflicts: conflicts,
            success: conflicts.isEmpty,
            rolledBack: rolledBack
        )
    }

    /// Commits the current in-progress merge after the user has resolved all conflicts.
    /// Call this after Keep Ours / Keep Theirs / manual edits have been applied and staged.
    func commitResolvedMerge(repoPath: URL, branch: String) async throws {
        try await gitService.commit(
            message: "Merge branch '\(branch)' — conflicts resolved manually",
            repoPath: repoPath.path
        )
    }

    /// Aborts the current in-progress merge and resets to the given ref (or HEAD).
    func rollbackMerge(repoPath: URL, toRef: String? = nil) async throws {
        try await gitService.abortMerge(repoPath: repoPath.path)
        if let ref = toRef {
            try await gitService.resetHard(repoPath: repoPath.path, reference: ref)
        }
    }
}

private extension MergeCoordinator {
    func resolveBaseBranch(baseBranch: String?, repoPath: URL) async throws -> String {
        if let baseBranch {
            return baseBranch
        }
        return try await gitService.getCurrentBranch(path: repoPath.path)
    }
}

import Foundation
import os

// MARK: - OrgChartError

enum OrgChartError: LocalizedError, Sendable {
    case unknownTemplate(String)
    case sessionHasNoRoles(UUID)
    case roleNotFound(UUID)
    case ceoRoleNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .unknownTemplate(let name):
            return "Unknown org template: \(name)"
        case .sessionHasNoRoles(let id):
            return "Session \(id) has no org roles"
        case .roleNotFound(let id):
            return "OrgRole not found: \(id)"
        case .ceoRoleNotFound(let id):
            return "CEO role not found in session \(id)"
        }
    }
}

// MARK: - OrgRoleNode

/// Tree node wrapping an OrgRole with its children for hierarchy display.
struct OrgRoleNode: Codable, Sendable {
    let role: OrgRole
    var children: [OrgRoleNode]
}

// MARK: - OrgTemplateEntry

/// Static definition for a role within an org template.
private struct OrgTemplateEntry: Sendable {
    let name: String
    let roleType: String
    let parentIndex: Int?
    let responsibilities: String
    let authority: String
}

// MARK: - OrgChartService

/// Manages organizational role hierarchies within cockpit sessions.
///
/// Provides template-based org creation, goal cascading through the hierarchy,
/// and gate approval routing based on risk level and authority.
actor OrgChartService {

    private let logger = Logger(subsystem: "com.xroads", category: "OrgChart")
    private let orgRoleRepository: OrgRoleRepository

    init(orgRoleRepository: OrgRoleRepository) {
        self.orgRoleRepository = orgRoleRepository
    }

    // MARK: - Templates

    /// Applies a named org template to a session, creating all roles with hierarchy.
    ///
    /// - Parameters:
    ///   - sessionId: The cockpit session to populate
    ///   - templateName: One of: SoloDev, Duo, Squad, FullTeam
    /// - Returns: Array of created OrgRole records
    func applyTemplate(sessionId: UUID, templateName: String) async throws -> [OrgRole] {
        guard let entries = Self.templates[templateName] else {
            throw OrgChartError.unknownTemplate(templateName)
        }

        logger.info("Applying org template '\(templateName)' to session \(sessionId)")

        // Create roles in order so parent IDs can be resolved by index
        var createdRoles: [OrgRole] = []

        for entry in entries {
            let parentId: UUID? = entry.parentIndex.map { createdRoles[$0].id }

            let role = OrgRole(
                sessionId: sessionId,
                name: entry.name,
                roleType: entry.roleType,
                parentRoleId: parentId,
                goalDescription: entry.responsibilities,
                authority: entry.authority
            )

            let persisted = try await orgRoleRepository.create(role)
            createdRoles.append(persisted)
        }

        logger.info("Created \(createdRoles.count) roles for session \(sessionId)")
        return createdRoles
    }

    // MARK: - Goal Cascading

    /// Distributes a CEO-level goal down the org hierarchy.
    /// Each role receives a scoped goal derived from its responsibilities and the parent goal.
    ///
    /// - Parameters:
    ///   - sessionId: The cockpit session
    ///   - ceoGoal: The top-level objective from the CEO role
    /// - Returns: Array of (roleId, assignedGoal) tuples
    func cascadeGoals(sessionId: UUID, ceoGoal: String) async throws -> [(UUID, String)] {
        let roles = try await orgRoleRepository.fetchBySession(sessionId: sessionId)

        guard !roles.isEmpty else {
            throw OrgChartError.sessionHasNoRoles(sessionId)
        }

        // Find the CEO/root role (no parent)
        guard let ceoRole = roles.first(where: { $0.parentRoleId == nil }) else {
            throw OrgChartError.ceoRoleNotFound(sessionId)
        }

        var results: [(UUID, String)] = []

        // Assign CEO goal to root
        var updatedCeo = ceoRole
        updatedCeo.goalDescription = ceoGoal
        updatedCeo.updatedAt = Date()
        try await orgRoleRepository.update(updatedCeo)
        results.append((ceoRole.id, ceoGoal))

        // Cascade to children recursively
        try await cascadeToChildren(
            parentId: ceoRole.id,
            parentGoal: ceoGoal,
            allRoles: roles,
            results: &results
        )

        logger.info("Cascaded goals to \(results.count) roles in session \(sessionId)")
        return results
    }

    // MARK: - Gate Approval Routing

    /// Determines which role should approve an execution gate based on risk level.
    ///
    /// Routing rules:
    /// - Low/Medium: auto-approve if the slot's role has "full" authority, else escalate to parent
    /// - High: always route to parent role
    /// - Critical: always route to the CEO (root) role
    ///
    /// - Parameters:
    ///   - sessionId: The cockpit session
    ///   - slotId: The agent slot requesting approval
    ///   - riskLevel: One of: low, medium, high, critical
    /// - Returns: UUID of the role that should approve the gate
    func routeGateApproval(sessionId: UUID, slotId: UUID, riskLevel: String) async throws -> UUID {
        let roles = try await orgRoleRepository.fetchBySession(sessionId: sessionId)

        guard !roles.isEmpty else {
            throw OrgChartError.sessionHasNoRoles(sessionId)
        }

        // Find the role assigned to this slot
        let slotRole = roles.first(where: { $0.assignedSlotId == slotId })

        // Find the CEO (root) role
        guard let ceoRole = roles.first(where: { $0.parentRoleId == nil }) else {
            throw OrgChartError.ceoRoleNotFound(sessionId)
        }

        switch riskLevel.lowercased() {
        case "low", "medium":
            // Auto-approve if role has full authority
            if let role = slotRole, role.authority == "full" {
                return role.id
            }
            // Escalate to parent, fallback to CEO
            if let role = slotRole, let parentId = role.parentRoleId {
                return parentId
            }
            return ceoRole.id

        case "high":
            // Always route to parent role
            if let role = slotRole, let parentId = role.parentRoleId {
                return parentId
            }
            return ceoRole.id

        case "critical":
            // Always route to CEO
            return ceoRole.id

        default:
            // Unknown risk level, route to CEO for safety
            return ceoRole.id
        }
    }

    // MARK: - Tree Building

    /// Builds a tree structure from the flat role list for a session.
    ///
    /// - Parameter sessionId: The cockpit session
    /// - Returns: Array of root-level OrgRoleNode trees
    func getTree(sessionId: UUID) async throws -> [OrgRoleNode] {
        let roles = try await orgRoleRepository.fetchBySession(sessionId: sessionId)

        guard !roles.isEmpty else {
            throw OrgChartError.sessionHasNoRoles(sessionId)
        }

        // Index roles by ID for fast lookup
        let rolesById = Dictionary(uniqueKeysWithValues: roles.map { ($0.id, $0) })

        // Group children by parent ID
        var childrenByParent: [UUID: [OrgRole]] = [:]
        var rootRoles: [OrgRole] = []

        for role in roles {
            if let parentId = role.parentRoleId {
                childrenByParent[parentId, default: []].append(role)
            } else {
                rootRoles.append(role)
            }
        }

        // Build tree recursively from roots
        func buildNode(for role: OrgRole) -> OrgRoleNode {
            let children = childrenByParent[role.id] ?? []
            let childNodes = children.map { buildNode(for: $0) }
            return OrgRoleNode(role: role, children: childNodes)
        }

        return rootRoles.map { buildNode(for: $0) }
    }

    // MARK: - Private Helpers

    private func cascadeToChildren(
        parentId: UUID,
        parentGoal: String,
        allRoles: [OrgRole],
        results: inout [(UUID, String)]
    ) async throws {
        let children = allRoles.filter { $0.parentRoleId == parentId }

        for child in children {
            // Derive a scoped goal from the parent goal and role responsibilities
            let scopedGoal = deriveGoal(parentGoal: parentGoal, role: child)

            var updated = child
            updated.goalDescription = scopedGoal
            updated.updatedAt = Date()
            try await orgRoleRepository.update(updated)
            results.append((child.id, scopedGoal))

            // Recurse into grandchildren
            try await cascadeToChildren(
                parentId: child.id,
                parentGoal: scopedGoal,
                allRoles: allRoles,
                results: &results
            )
        }
    }

    /// Derives a scoped goal for a child role based on its type and the parent goal.
    private func deriveGoal(parentGoal: String, role: OrgRole) -> String {
        let roleType = role.roleType.lowercased()
        let prefix: String

        switch roleType {
        case "backend", "backend_lead":
            prefix = "Backend implementation"
        case "frontend", "frontend_lead":
            prefix = "Frontend implementation"
        case "qa", "testing":
            prefix = "Quality assurance and testing"
        case "devops", "infra":
            prefix = "Infrastructure and deployment"
        case "design", "ui_ux":
            prefix = "Design and UX"
        case "lead", "ceo":
            prefix = "Overall coordination"
        default:
            prefix = "\(role.name) scope"
        }

        return "\(prefix) for: \(parentGoal)"
    }

    // MARK: - Template Definitions

    private static let templates: [String: [OrgTemplateEntry]] = [
        "SoloDev": [
            OrgTemplateEntry(
                name: "Solo Developer",
                roleType: "lead",
                parentIndex: nil,
                responsibilities: "Full-stack development, testing, and deployment",
                authority: "full"
            ),
        ],
        "Duo": [
            OrgTemplateEntry(
                name: "Lead Developer",
                roleType: "lead",
                parentIndex: nil,
                responsibilities: "Architecture, code review, and coordination",
                authority: "full"
            ),
            OrgTemplateEntry(
                name: "Implementation Agent",
                roleType: "backend",
                parentIndex: 0,
                responsibilities: "Feature implementation and unit testing",
                authority: "limited"
            ),
        ],
        "Squad": [
            OrgTemplateEntry(
                name: "CEO / Tech Lead",
                roleType: "ceo",
                parentIndex: nil,
                responsibilities: "Architecture decisions, gate approvals, and coordination",
                authority: "full"
            ),
            OrgTemplateEntry(
                name: "Backend Agent",
                roleType: "backend",
                parentIndex: 0,
                responsibilities: "Backend logic, APIs, data layer, and backend tests",
                authority: "limited"
            ),
            OrgTemplateEntry(
                name: "Frontend Agent",
                roleType: "frontend",
                parentIndex: 0,
                responsibilities: "UI components, views, styling, and frontend tests",
                authority: "limited"
            ),
            OrgTemplateEntry(
                name: "QA Agent",
                roleType: "qa",
                parentIndex: 0,
                responsibilities: "Integration tests, regression tests, and bug reports",
                authority: "limited"
            ),
        ],
        "FullTeam": [
            OrgTemplateEntry(
                name: "CEO / Architect",
                roleType: "ceo",
                parentIndex: nil,
                responsibilities: "Strategic direction, architecture, and final approvals",
                authority: "full"
            ),
            OrgTemplateEntry(
                name: "Backend Lead",
                roleType: "backend_lead",
                parentIndex: 0,
                responsibilities: "Backend architecture, API design, and backend team coordination",
                authority: "full"
            ),
            OrgTemplateEntry(
                name: "Frontend Lead",
                roleType: "frontend_lead",
                parentIndex: 0,
                responsibilities: "Frontend architecture, component library, and frontend team coordination",
                authority: "full"
            ),
            OrgTemplateEntry(
                name: "Backend Agent A",
                roleType: "backend",
                parentIndex: 1,
                responsibilities: "Core backend features and data models",
                authority: "limited"
            ),
            OrgTemplateEntry(
                name: "Backend Agent B",
                roleType: "backend",
                parentIndex: 1,
                responsibilities: "API endpoints and integrations",
                authority: "limited"
            ),
            OrgTemplateEntry(
                name: "Frontend Agent",
                roleType: "frontend",
                parentIndex: 2,
                responsibilities: "UI implementation and component development",
                authority: "limited"
            ),
            OrgTemplateEntry(
                name: "QA Agent",
                roleType: "qa",
                parentIndex: 0,
                responsibilities: "End-to-end testing, integration tests, and quality gates",
                authority: "limited"
            ),
        ],
    ]
}

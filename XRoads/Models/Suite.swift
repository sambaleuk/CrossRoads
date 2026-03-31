import Foundation

// MARK: - Suite

/// A mission profile that configures XRoads for a specific type of work.
///
/// Suites define what roles the chairman can assign, which skills to load,
/// what deliverables to produce, and what phases the brain should orchestrate.
/// The same XRoads engine powers every suite — only the configuration changes.
struct Suite: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let description: String
    let icon: String                  // SF Symbol
    let roles: [SuiteRole]           // Roles the chairman can assign to slots
    let skillPaths: [String]         // Directories to load skills from
    let deliverableCategories: [String]  // What to produce in .crossroads/deliverables/
    let phases: [SuitePhase]         // Orchestration phases for the brain
    let domainKeywords: [String: [String]]  // Domain detection overrides
}

// MARK: - SuiteRole

/// A role that the chairman can assign to a slot within this suite.
struct SuiteRole: Codable, Hashable, Sendable {
    let id: String                // "implementer", "copywriter", "analyst"
    let name: String              // "Copywriter"
    let description: String       // "Writes marketing copy, landing pages, emails"
    let icon: String              // SF Symbol
    let skillIds: [String]        // Skills to load for this role
    let agentPreference: String?  // Preferred agent type ("claude", "gemini", nil = any)
    let actionType: String        // Maps to ActionType.rawValue or "custom"
}

// MARK: - SuitePhase

/// An orchestration phase that the cockpit brain sequences through.
struct SuitePhase: Codable, Hashable, Sendable {
    let id: String                // "understand", "create", "review", "deliver"
    let name: String              // "CREATE"
    let description: String       // "Main production phase"
    let roleIds: [String]         // Which roles are active in this phase
    let transitionCondition: String  // "all_stories_done", "deliverables_80_percent", "manual"
}

// MARK: - Built-in Suites

extension Suite {

    /// Developer suite — the original XRoads experience.
    static let developer = Suite(
        id: "developer",
        name: "Developer",
        description: "Multi-agent software development with PRD-driven orchestration",
        icon: "chevron.left.forwardslash.chevron.right",
        roles: [
            SuiteRole(id: "implementer", name: "Implementer", description: "Feature development from PRD stories with unit tests", icon: "hammer.fill", skillIds: ["prd", "code-writer", "commit"], agentPreference: "claude", actionType: "implement"),
            SuiteRole(id: "tester", name: "Tester", description: "Integration, E2E, and performance testing", icon: "testtube.2", skillIds: ["integration-test", "e2e-test", "perf-test"], agentPreference: "gemini", actionType: "integrationTest"),
            SuiteRole(id: "reviewer", name: "Reviewer", description: "Deep code review — OWASP, SOLID, complexity", icon: "eye.fill", skillIds: ["code-reviewer", "lint"], agentPreference: "claude", actionType: "review"),
            SuiteRole(id: "writer", name: "Doc Writer", description: "README, API docs, architecture guides", icon: "doc.text.fill", skillIds: ["doc-generator"], agentPreference: nil, actionType: "write"),
            SuiteRole(id: "debugger", name: "Debugger", description: "Bug reproduction, diagnosis, and fix", icon: "ladybug.fill", skillIds: ["code-reviewer", "commit"], agentPreference: "claude", actionType: "debug"),
            SuiteRole(id: "security", name: "Security Auditor", description: "Vulnerability assessment and compliance", icon: "lock.shield.fill", skillIds: ["code-reviewer"], agentPreference: "claude", actionType: "review"),
            SuiteRole(id: "devops", name: "DevOps", description: "CI/CD, infrastructure, deployment", icon: "server.rack", skillIds: [], agentPreference: "claude", actionType: "custom"),
        ],
        skillPaths: ["bundled://Skills"],
        deliverableCategories: ["documentation", "ops"],
        phases: [
            SuitePhase(id: "understand", name: "UNDERSTAND", description: "Scan codebase, detect patterns, assess state", roleIds: ["reviewer"], transitionCondition: "manual"),
            SuitePhase(id: "build", name: "BUILD", description: "Implement stories in parallel", roleIds: ["implementer", "writer"], transitionCondition: "all_stories_done"),
            SuitePhase(id: "verify", name: "VERIFY", description: "Test and review all implementations", roleIds: ["tester", "reviewer", "security"], transitionCondition: "all_tests_pass"),
            SuitePhase(id: "deliver", name: "DELIVER", description: "Finalize docs, merge prep, retro", roleIds: ["writer", "devops"], transitionCondition: "manual"),
        ],
        domainKeywords: [:]  // Uses default detection
    )

    /// Marketing suite — content creation, GTM, growth.
    /// Leverages 16 vibe-marketing skills from ~/.claude/skills/vibe-marketing/
    static let marketer = Suite(
        id: "marketer",
        name: "Marketer",
        description: "Content creation, copywriting, SEO, email campaigns, and go-to-market strategy. 16 specialized marketing skills.",
        icon: "megaphone.fill",
        roles: [
            SuiteRole(id: "copywriter", name: "Copywriter", description: "Landing pages, value props, direct response copy, lead magnets", icon: "text.cursor",
                       skillIds: ["05-direct-response-copy", "01-brand-voice", "04-lead-magnet"], agentPreference: "claude", actionType: "custom"),
            SuiteRole(id: "seo", name: "SEO Specialist", description: "Keyword research, SEO content, blog articles, FAQ sections", icon: "magnifyingglass",
                       skillIds: ["03-keyword-research", "06-seo-content"], agentPreference: "claude", actionType: "custom"),
            SuiteRole(id: "email", name: "Email Strategist", description: "Welcome sequences, nurture drips, newsletters, launch campaigns", icon: "envelope.fill",
                       skillIds: ["08-email-sequences", "07-newsletter"], agentPreference: "claude", actionType: "custom"),
            SuiteRole(id: "social", name: "Social Creator", description: "Content atomization, social graphics, carousel copy, video scripts", icon: "bubble.left.and.bubble.right.fill",
                       skillIds: ["09-content-atomizer", "14-social-graphics", "15-product-video"], agentPreference: nil, actionType: "custom"),
            SuiteRole(id: "strategist", name: "Growth Strategist", description: "Market positioning, competitive analysis, GTM planning, orchestration", icon: "chart.line.uptrend.xyaxis",
                       skillIds: ["02-positioning-angles", "10-orchestrator", "11-creative-strategist"], agentPreference: "claude", actionType: "custom"),
            SuiteRole(id: "creative", name: "Creative Director", description: "Visual DNA, image generation, product photography, brand assets", icon: "paintbrush.fill",
                       skillIds: ["11-creative-strategist", "12-image-generation", "13-product-photography", "16-talking-head"], agentPreference: "claude", actionType: "custom"),
        ],
        skillPaths: ["~/.claude/skills/vibe-marketing"],
        deliverableCategories: ["marketing", "strategy", "research"],
        phases: [
            SuitePhase(id: "foundation", name: "FOUNDATION", description: "Brand voice + positioning angles + keyword map. Must happen first.", roleIds: ["strategist", "seo"], transitionCondition: "manual"),
            SuitePhase(id: "create", name: "CREATE", description: "All content assets in parallel: copy, emails, social, visuals", roleIds: ["copywriter", "email", "social", "creative"], transitionCondition: "deliverables_complete"),
            SuitePhase(id: "multiply", name: "MULTIPLY", description: "Atomize content: 1 blog post → 15 pieces across channels", roleIds: ["social", "email"], transitionCondition: "manual"),
            SuitePhase(id: "publish", name: "PUBLISH", description: "Final formatting, A/B variants, scheduling prep, distribution", roleIds: ["strategist", "social", "email"], transitionCondition: "manual"),
        ],
        domainKeywords: [
            "saas-growth": ["saas", "mrr", "churn", "onboarding", "activation", "retention"],
            "ecommerce": ["product", "catalog", "cart", "checkout", "shipping"],
            "b2b": ["enterprise", "pipeline", "outreach", "cold-email", "linkedin"],
            "content": ["blog", "newsletter", "podcast", "youtube", "social"],
            "local": ["artisan", "commerce", "ville", "region", "local"],
        ]
    )

    /// Researcher/Analyst suite — deep analysis, competitive intel, reports.
    static let researcher = Suite(
        id: "researcher",
        name: "Researcher",
        description: "Competitive intelligence, market analysis, technical research, and report generation",
        icon: "magnifyingglass.circle.fill",
        roles: [
            SuiteRole(id: "analyst", name: "Analyst", description: "Data analysis, pattern detection, insight extraction", icon: "chart.bar.fill", skillIds: [], agentPreference: "claude", actionType: "custom"),
            SuiteRole(id: "researcher", name: "Researcher", description: "Deep web research, paper analysis, trend mapping", icon: "book.fill", skillIds: [], agentPreference: "claude", actionType: "custom"),
            SuiteRole(id: "competitor", name: "Competitive Intel", description: "Competitor analysis, feature comparison, positioning gaps", icon: "person.2.fill", skillIds: [], agentPreference: "claude", actionType: "custom"),
            SuiteRole(id: "reporter", name: "Report Writer", description: "Executive summaries, briefing docs, presentations", icon: "doc.richtext.fill", skillIds: ["doc-generator"], agentPreference: nil, actionType: "write"),
        ],
        skillPaths: [],
        deliverableCategories: ["research", "strategy"],
        phases: [
            SuitePhase(id: "scope", name: "SCOPE", description: "Define research questions, identify sources", roleIds: ["researcher"], transitionCondition: "manual"),
            SuitePhase(id: "gather", name: "GATHER", description: "Collect data, read sources, extract facts", roleIds: ["researcher", "competitor", "analyst"], transitionCondition: "manual"),
            SuitePhase(id: "analyze", name: "ANALYZE", description: "Cross-reference, detect patterns, form insights", roleIds: ["analyst", "competitor"], transitionCondition: "manual"),
            SuitePhase(id: "report", name: "REPORT", description: "Synthesize findings into deliverables", roleIds: ["reporter", "analyst"], transitionCondition: "deliverables_complete"),
        ],
        domainKeywords: [:]
    )

    /// Operations suite — compliance, finance, legal, HR.
    static let ops = Suite(
        id: "ops",
        name: "Operations",
        description: "Compliance audits, financial analysis, legal review, and operational reporting",
        icon: "building.2.fill",
        roles: [
            SuiteRole(id: "finance", name: "Finance Analyst", description: "Budget analysis, cost optimization, financial reporting", icon: "dollarsign.circle.fill", skillIds: ["finance-analyst"], agentPreference: "claude", actionType: "custom"),
            SuiteRole(id: "legal", name: "Legal Clerk", description: "Contract review, compliance checks, policy drafting", icon: "scale.3d", skillIds: ["legal-clerk"], agentPreference: "claude", actionType: "custom"),
            SuiteRole(id: "hr", name: "HR Manager", description: "Process documentation, handbook updates, policy review", icon: "person.crop.circle.fill", skillIds: ["hr-wiki-manager"], agentPreference: nil, actionType: "custom"),
            SuiteRole(id: "auditor", name: "Compliance Auditor", description: "Regulatory compliance, GDPR/SOC2 checks, risk assessment", icon: "checkmark.shield.fill", skillIds: [], agentPreference: "claude", actionType: "custom"),
        ],
        skillPaths: ["bundled://Skills/ops"],
        deliverableCategories: ["ops", "documentation"],
        phases: [
            SuitePhase(id: "assess", name: "ASSESS", description: "Audit current state, identify gaps", roleIds: ["auditor", "finance"], transitionCondition: "manual"),
            SuitePhase(id: "execute", name: "EXECUTE", description: "Process work items in parallel", roleIds: ["finance", "legal", "hr"], transitionCondition: "manual"),
            SuitePhase(id: "validate", name: "VALIDATE", description: "Cross-check, verify compliance", roleIds: ["auditor"], transitionCondition: "manual"),
            SuitePhase(id: "deliver", name: "DELIVER", description: "Finalize reports and deliverables", roleIds: ["finance", "legal", "hr"], transitionCondition: "deliverables_complete"),
        ],
        domainKeywords: [
            "compliance": ["gdpr", "soc2", "hipaa", "iso", "audit", "regulation"],
            "finance": ["budget", "revenue", "cost", "invoice", "forecast"],
        ]
    )

    /// All built-in suites.
    static let builtIn: [Suite] = [.developer, .marketer, .researcher, .ops]
}

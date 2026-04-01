//
//  NotificationNames.swift
//  XRoads
//
//  Notification names used throughout the app for cross-component communication.
//

import Foundation

// MARK: - Notification Names

extension Notification.Name {
    /// Notification to show the new worktree sheet
    static let showNewWorktreeSheet = Notification.Name("showNewWorktreeSheet")

    /// Notification to close the selected worktree
    static let closeSelectedWorktree = Notification.Name("closeSelectedWorktree")

    /// Notification to stop the agent of the selected worktree
    static let stopSelectedAgent = Notification.Name("stopSelectedAgent")

    /// Notification to clear logs
    static let clearLogs = Notification.Name("clearLogs")

    /// Notification to show command palette
    static let showCommandPalette = Notification.Name("showCommandPalette")

    /// Notification to request app quit with cleanup
    static let requestAppQuit = Notification.Name("requestAppQuit")

    /// Notification to open PRD Assistant
    static let openPRDAssistant = Notification.Name("openPRDAssistant")

    /// Notification to open Worktree Creator
    static let openWorktreeCreator = Notification.Name("openWorktreeCreator")

    /// Notification to open Art Direction pipeline
    static let openArtDirection = Notification.Name("openArtDirection")

    /// Notification to open Skills Browser
    static let openSkillsBrowser = Notification.Name("openSkillsBrowser")

    /// Notification to launch quick loop on current branch
    static let launchQuickLoop = Notification.Name("launchQuickLoop")

    /// Notification to load a PRD file from path
    static let loadPRDFromPath = Notification.Name("loadPRDFromPath")

    /// Notification to launch an agent loop with PRD
    /// UserInfo keys: agent (AgentType), prdPath (String), branch (String), projectPath (String)
    static let launchAgentLoop = Notification.Name("launchAgentLoop")

    /// Notification to open slot configuration sheet (Phase 2: Chat Integration)
    /// UserInfo keys: slotNumber (String), agentType (String?), actionType (String?)
    static let openSlotConfiguration = Notification.Name("openSlotConfiguration")

    /// Posted by CockpitViewModel when slots are auto-launched.
    static let cockpitSlotLaunched = Notification.Name("cockpitSlotLaunched")

    /// Posted when a cockpit-launched agent produces PTY output.
    /// UserInfo: "slotNumber" (Int), "output" (String), "agentType" (String)
    static let cockpitSlotOutput = Notification.Name("cockpitSlotOutput")

    /// Posted when a cockpit-launched agent terminates.
    /// UserInfo: "slotNumber" (Int), "exitCode" (Int32)
    static let cockpitSlotTerminated = Notification.Name("cockpitSlotTerminated")

    // MARK: - Cockpit Brain (PRD-S09)

    /// Posted when the cockpit brain Claude Code session starts.
    static let cockpitBrainStarted = Notification.Name("cockpitBrainStarted")

    /// Posted when the cockpit brain Claude Code session stops.
    static let cockpitBrainStopped = Notification.Name("cockpitBrainStopped")

    /// Posted when the cockpit brain produces output.
    /// UserInfo: "type" (String: thinking/action/decision/loop/subagent/error),
    ///           "content" (String), "timestamp" (Date)
    static let cockpitBrainOutput = Notification.Name("cockpitBrainOutput")

    /// Posted when the cockpit brain wants to send a message to the chat panel.
    /// UserInfo: "content" (String), "role" (String: "system" or "assistant")
    static let cockpitBrainToChat = Notification.Name("cockpitBrainToChat")

    /// Posted when the brain requests a slot launch.
    /// UserInfo: "agentType" (String), "role" (String), "task" (String)
    static let brainRequestsSlotLaunch = Notification.Name("brainRequestsSlotLaunch")

    /// Posted when a cockpit session closes with an OrchestrationRecord ready for persistence.
    /// UserInfo: "record" (OrchestrationRecord)
    static let cockpitSessionRecordReady = Notification.Name("cockpitSessionRecordReady")
}

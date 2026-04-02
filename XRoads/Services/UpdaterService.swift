import Foundation
import SwiftUI
import Sparkle

// MARK: - UpdaterService

/// Manages app updates via Sparkle framework.
/// Checks for updates on startup and provides a manual check action.
///
/// Configuration:
/// - Set XROADS_APPCAST_URL env var or use the default GitHub releases URL
/// - The appcast.xml must be hosted at the configured URL
/// - Builds must be signed with EdDSA key for Sparkle verification
@MainActor
@Observable
final class UpdaterService {

    /// Sparkle updater controller
    private let updaterController: SPUStandardUpdaterController

    /// Whether an update is currently being checked
    var isCheckingForUpdates: Bool = false

    /// The appcast URL — defaults to GitHub releases, overridable via env var
    static let appcastURL: String = {
        ProcessInfo.processInfo.environment["XROADS_APPCAST_URL"]
            ?? "https://github.com/Nexus-Neurogrid/XRoads/releases/latest/download/appcast.xml"
    }()

    init() {
        // Initialize Sparkle with the standard UI controller
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        // Configure the feed URL
        if let url = URL(string: Self.appcastURL) {
            updaterController.updater.setFeedURL(url)
        }

        // Auto-check on startup (Sparkle handles the interval)
        updaterController.updater.automaticallyChecksForUpdates = true
        updaterController.updater.updateCheckInterval = 3600 // 1 hour
    }

    /// Manually check for updates (from menu or settings)
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// Whether the updater can check (not already in progress)
    var canCheckForUpdates: Bool {
        updaterController.updater.canCheckForUpdates
    }
}

// MARK: - SwiftUI Menu Integration

/// A SwiftUI view that wraps Sparkle's "Check for Updates" menu item.
struct CheckForUpdatesView: View {
    let updater: UpdaterService

    var body: some View {
        Button("Check for Updates...") {
            updater.checkForUpdates()
        }
        .disabled(!updater.canCheckForUpdates)
    }
}

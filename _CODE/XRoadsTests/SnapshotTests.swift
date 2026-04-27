import XCTest
import SwiftUI
import AppKit
@testable import XRoadsLib

@MainActor
final class SnapshotTests: XCTestCase {

    // US-007: per-user temp path so SnapshotTests run on any machine.
    // Replaces a previously hardcoded developer-home path that failed with
    // Permission denied on every other account and leaked the username via
    // MCP CHATTER scan logs.
    private let outputDir = FileManager.default
        .temporaryDirectory
        .appendingPathComponent("xroads-snapshots", isDirectory: true)
        .path

    override func setUp() async throws {
        try FileManager.default.createDirectory(
            atPath: outputDir,
            withIntermediateDirectories: true
        )
    }

    func test_01_TitleBar() throws {
        let view = TitleBar(
            showChatPanel: .constant(true),
            showInspector: .constant(true),
            showCockpitPanel: false,
            pendingProposalCount: 3,
            onToggleChat: {},
            onToggleCockpit: {},
            onToggleReview: {},
            onStartSession: {},
            onLoadPRD: {},
            onShowHistory: {},
            onShowIntelligence: {},
            onShowSkills: {},
            onShowArtDirection: {}
        )
        .frame(width: 1440, height: 30)
        .environment(\.appState, AppState())

        try render(view, size: CGSize(width: 1440, height: 30), to: "01-titlebar.png")
    }

    func test_02_HeroIdleState() throws {
        let view = HeroIdleState(snapshotScanlineSeed: 0.42)
            .frame(width: 1000, height: 640)
            .background(Theme.Color.void)

        try render(view, size: CGSize(width: 1000, height: 640), to: "02-hero-idle.png")
    }

    func test_03_OrchestratorSidebar() throws {
        let view = OrchestratorSidebar(snapshotCursorOn: true)
            .frame(width: 320, height: 720)
            .background(Theme.Color.void)

        try render(view, size: CGSize(width: 320, height: 720), to: "03-orchestrator-sidebar.png")
    }

    func test_04_StatusBar() throws {
        let view = VStack(spacing: 0) {
            StatusBar(snapshotShimmerOn: true)
            StatusBar(label: "EXEC", status: "compiling layer 02 / 04",
                      progress: 0.42, agentCount: 3, agentMax: 6,
                      snapshotShimmerOn: true)
        }
        .frame(width: 1000, height: 60)
        .background(Theme.Color.void)

        try render(view, size: CGSize(width: 1000, height: 60), to: "04-status-bar.png")
    }

    func test_05_BottomBar() throws {
        let view = VStack(spacing: 0) {
            BottomBar()
            BottomBar(sectionName: "LOOP SCRIPTS", counterCount: 2, counterTotal: 4, allHealthy: false)
        }
        .frame(width: 1000, height: 52)
        .background(Theme.Color.void)

        try render(view, size: CGSize(width: 1000, height: 52), to: "05-bottom-bar.png")
    }

    // MARK: - Helpers

    private func render<V: View>(_ view: V, size: CGSize, to filename: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 4  // 4x: inspect-grade detail on small chrome (0.5pt rules, mono tracking)
        renderer.proposedSize = ProposedViewSize(size)

        guard let image = renderer.nsImage else {
            XCTFail("ImageRenderer returned nil for \(filename)")
            return
        }

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode PNG for \(filename)")
            return
        }

        let url = URL(fileURLWithPath: outputDir).appendingPathComponent(filename)
        try png.write(to: url)
        print("📸 wrote \(url.path) (\(png.count) bytes)")
    }
}

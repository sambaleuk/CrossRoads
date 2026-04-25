import XCTest
import SwiftUI
import AppKit
@testable import XRoadsLib

@MainActor
final class SnapshotTests: XCTestCase {

    private let outputDir = "/Users/bigouz/Xroads/.screenshots"

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

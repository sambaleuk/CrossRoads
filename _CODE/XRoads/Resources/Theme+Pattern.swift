import SwiftUI

// MARK: - African Pattern System
// Three geometric traditions mapped to semantic UI functions:
//   • .bogolan  → horizontal rhythms, status strips, dividers
//   • .kubaMaze → ambient depth, empty states, hero backdrops
//   • .ndebele  → active/hover emphasis, premium component surfaces

enum AfricanPattern: String, CaseIterable {
    case bogolan  = "PatternBogolan"
    case kubaMaze = "PatternKuba"
    case ndebele  = "PatternNdebele"

    /// NSImage loaded from the bundled Patterns folder via Bundle.module
    var nsImage: NSImage? {
        guard let url = Bundle.module.url(
            forResource: rawValue,
            withExtension: "svg",
            subdirectory: "Patterns"
        ) else { return nil }
        guard let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: img.size.width * 0.35, height: img.size.height * 0.35)
        return img
    }
}

// MARK: - PatternTile (the actual render primitive)

struct PatternTile: View {
    let pattern: AfricanPattern
    let color: Color
    let opacity: Double

    var body: some View {
        if let nsImage = pattern.nsImage {
            Image(nsImage: nsImage)
                .resizable(resizingMode: .tile)
                .renderingMode(.template)
                .foregroundColor(color.opacity(opacity))
        }
        // If the asset can't load, renders nothing — no crash.
    }
}

// MARK: - View modifier

extension View {
    /// Applies a subtle repeating African geometric pattern behind the view.
    ///
    /// - Parameters:
    ///   - pattern: `.bogolan`, `.kubaMaze`, or `.ndebele`
    ///   - opacity: 0.02–0.05 keeps it subliminal in the dark-tech palette
    ///   - color:   defaults to `Theme.Color.ink` (near-white on dark backgrounds)
    func africanPatternOverlay(
        _ pattern: AfricanPattern,
        opacity: Double = 0.01,
        color: Color = Theme.Color.ink
    ) -> some View {
        self.overlay(
            PatternTile(pattern: pattern, color: color, opacity: opacity)
        )
    }
}

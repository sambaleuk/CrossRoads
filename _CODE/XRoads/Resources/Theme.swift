import SwiftUI

// MARK: - Color hex initializers

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8)  & 0xFF) / 255.0,
            blue:  Double( hex        & 0xFF) / 255.0,
            opacity: alpha
        )
    }

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64
        switch hex.count {
        case 3:
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

// MARK: - Theme namespace (locked visual system v2)

enum Theme {

    // MARK: Color tokens (the entire palette)

    enum Color {
        static let void     = SwiftUI.Color(hex: 0x09090B)
        static let surface  = SwiftUI.Color(hex: 0x131316)
        static let rule     = SwiftUI.Color(hex: 0x1C1C20)
        static let ink      = SwiftUI.Color(hex: 0xE5E5E7)
        static let muted    = SwiftUI.Color(hex: 0x8A8A92)
        static let faint    = SwiftUI.Color(hex: 0x4A4A52)
        static let voltage  = SwiftUI.Color(hex: 0xFFD60A)
    }

    // MARK: Layout primitives

    enum Layout {
        static let radiusFlat: CGFloat    = 0
        static let radiusTactile: CGFloat = 2
        static let ruleWidth: CGFloat     = 0.5

        // Window / panel sizing kept here for app-level use.
        static let sidebarWidth: CGFloat        = 240
        static let inspectorWidth: CGFloat      = 320
        static let minWindowWidth: CGFloat      = 1280
        static let minWindowHeight: CGFloat     = 800
        static let defaultWindowWidth: CGFloat  = 1440
        static let defaultWindowHeight: CGFloat = 900
        static let chatMaxWidth: CGFloat        = 800
        static let processLogsHeight: CGFloat   = 200
    }

    // MARK: Typography

    enum Font {
        static func displayRegular(_ size: CGFloat) -> SwiftUI.Font {
            .custom("InterTight-Regular", size: size)
        }
        static func displayMedium(_ size: CGFloat) -> SwiftUI.Font {
            .custom("InterTight-Medium", size: size)
        }
        static func mono(_ size: CGFloat) -> SwiftUI.Font {
            .custom("JetBrainsMono-Regular", size: size)
        }
    }

    // NOTE: Spec v2 binding shows `enum Type`, but `Theme.Type` in member-access position
    // resolves to Swift's metatype, not a nested enum. Renamed to `TextStyle` to avoid
    // the clash. Constant names preserved.
    enum TextStyle {
        static let heroDisplay  = Font.displayMedium(56)
        static let pageHeading  = Font.displayMedium(28)
        static let sectionHead  = Font.displayMedium(18)
        static let bodyLarge    = Font.displayRegular(16)
        static let body         = Font.displayRegular(14)
        static let smallBody    = Font.displayRegular(12)
        static let labelMono    = Font.mono(11)
        static let tacticalMono = Font.mono(10)
    }

    enum Tracking {
        static let heroDisplay: CGFloat       = -2.24  // 56 × -0.04em
        static let pageHeading: CGFloat       = -0.56  // 28 × -0.02em
        static let sectionHead: CGFloat       = -0.36  // 18 × -0.02em
        static let bodyLarge: CGFloat         = 0
        static let body: CGFloat              = 0
        static let smallBody: CGFloat         = 0
        static let labelMonoCaps: CGFloat     = 0.55   // 11 × +0.05em
        static let tacticalCaps: CGFloat      = 0.80   // 10 × +0.08em
        static let tacticalCapsDense: CGFloat = 1.20   // 10 × +0.12em
    }

    // MARK: Transitional constants (kept compiling the old surface)
    // The audit/refactor passes will reduce each call site to the locked tokens above.

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
    }

    enum Animation {
        static let fast: Double   = 0.1
        static let normal: Double = 0.15
        static let slow: Double   = 0.2
        static let modal: Double  = 0.25
        static let pulse: Double  = 2.0
    }

    enum Component {
        static let headerHeight: CGFloat        = 48
        static let inputBarHeight: CGFloat      = 56
        static let logHeaderHeight: CGFloat     = 36
        static let buttonHeight: CGFloat        = 36
        static let statusBadgeHeight: CGFloat   = 20
        static let statusDotSize: CGFloat       = 8
        static let sessionCardMinHeight: CGFloat = 96

        static let slotCardWidth: CGFloat   = 220
        static let slotCardHeight: CGFloat  = 160
        static let slotHeaderHeight: CGFloat = 36

        static let leftPanelWidth: CGFloat     = 210
        static let rightPanelWidth: CGFloat    = 280
        static let panelHeaderHeight: CGFloat  = 40
        static let sectionHeaderHeight: CGFloat = 20
    }

    enum SlotCard {
        static let background           = SwiftUI.Color(hex: "#14161a")
        static let headerBackground     = SwiftUI.Color(hex: "#1a1d23")
        static let terminalBackground   = SwiftUI.Color(hex: "#0d0f12")
        static let borderInactive       = SwiftUI.Color(hex: "#333840")
    }

    enum Status {
        static func color(for status: String) -> SwiftUI.Color {
            switch status {
            case "empty":                          return Theme.Color.faint
            case "configuring", "ready":           return Theme.Color.muted
            case "starting", "paused":             return Theme.Color.voltage
            case "running":                        return Theme.Color.voltage
            case "completed":                      return Theme.Color.voltage
            case "error":                          return Theme.Color.voltage
            case "needsInput", "waitingForInput":  return Theme.Color.voltage
            default:                               return Theme.Color.faint
            }
        }

        static func backgroundColor(for status: String) -> SwiftUI.Color {
            color(for: status).opacity(0.15)
        }

        static func borderColor(for status: String) -> SwiftUI.Color {
            color(for: status).opacity(0.4)
        }
    }
}

// MARK: - StatusPip (locked component)

struct StatusPip: View {
    enum State { case idle, queued, active, connected, error }

    let state: State
    var animated: Bool = true

    @SwiftUI.State private var pulse = false

    var body: some View {
        Rectangle()
            .fill(fillColor)
            .frame(width: 4, height: 9)
            .opacity(currentOpacity)
            .onAppear {
                guard animated, isLive else { return }
                withAnimation(Motion.pulsePip) { pulse = true }
            }
    }

    private var fillColor: SwiftUI.Color {
        switch state {
        case .idle, .queued: return Theme.Color.faint
        case .active, .error: return Theme.Color.voltage
        case .connected:      return SwiftUI.Color(hex: 0x3FB950) // neon-green — healthy
        }
    }

    private var isLive: Bool {
        switch state {
        case .active, .error, .connected: return true
        case .idle, .queued:              return false
        }
    }

    private var currentOpacity: Double {
        guard isLive else { return 1.0 }
        return pulse ? 0.4 : 1.0
    }
}

// MARK: - Deprecated color shims
// Mapped to closest locked token. Each call site is migration work.

extension Color {
    @available(*, deprecated, message: "Use Theme.Color.void")
    static var bgApp: Color { Theme.Color.void }

    @available(*, deprecated, message: "Use Theme.Color.void")
    static var bgCanvas: Color { Theme.Color.void }

    @available(*, deprecated, message: "Use Theme.Color.surface")
    static var bgSurface: Color { Theme.Color.surface }

    @available(*, deprecated, message: "Use Theme.Color.surface")
    static var bgElevated: Color { Theme.Color.surface }

    @available(*, deprecated, message: "Use Theme.Color.ink")
    static var textPrimary: Color { Theme.Color.ink }

    @available(*, deprecated, message: "Use Theme.Color.muted")
    static var textSecondary: Color { Theme.Color.muted }

    @available(*, deprecated, message: "Use Theme.Color.faint")
    static var textTertiary: Color { Theme.Color.faint }

    @available(*, deprecated, message: "Use Theme.Color.void")
    static var textInverse: Color { Theme.Color.void }

    @available(*, deprecated, message: "Use Theme.Color.rule")
    static var borderDefault: Color { Theme.Color.rule }

    @available(*, deprecated, message: "Use Theme.Color.rule")
    static var borderMuted: Color { Theme.Color.rule }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var borderAccent: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var accentPrimary: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var accentPrimaryHover: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.voltage; state distinguished by copy, not hue")
    static var statusSuccess: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var statusWarning: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var statusError: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.muted")
    static var statusInfo: Color { Theme.Color.muted }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var terminalGreen: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.muted")
    static var terminalCyan: Color { Theme.Color.muted }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var terminalYellow: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var terminalRed: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var terminalMagenta: Color { Theme.Color.voltage }

    // Glow shims: spec forbids halos, but `.opacity(0.15)` fills are translucent backgrounds,
    // not glows. Audit replaces these where they back a `.shadow()` or imply bloom.
    @available(*, deprecated, message: "Glow forbidden; remove or replace with surface")
    static var accentPrimaryGlow: Color { Theme.Color.voltage.opacity(0.15) }

    @available(*, deprecated, message: "Glow forbidden; remove or replace with surface")
    static var statusSuccessGlow: Color { Theme.Color.voltage.opacity(0.15) }

    @available(*, deprecated, message: "Glow forbidden; remove or replace with surface")
    static var statusWarningGlow: Color { Theme.Color.voltage.opacity(0.15) }

    @available(*, deprecated, message: "Glow forbidden; remove or replace with surface")
    static var statusErrorGlow: Color { Theme.Color.voltage.opacity(0.15) }

    @available(*, deprecated, message: "Glow forbidden; remove or replace with surface")
    static var statusInfoGlow: Color { Theme.Color.voltage.opacity(0.15) }

    // Creature/orchestrator state hues: collapse to voltage/muted/faint per state semantics.
    @available(*, deprecated, message: "Use Theme.Color.muted")
    static var creatureIdle: Color { Theme.Color.muted }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var creaturePlanning: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var creatureDistributing: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var creatureMonitoring: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var creatureSynthesizing: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var creatureCelebrating: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var creatureConcerned: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.faint")
    static var creatureSleeping: Color { Theme.Color.faint }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var slotBorderClaude: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var slotBorderGemini: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var slotBorderCodex: Color { Theme.Color.voltage }

    @available(*, deprecated, message: "Use Theme.Color.faint")
    static var slotBorderEmpty: Color { Theme.Color.faint }

    @available(*, deprecated, message: "Use Theme.Color.void")
    static var dashboardPanelBg: Color { Theme.Color.void }

    @available(*, deprecated, message: "Use Theme.Color.rule")
    static var connectionLineDefault: Color { Theme.Color.rule }

    @available(*, deprecated, message: "Use Theme.Color.voltage")
    static var connectionLineActive: Color { Theme.Color.voltage }
}

// MARK: - Deprecated typography shims
// Bridge the existing `.font(.body14)` etc. surface to the locked Theme.Type scale.

extension Font {
    @available(*, deprecated, message: "Use Theme.Font.mono(_:) or Theme.TextStyle.*")
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    @available(*, deprecated, message: "Use Theme.Font.displayRegular(_:) or Theme.TextStyle.*")
    static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    @available(*, deprecated, message: "Use Theme.TextStyle.pageHeading")
    static var display: Font { Theme.TextStyle.pageHeading }

    @available(*, deprecated, message: "Use Theme.TextStyle.sectionHead")
    static var h1: Font { Theme.TextStyle.sectionHead }

    @available(*, deprecated, message: "Use Theme.TextStyle.bodyLarge")
    static var h2: Font { Theme.TextStyle.bodyLarge }

    @available(*, deprecated, message: "Use Theme.TextStyle.body")
    static var h3: Font { Theme.TextStyle.body }

    @available(*, deprecated, message: "Use Theme.TextStyle.body")
    static var body14: Font { Theme.TextStyle.body }

    @available(*, deprecated, message: "Use Theme.TextStyle.smallBody")
    static var small: Font { Theme.TextStyle.smallBody }

    @available(*, deprecated, message: "Use Theme.TextStyle.labelMono")
    static var xs: Font { Theme.TextStyle.labelMono }

    @available(*, deprecated, message: "Use Theme.TextStyle.body")
    static var terminal: Font { Theme.TextStyle.body }

    @available(*, deprecated, message: "Use Theme.TextStyle.body")
    static var code: Font { Theme.TextStyle.body }
}

// MARK: - Deprecated view modifiers
// `cardStyle` etc. apply non-conforming radius and shadow. Audit removes or replaces.

extension View {
    @available(*, deprecated, message: "Apply Theme.Color.void directly")
    func darkProBackground(_ color: Color = Theme.Color.void) -> some View {
        self.background(color)
    }

    @available(*, deprecated, message: "Cards forbidden: 0.5pt rule border, 0pt radius, no shadow")
    func cardStyle() -> some View {
        self
            .background(Theme.Color.surface)
            .overlay(
                Rectangle()
                    .stroke(Theme.Color.rule, lineWidth: Theme.Layout.ruleWidth)
            )
    }

    @available(*, deprecated, message: "Cards forbidden: 0.5pt rule border, 0pt radius, no shadow")
    func elevatedCardStyle() -> some View {
        self
            .background(Theme.Color.surface)
            .overlay(
                Rectangle()
                    .stroke(Theme.Color.rule, lineWidth: Theme.Layout.ruleWidth)
            )
    }

    @available(*, deprecated, message: "Use surface + 0.5pt rule border directly")
    func terminalStyle() -> some View {
        self
            .background(Theme.Color.void)
            .overlay(
                Rectangle()
                    .stroke(Theme.Color.rule, lineWidth: Theme.Layout.ruleWidth)
            )
    }
}

// MARK: - Preview

#if DEBUG
struct Theme_Previews: PreviewProvider {
    static var previews: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 8) {
                colorSwatch(Theme.Color.void, label: "void")
                colorSwatch(Theme.Color.surface, label: "surface")
                colorSwatch(Theme.Color.rule, label: "rule")
                colorSwatch(Theme.Color.ink, label: "ink")
                colorSwatch(Theme.Color.muted, label: "muted")
                colorSwatch(Theme.Color.faint, label: "faint")
                colorSwatch(Theme.Color.voltage, label: "voltage")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("hero display")
                    .font(Theme.TextStyle.heroDisplay)
                    .tracking(Theme.Tracking.heroDisplay)
                    .foregroundStyle(Theme.Color.ink)
                Text("page heading")
                    .font(Theme.TextStyle.pageHeading)
                    .tracking(Theme.Tracking.pageHeading)
                    .foregroundStyle(Theme.Color.ink)
                Text("section head")
                    .font(Theme.TextStyle.sectionHead)
                    .tracking(Theme.Tracking.sectionHead)
                    .foregroundStyle(Theme.Color.ink)
                Text("body large")
                    .font(Theme.TextStyle.bodyLarge)
                    .foregroundStyle(Theme.Color.ink)
                Text("body")
                    .font(Theme.TextStyle.body)
                    .foregroundStyle(Theme.Color.ink)
                Text("LABEL MONO")
                    .font(Theme.TextStyle.labelMono)
                    .tracking(Theme.Tracking.labelMonoCaps)
                    .foregroundStyle(Theme.Color.muted)
                Text("AGENTS 0/6 · GATES 6/6 · DRIFT NONE")
                    .font(Theme.TextStyle.tacticalMono)
                    .tracking(Theme.Tracking.tacticalCaps)
                    .foregroundStyle(Theme.Color.voltage)
            }

            HStack(spacing: 24) {
                pipRow("idle", state: .idle)
                pipRow("queued", state: .queued)
                pipRow("exec", state: .active)
                pipRow("error", state: .error)
            }
        }
        .padding(32)
        .background(Theme.Color.void)
    }

    private static func colorSwatch(_ color: SwiftUI.Color, label: String) -> some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(color)
                .frame(width: 60, height: 40)
                .overlay(Rectangle().stroke(Theme.Color.rule, lineWidth: Theme.Layout.ruleWidth))
            Text(label)
                .font(Theme.TextStyle.tacticalMono)
                .foregroundStyle(Theme.Color.faint)
        }
    }

    private static func pipRow(_ label: String, state: StatusPip.State) -> some View {
        HStack(spacing: 8) {
            StatusPip(state: state)
            Text(label)
                .font(Theme.TextStyle.labelMono)
                .foregroundStyle(state == .active || state == .error ? Theme.Color.ink : Theme.Color.muted)
        }
    }
}
#endif

import SwiftUI

// MARK: - Motion library (locked visual system v2)
// Named animation constants for state-driven motion.
// Never inline durations or easings in views; reference these.

enum Motion {

    // Pulse for active strokes (e.g. brand mark, status pips with attention).
    static let pulseStroke = Animation
        .easeInOut(duration: 3.2)
        .repeatForever(autoreverses: true)

    // Slower breathing for ambient elements (center dots, idle markers).
    static let breatheDot = Animation
        .easeInOut(duration: 2.4)
        .repeatForever(autoreverses: true)

    // Pip pulse for live status indicators.
    static let pulsePip = Animation
        .easeInOut(duration: 2.0)
        .repeatForever(autoreverses: true)

    // Cursor blink. Linear so the toggle reads as discrete on/off.
    static let cursorBlink = Animation
        .linear(duration: 1.1)
        .repeatForever(autoreverses: true)

    // Progress bar shimmer (alive even at 0%).
    static let shimmerBar = Animation
        .easeInOut(duration: 2.6)
        .repeatForever(autoreverses: true)

    // Scanline traveling vertically through a content area.
    static let scanlineTravel = Animation
        .linear(duration: 6.0)
        .repeatForever(autoreverses: false)

    // HUD bracket frame pulse.
    static let bracketPulse = Animation
        .easeInOut(duration: 4.0)
        .repeatForever(autoreverses: true)

    // Diagnostic readout value tick.
    static let diagTick = Animation
        .easeInOut(duration: 3.0)
        .repeatForever(autoreverses: true)

    // Chevron flow inward (data converging on orchestrator).
    static let chevronFlow = Animation
        .easeInOut(duration: 1.6)
        .repeatForever(autoreverses: true)

    // Radar ping (broadcast). Outward expansion only, no reverse.
    static let radarPing = Animation
        .easeOut(duration: 3.6)
        .repeatForever(autoreverses: false)

    // Wordmark glitch. Sparse jump-cut, every 8s.
    static let glitch = Animation
        .linear(duration: 8.0)
        .repeatForever(autoreverses: false)

    // Tactical button hover transition. Spec: under 120ms, linear.
    static let tacticalHover = Animation.linear(duration: 0.12)

    // Stagger helper. Apply a phase offset (in seconds) to a related-element animation
    // so a series of N elements creates rhythm rather than synchrony.
    static func staggered(_ base: Animation, delay: Double) -> Animation {
        base.delay(delay)
    }
}

// MARK: - HUD bracket frame

struct BracketCorner: Shape {
    enum Corner: Hashable { case topLeft, topRight, bottomLeft, bottomRight }

    let corner: Corner
    var armLength: CGFloat = 24

    func path(in rect: CGRect) -> Path {
        var p = Path()
        switch corner {
        case .topLeft:
            p.move(to: CGPoint(x: rect.minX, y: rect.minY + armLength))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.minX + armLength, y: rect.minY))
        case .topRight:
            p.move(to: CGPoint(x: rect.maxX - armLength, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + armLength))
        case .bottomLeft:
            p.move(to: CGPoint(x: rect.minX, y: rect.maxY - armLength))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX + armLength, y: rect.maxY))
        case .bottomRight:
            p.move(to: CGPoint(x: rect.maxX - armLength, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - armLength))
        }
        return p
    }
}

struct HUDFrame: View {
    var armLength: CGFloat = 24
    var stroke: CGFloat = 1.5
    var animated: Bool = true

    @State private var pulse = false

    var body: some View {
        ZStack {
            ForEach([BracketCorner.Corner.topLeft,
                     .topRight,
                     .bottomLeft,
                     .bottomRight], id: \.self) { corner in
                BracketCorner(corner: corner, armLength: armLength)
                    .stroke(Theme.Color.voltage, lineWidth: stroke)
            }
        }
        .opacity(pulse ? 0.95 : 0.55)
        .onAppear {
            guard animated else { return }
            withAnimation(Motion.bracketPulse) { pulse = true }
        }
    }
}

// MARK: - Convenience modifiers

extension View {
    /// Drive an opacity animation from a `@State` toggle. Call inside `.onAppear`:
    /// `withAnimation(Motion.pulsePip) { liveState.toggle() }`.
    /// This modifier is documentation-only; views own their own state to avoid
    /// hidden modifier state that can desync across redraws.
    func liveOpacity(_ active: Bool, hi: Double = 1.0, lo: Double = 0.4) -> some View {
        self.opacity(active ? lo : hi)
    }
}

#if DEBUG
struct Motion_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Theme.Color.void.ignoresSafeArea()
            VStack(spacing: 32) {
                HUDFrame()
                    .frame(width: 320, height: 200)
                    .overlay(
                        Text("SYSTEM IDLE")
                            .font(Theme.TextStyle.labelMono)
                            .tracking(Theme.Tracking.tacticalCapsDense)
                            .foregroundStyle(Theme.Color.voltage)
                    )

                HStack(spacing: 12) {
                    StatusPip(state: .idle)
                    StatusPip(state: .queued)
                    StatusPip(state: .active)
                    StatusPip(state: .error)
                }
            }
        }
        .frame(width: 480, height: 360)
    }
}
#endif

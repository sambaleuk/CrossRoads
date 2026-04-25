import SwiftUI

/// Idle-state hero region. Renders the v2 spec section 8 pattern when no
/// orchestration is running: HUD bracket frame, coordinate callouts, vertical
/// scanline, brand mark placeholder, SYSTEM IDLE status, diagnostic readout,
/// and the `what are we shipping?` prompt.
struct HeroIdleState: View {

    /// Test-only seed for the scanline progress (0...1). The running app
    /// drives this via `Motion.scanlineTravel`; ImageRenderer does not fire
    /// `.onAppear`, so a snapshot needs an explicit non-zero seed for the
    /// scanline to be visible.
    var snapshotScanlineSeed: CGFloat? = nil

    @State private var scanlineProgress: CGFloat = 0
    @State private var diagAgents = false
    @State private var diagGates = false
    @State private var diagDrift = false
    @State private var promptCursorOn = true

    private let framePadding: CGFloat = 48
    private let calloutInset: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.Color.void
                    .africanPatternOverlay(.kubaMaze)

                CoordinateCallouts(
                    width: geo.size.width,
                    height: geo.size.height,
                    inset: calloutInset
                )

                HUDFrame()
                    .padding(framePadding)

                let scanY = (snapshotScanlineSeed ?? scanlineProgress)
                    * (geo.size.height - framePadding * 2)
                let markGap: CGFloat = 140  // brand mark width + breathing room
                let halfCanvas = max(0, geo.size.width - framePadding * 2)
                let segmentW  = max(0, (halfCanvas - markGap) / 2)

                // Left scanline segment (gaps around brand mark)
                Rectangle()
                    .fill(Theme.Color.voltage.opacity(0.15))
                    .frame(width: segmentW, height: 1)
                    .position(
                        x: framePadding + segmentW / 2,
                        y: framePadding + scanY
                    )

                // Right scanline segment
                Rectangle()
                    .fill(Theme.Color.voltage.opacity(0.15))
                    .frame(width: segmentW, height: 1)
                    .position(
                        x: geo.size.width - framePadding - segmentW / 2,
                        y: framePadding + scanY
                    )

                VStack(spacing: 28) {
                    BrandMarkPlaceholder(size: 120)

                    Text("SYSTEM IDLE")
                        .font(Theme.TextStyle.labelMono)
                        .tracking(Theme.Tracking.tacticalCapsDense)
                        .foregroundStyle(Theme.Color.muted)

                    DiagnosticReadout(
                        agentsLive: diagAgents,
                        gatesLive: diagGates,
                        driftLive: diagDrift
                    )

                    HStack(spacing: 1) {
                        Text("what are we shipping?")
                            .font(Theme.Font.mono(12))
                            .foregroundStyle(Theme.Color.faint)
                        Rectangle()
                            .fill(Theme.Color.voltage)
                            .frame(width: 1.5, height: 13)
                            .opacity(promptCursorOn ? 1 : 0)
                    }
                    .padding(.top, 8)
                }
            }
            .onAppear {
                guard snapshotScanlineSeed == nil else { return }

                withAnimation(Motion.scanlineTravel) {
                    scanlineProgress = 1.0
                }
                withAnimation(Motion.diagTick) {
                    diagAgents.toggle()
                }
                withAnimation(Motion.diagTick.delay(1.0)) {
                    diagGates.toggle()
                }
                withAnimation(Motion.diagTick.delay(2.0)) {
                    diagDrift.toggle()
                }
                withAnimation(Motion.cursorBlink) {
                    promptCursorOn = false
                }
            }
        }
    }
}

// MARK: - Diagnostic readout

private struct DiagnosticReadout: View {
    let agentsLive: Bool
    let gatesLive: Bool
    let driftLive: Bool

    var body: some View {
        HStack(spacing: 10) {
            DiagPair(label: "AGENTS", value: "0/6", live: agentsLive)
            DiagSeparator()
            DiagPair(label: "GATES", value: "6/6", live: gatesLive)
            DiagSeparator()
            DiagPair(label: "DRIFT", value: "NONE", live: driftLive)
        }
    }
}

private struct DiagPair: View {
    let label: String
    let value: String
    let live: Bool

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(Theme.TextStyle.tacticalMono)
                .tracking(Theme.Tracking.tacticalCaps)
                .foregroundStyle(Theme.Color.faint)
            Text(value)
                .font(Theme.TextStyle.tacticalMono)
                .tracking(Theme.Tracking.tacticalCaps)
                .foregroundStyle(live ? Theme.Color.voltage : Theme.Color.muted)
        }
    }
}

private struct DiagSeparator: View {
    var body: some View {
        Text("·")
            .font(Theme.TextStyle.tacticalMono)
            .foregroundStyle(Theme.Color.faint)
    }
}

// MARK: - Coordinate callouts

private struct CoordinateCallouts: View {
    let width: CGFloat
    let height: CGFloat
    let inset: CGFloat

    var body: some View {
        ZStack {
            calloutText("X:0  Y:0")
                .position(x: inset + 32, y: inset + 6)
            calloutText("\(Int(width))×\(Int(height))")
                .position(x: width - inset - 40, y: inset + 6)
            calloutText("T+00:00:00")
                .position(x: inset + 36, y: height - inset - 6)
            calloutText("Q:0")
                .position(x: width - inset - 14, y: height - inset - 6)
        }
    }

    private func calloutText(_ s: String) -> some View {
        Text(s)
            .font(Theme.Font.mono(9))
            .tracking(Theme.Tracking.tacticalCaps)
            .foregroundStyle(Theme.Color.faint)
    }
}

#if DEBUG
struct HeroIdleState_Previews: PreviewProvider {
    static var previews: some View {
        HeroIdleState(snapshotScanlineSeed: 0.42)
            .frame(width: 1000, height: 640)
    }
}
#endif

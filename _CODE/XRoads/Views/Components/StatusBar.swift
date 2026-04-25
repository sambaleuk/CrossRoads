import SwiftUI

/// Top-of-column status strip per v2 spec section 5/8. Carries section state
/// (pip plus label), free-text status, a progress bar with shimmer indicator,
/// percentage, and an agent counter. Sits at 30pt with surface background and
/// a 0.5pt rule bottom border.
struct StatusBar: View {

    var label: String = "READY"
    var status: String = "standing by"
    var progress: Double = 0
    var agentCount: Int = 0
    var agentMax: Int = 6

    /// Test-only override.
    var snapshotShimmerOn: Bool? = nil

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                StatusPip(state: .active)
                Text(label)
                    .font(Theme.Font.mono(10))
                    .tracking(Theme.Tracking.tacticalCaps)
                    .foregroundStyle(Theme.Color.ink)
            }

            Text(status)
                .font(Theme.Font.mono(10))
                .foregroundStyle(Theme.Color.faint)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            ProgressShimmer(
                progress: progress,
                snapshotShimmerOn: snapshotShimmerOn
            )

            Text("\(Int(progress * 100))%")
                .font(Theme.Font.mono(10))
                .tracking(Theme.Tracking.tacticalCaps)
                .foregroundStyle(Theme.Color.faint)
                .frame(width: 32, alignment: .trailing)
                .monospacedDigit()

            Text("\(agentCount)/\(agentMax) agents")
                .font(Theme.Font.mono(10))
                .tracking(Theme.Tracking.tacticalCaps)
                .foregroundStyle(Theme.Color.faint)
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(Theme.Color.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Color.rule)
                .frame(height: Theme.Layout.ruleWidth)
        }
    }
}

// MARK: - ProgressShimmer

private struct ProgressShimmer: View {
    let progress: Double
    let snapshotShimmerOn: Bool?

    @State private var shimmerOn = true

    private let railWidth: CGFloat = 80
    private let railHeight: CGFloat = 4
    private let indicatorWidth: CGFloat = 2

    var body: some View {
        let clamped = min(max(progress, 0), 1)
        let fillWidth = railWidth * clamped
        let indicatorX = max(0, fillWidth - indicatorWidth)

        ZStack(alignment: .leading) {
            Rectangle()
                .fill(Theme.Color.rule)
                .frame(width: railWidth, height: railHeight)

            if clamped > 0 {
                Rectangle()
                    .fill(Theme.Color.voltage)
                    .frame(width: fillWidth, height: railHeight)
            }

            Rectangle()
                .fill(Theme.Color.voltage)
                .frame(width: indicatorWidth, height: railHeight)
                .opacity((snapshotShimmerOn ?? shimmerOn) ? 1.0 : 0.4)
                .offset(x: indicatorX)
        }
        .frame(width: railWidth, height: railHeight)
        .onAppear {
            guard snapshotShimmerOn == nil else { return }
            withAnimation(Motion.shimmerBar) {
                shimmerOn = false
            }
        }
    }
}

#if DEBUG
struct StatusBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            StatusBar(snapshotShimmerOn: true)
            StatusBar(label: "EXEC", status: "compiling layer 02 / 04",
                      progress: 0.42, agentCount: 3, agentMax: 6,
                      snapshotShimmerOn: true)
            Theme.Color.void.frame(height: 240)
        }
        .frame(width: 800)
    }
}
#endif

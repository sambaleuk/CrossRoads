import SwiftUI

/// Window-bottom status strip per v2 spec section 8. 26pt tall, surface
/// background, 0.5pt rule top border. Section name in mono caps left, status
/// counter on the right with a 6pt dot in voltage (healthy) or faint (dormant).
struct BottomBar: View {

    var sectionName: String = "ACTIVE PROJECT"
    var counterCount: Int = 4
    var counterTotal: Int = 4
    var allHealthy: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Text(sectionName)
                .font(Theme.Font.mono(10))
                .tracking(Theme.Tracking.tacticalCaps)
                .foregroundStyle(Theme.Color.faint)

            Spacer()

            HStack(spacing: 8) {
                Text("\(counterCount)/\(counterTotal)")
                    .font(Theme.Font.mono(10))
                    .tracking(Theme.Tracking.tacticalCaps)
                    .foregroundStyle(allHealthy ? Theme.Color.ink : Theme.Color.muted)
                    .monospacedDigit()

                Circle()
                    .fill(allHealthy ? Theme.Color.voltage : Theme.Color.faint)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 26)
        .background(Theme.Color.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Color.rule)
                .frame(height: Theme.Layout.ruleWidth)
        }
    }
}

#if DEBUG
struct BottomBar_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 0) {
            Theme.Color.void.frame(height: 200)
            BottomBar()
            BottomBar(sectionName: "LOOP SCRIPTS", counterCount: 2, counterTotal: 4, allHealthy: false)
        }
        .frame(width: 1000)
    }
}
#endif

import SwiftUI

/// Inert placeholder for the XRoads brand mark. The final mark is being adjusted
/// by art direction; until it ships, every brand-mark site renders this typed sentinel.
/// When the mark lands, swap the body of this view and every callsite updates.
struct BrandMarkPlaceholder: View {
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            // Container
            Rectangle()
                .fill(Theme.Color.void)
                .frame(width: size, height: size)
                .overlay(
                    Rectangle()
                        .stroke(Theme.Color.voltage, lineWidth: Theme.Layout.ruleWidth)
                )

            // Crosshair reticle — intentional targeting glyph
            let armLen = size * 0.32
            let hairWeight: CGFloat = Theme.Layout.ruleWidth
            let armOpacity = size >= 80 ? 0.60 : 0.45

            // Horizontal hair
            Rectangle()
                .fill(Theme.Color.voltage.opacity(armOpacity))
                .frame(width: armLen, height: hairWeight)

            // Vertical hair
            Rectangle()
                .fill(Theme.Color.voltage.opacity(armOpacity))
                .frame(width: hairWeight, height: armLen)

            // Center dot
            Circle()
                .fill(Theme.Color.voltage.opacity(0.7))
                .frame(width: max(2, size * 0.04), height: max(2, size * 0.04))
        }
        .frame(width: size, height: size)
    }
}

#if DEBUG
struct BrandMarkPlaceholder_Previews: PreviewProvider {
    static var previews: some View {
        HStack(spacing: 24) {
            BrandMarkPlaceholder(size: 18)
            BrandMarkPlaceholder(size: 40)
            BrandMarkPlaceholder(size: 120)
        }
        .padding(40)
        .background(Theme.Color.void)
    }
}
#endif

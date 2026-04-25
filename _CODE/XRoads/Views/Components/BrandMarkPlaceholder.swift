import SwiftUI

/// Inert placeholder for the XRoads brand mark. The final mark is being adjusted
/// by art direction; until it ships, every brand-mark site renders this typed sentinel.
/// When the mark lands, swap the body of this view and every callsite updates.
struct BrandMarkPlaceholder: View {
    var size: CGFloat = 40

    var body: some View {
        Rectangle()
            .fill(Theme.Color.void)
            .frame(width: size, height: size)
            .overlay(
                Rectangle()
                    .stroke(Theme.Color.voltage, lineWidth: Theme.Layout.ruleWidth)
            )
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

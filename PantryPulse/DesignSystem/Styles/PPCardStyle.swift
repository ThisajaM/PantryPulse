import SwiftUI

struct PPCardStyle: ViewModifier {
    var padding: CGFloat = PPSpacing.md

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(PPColors.surface, in: RoundedRectangle(cornerRadius: PPCornerRadius.card, style: .continuous))
            .shadow(color: PPColors.shadow.opacity(PPMetrics.cardShadowOpacity),
                    radius: PPMetrics.cardShadowRadius, y: PPMetrics.cardShadowOffset)
    }
}

extension View {
    func ppCard(padding: CGFloat = PPSpacing.md) -> some View {
        modifier(PPCardStyle(padding: padding))
    }
}

import SwiftUI

struct PPButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary }
    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        let shape = dynamicTypeSize.isAccessibilitySize
            ? AnyShape(RoundedRectangle(cornerRadius: PPCornerRadius.hero, style: .continuous))
            : AnyShape(Capsule())
        configuration.label
            .font(PPTypography.button)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? PPSpacing.md : PPSpacing.xl)
            .padding(.vertical, PPSpacing.sm)
            .frame(maxWidth: .infinity)
            .frame(minHeight: kind == .primary ? PPMetrics.primaryButtonHeight : PPMetrics.secondaryButtonHeight)
            .foregroundStyle(kind == .primary ? PPColors.onPrimary : PPColors.text)
            .background(kind == .primary ? PPColors.primary : PPColors.surface, in: shape)
            .contentShape(shape)
            .shadow(color: PPColors.shadow.opacity(PPMetrics.cardShadowOpacity),
                    radius: PPMetrics.cardShadowRadius, y: PPMetrics.cardShadowOffset)
            .opacity(isEnabled ? (configuration.isPressed ? PPMetrics.pressedOpacity : 1) : PPMetrics.disabledOpacity)
    }
}

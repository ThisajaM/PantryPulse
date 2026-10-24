import SwiftUI

/// No managed objects or expiry calculations. Images and formatted labels come from the caller.
struct FoodCard: View {
    let title: String
    var subtitle: String? = nil
    var image: Image? = nil
    var imageAspectRatio: CGFloat = 1
    var expiry: StatusBadge? = nil
    var status: StatusBadge? = nil
    var action: PPAction? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            artwork
                .overlay(alignment: .topLeading) {
                    if !dynamicTypeSize.isAccessibilitySize, let expiry {
                        expiry.padding(PPSpacing.xs)
                    }
                }
            if dynamicTypeSize.isAccessibilitySize, let expiry { expiry }
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                Text(title).font(PPTypography.cardTitle).foregroundStyle(PPColors.text)
                if let subtitle {
                    Text(subtitle).font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PPSpacing.xs) {
                    status
                    Spacer(minLength: 0)
                    actionButton
                }
                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    status
                    actionButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppCard(padding: PPSpacing.sm)
        .accessibilityElement(children: .contain)
    }

    private var artwork: some View {
        PPColors.mutedSurface
            .aspectRatio(imageAspectRatio, contentMode: .fit)
            .overlay {
                if let image {
                    image.resizable().scaledToFill()
                } else {
                    Image(systemName: "carrot")
                        .font(.largeTitle)
                        .foregroundStyle(PPColors.secondaryText)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: PPCornerRadius.image, style: .continuous))
            .accessibilityHidden(true) // The adjacent food name supplies the accessible description.
    }

    @ViewBuilder private var actionButton: some View {
        if let action {
            Button(action: action.action) {
                PPActionLabel(title: action.title, systemImage: action.systemImage)
                    .font(PPTypography.caption)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minWidth: PPMetrics.minimumTapTarget, minHeight: PPMetrics.minimumTapTarget)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(PPColors.actionText)
            .accessibilityLabel("\(action.title), \(title)")
        }
    }
}

import SwiftUI

struct EmptyStateView<Artwork: View>: View {
    let title: String
    let message: String
    var primaryAction: PPAction? = nil
    var secondaryAction: PPAction? = nil
    @ViewBuilder let artwork: () -> Artwork
    @ScaledMetric(relativeTo: .title) private var symbolSize = PPMetrics.emptyStateSymbol

    init(title: String, message: String, primaryAction: PPAction? = nil,
         secondaryAction: PPAction? = nil, @ViewBuilder artwork: @escaping () -> Artwork) {
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.artwork = artwork
    }

    var body: some View {
        VStack(spacing: PPSpacing.xl) {
            artwork()
                .font(.system(size: symbolSize))
                .foregroundStyle(PPColors.actionText)
                .accessibilityHidden(true)
            VStack(spacing: PPSpacing.xs) {
                Text(title).font(PPTypography.screenTitle).foregroundStyle(PPColors.text)
                    .accessibilityAddTraits(.isHeader)
                Text(message).font(PPTypography.body).foregroundStyle(PPColors.secondaryText)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            if primaryAction != nil || secondaryAction != nil {
                VStack(spacing: PPSpacing.sm) {
                    if let primaryAction {
                        PrimaryButton(title: primaryAction.title, systemImage: primaryAction.systemImage, action: primaryAction.action)
                    }
                    if let secondaryAction {
                        SecondaryButton(title: secondaryAction.title, systemImage: secondaryAction.systemImage, action: secondaryAction.action)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, PPSpacing.xl)
    }
}

extension EmptyStateView where Artwork == Image {
    init(title: String, message: String, systemImage: String,
         primaryAction: PPAction? = nil, secondaryAction: PPAction? = nil) {
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
        self.artwork = { Image(systemName: systemImage) }
    }
}

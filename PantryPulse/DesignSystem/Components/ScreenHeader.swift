import SwiftUI

/// In-content editorial heading. Keep navigation/back buttons in NavigationStack.toolbars.
struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil
    var badge: StatusBadge? = nil
    var action: PPAction? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PPSpacing.sm))
            : AnyLayout(HStackLayout(alignment: .center, spacing: PPSpacing.sm))
        layout {
            VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                if let subtitle {
                    Text(subtitle).font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PPSpacing.xs) { heading; badge }
                    VStack(alignment: .leading, spacing: PPSpacing.xs) { heading; badge }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action: action.action) {
                    PPActionLabel(title: action.title, systemImage: action.systemImage)
                        .font(PPTypography.caption)
                        .frame(minWidth: PPMetrics.minimumTapTarget, minHeight: PPMetrics.minimumTapTarget)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(PPColors.actionText)
            }
        }
    }

    private var heading: some View {
        Text(title).font(PPTypography.screenTitle).foregroundStyle(PPColors.text)
            .accessibilityAddTraits(.isHeader)
    }
}

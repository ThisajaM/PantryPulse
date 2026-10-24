import SwiftUI

struct SectionHeader: View {
    let title: String
    var badge: StatusBadge? = nil
    var action: PPAction? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: PPSpacing.xs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: PPSpacing.xs))
        layout {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: PPSpacing.xs) { heading; badge }
                VStack(alignment: .leading, spacing: PPSpacing.xxs) { heading; badge }
            }
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
        Text(title).font(PPTypography.sectionTitle).foregroundStyle(PPColors.text)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

import SwiftUI

/// Pure presentation: the parent owns the task and decides when to show this view.
struct LoadingStateView: View {
    var title: String = "Loading…"
    var message: String? = nil

    var body: some View {
        VStack(spacing: PPSpacing.sm) {
            ProgressView().controlSize(.large).tint(PPColors.actionText).accessibilityHidden(true)
            Text(title).font(PPTypography.sectionTitle).foregroundStyle(PPColors.text)
            if let message {
                Text(message).font(PPTypography.body).foregroundStyle(PPColors.secondaryText)
            }
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .padding(.vertical, PPSpacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text("In progress"))
    }
}

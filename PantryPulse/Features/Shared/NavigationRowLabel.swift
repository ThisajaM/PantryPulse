import SwiftUI

/// Presentation only; the app composition root supplies navigation actions.
struct NavigationRowLabel: View {
    let title: String
    var systemImage: String? = nil

    var body: some View {
        HStack {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
            Spacer(minLength: PPSpacing.xs)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .font(PPTypography.body)
        .padding(.vertical, PPSpacing.xxs)
        .contentShape(Rectangle())
    }
}

import SwiftUI

/// An honest destination for a capability that has no implementation yet.
struct LaterPhaseView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ScrollView {
            ContentUnavailableView {
                Label(title, systemImage: systemImage)
            } description: {
                VStack(spacing: PPSpacing.xs) {
                    Text("Coming in a later phase")
                        .font(PPTypography.cardTitle)
                        .foregroundStyle(PPColors.text)
                    Text(message)
                        .font(PPTypography.body)
                }
            }
            .padding(.vertical, PPSpacing.xxl)
        }
        .background(PPColors.background)
        .navigationTitle(title)
    }
}

import SwiftUI

struct EmptyPantryView: View {
    let onAddFood: () -> Void
    let onScan: () -> Void
    var body: some View {
        VStack(spacing: PPSpacing.md) {
            Text("Your pantry is ready!").font(PPTypography.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Text("Start adding your food and keep everything fresh, organized, and easy to find.")
                .font(PPTypography.body).foregroundStyle(PPColors.secondaryText)
            PrimaryButton(title: "Add Your First Food", systemImage: "plus", action: onAddFood)
            Text("Scan, photograph, or enter food manually.")
                .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, PPSpacing.md)
    }
}

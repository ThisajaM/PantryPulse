import SwiftUI

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading = false
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: PPSpacing.xs))
                : AnyLayout(HStackLayout(spacing: PPSpacing.xs))
            layout {
                if isLoading {
                    ProgressView().tint(PPColors.onPrimary).accessibilityHidden(true)
                }
                PPActionLabel(title: title, systemImage: isLoading ? nil : systemImage, stacksAtAccessibilitySizes: true)
            }
        }
        .buttonStyle(PPButtonStyle(kind: .primary))
        .disabled(isLoading)
        .accessibilityValue(isLoading ? Text("Loading") : Text(""))
    }
}

import SwiftUI

/// Presentation-only action metadata. Callers own side effects and navigation.
struct PPAction {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void
}

struct PPActionLabel: View {
    let title: String
    let systemImage: String?
    var stacksAtAccessibilitySizes = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = stacksAtAccessibilitySizes && dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: PPSpacing.xs))
            : AnyLayout(HStackLayout(spacing: PPSpacing.xs))
        layout {
            if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
    }
}

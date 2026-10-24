#if DEBUG
import SwiftUI

/// Interactive visual fixtures only. Never referenced by the running app's composition root.
struct DesignSystemPreviewContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var interactionCount = 0

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.xl) {
            ScreenHeader(title: "Your Pantry", subtitle: "Good morning,",
                         action: PPAction(title: "Filter", systemImage: "line.3.horizontal.decrease") { interactionCount += 1 })

            SectionHeader(title: "Buttons")
            PrimaryButton(title: "Add Food", systemImage: "plus.circle.fill") { interactionCount += 1 }
            SecondaryButton(title: "Scan with AI", systemImage: "sparkles") { interactionCount += 1 }
            PrimaryButton(title: "Adding food", isLoading: true) { interactionCount += 1 }
            SecondaryButton(title: "Unavailable action") { interactionCount += 1 }.disabled(true)

            SectionHeader(title: "Use First", badge: StatusBadge(title: "3 items", tone: .warning),
                          action: PPAction(title: "See All", systemImage: "chevron.right") { interactionCount += 1 })
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: PPSpacing.sm))
                : AnyLayout(HStackLayout(alignment: .top, spacing: PPSpacing.sm))
            layout {
                FoodCard(title: "Whole Milk", subtitle: "1L bottle • Fridge", image: Image("FoodMilk"),
                         expiry: StatusBadge(title: "1 day left", tone: .danger),
                         status: StatusBadge(title: "Critical", tone: .danger, systemImage: "exclamationmark.circle"),
                         action: PPAction(title: "Use", systemImage: "checkmark") { interactionCount += 1 })
                FoodCard(title: "A longer ingredient name", subtitle: "No photo available • Pantry",
                         expiry: StatusBadge(title: "5 days left", tone: .success),
                         status: StatusBadge(title: "Fresh", tone: .success, systemImage: "leaf"))
            }

            SectionHeader(title: "Dashboard statistics")
            layout {
                DashboardStatCard(title: "Added", value: "32", unit: "items", detail: "Pantry total", systemImage: "archivebox")
                DashboardStatCard(title: "Consumed", value: "25", unit: "items", detail: "Eaten fresh", systemImage: "checkmark.circle", tone: .success)
            }

            SectionHeader(title: "Status badges")
            VStack(alignment: .leading, spacing: PPSpacing.xs) {
                StatusBadge(title: "Stable", tone: .neutral)
                StatusBadge(title: "Fresh", tone: .success, systemImage: "leaf")
                StatusBadge(title: "Expiring soon", tone: .warning, systemImage: "clock")
                StatusBadge(title: "Needs attention", tone: .danger, systemImage: "exclamationmark.circle")
            }

            EmptyStateView(title: "Your pantry is empty",
                           message: "Start adding your food and let PantryPulse keep track of what you have.",
                           systemImage: "cabinet",
                           primaryAction: PPAction(title: "Add Food", systemImage: "plus") { interactionCount += 1 },
                           secondaryAction: PPAction(title: "Scan with AI", systemImage: "sparkles") { interactionCount += 1 })
            LoadingStateView(title: "Loading your pantry", message: "Getting everything ready.")
            Text("Preview interactions: \(interactionCount)")
                .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
        }
        .padding(PPSpacing.lg)
        .background(PPColors.background)
    }
}

#Preview("Components — light") {
    ScrollView { DesignSystemPreviewContent() }
        .background(PPColors.background)
        .preferredColorScheme(.light)
}

#Preview("Components — dark") {
    ScrollView { DesignSystemPreviewContent() }
        .background(PPColors.background)
        .preferredColorScheme(.dark)
}

#Preview("Components — accessibility text") {
    ScrollView { DesignSystemPreviewContent() }
        .background(PPColors.background)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif

import SwiftUI

struct HomeView: View {
    let pantry: PantryViewModel
    let onUseFirst: () -> Void
    let onFoodSelection: (UUID) -> Void
    let onAddFood: () -> Void
    let onPantry: () -> Void
    let onNotifications: () -> Void
    let onProfile: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.xl) {
                ScreenHeader(title: "Your Pantry", subtitle: "Welcome to PantryPulse")
                PantrySummaryCard(total: pantry.itemCount, fresh: pantry.freshCount,
                                  expiringSoon: pantry.expiringSoonCount, urgent: pantry.urgentCount,
                                  expired: pantry.expiredCount, unknownExpiry: pantry.unknownExpiryCount, onAddFood: onAddFood)
                if pantry.isEmpty {
                    PantrySectionMessage(title: "Your pantry is empty", message: "Add your first food item to start tracking your inventory.")
                }
                VStack(spacing: PPSpacing.sm) {
                    SectionHeader(title: "Use First", badge: StatusBadge(title: "\(pantry.useFirst.count) items", tone: .warning),
                                  action: PPAction(title: "See all", systemImage: "chevron.right", action: onUseFirst))
                    if pantry.useFirst.isEmpty {
                        PantrySectionMessage(title: "Nothing to use first yet", message: pantry.isEmpty
                                             ? "Food approaching its expiry date will appear here once you add it."
                                             : "No food has an upcoming expiry date. Review expired items and items missing an expiry date.")
                    } else {
                        PantryFoodGrid(food: Array(pantry.useFirst.prefix(2)), onSelect: onFoodSelection)
                    }
                }
                VStack(spacing: PPSpacing.sm) {
                    SectionHeader(title: "Recently Added", action: PPAction(title: "View all", action: onPantry))
                    if pantry.recentlyAdded.isEmpty {
                        PantrySectionMessage(title: "No recently added food", message: "Saved food with an added date will appear here.")
                    } else {
                        ForEach(pantry.recentlyAdded.prefix(3)) { food in
                            PantryFoodRow(food: food) { onFoodSelection(food.id) }
                        }
                    }
                }
                Text("Expiry summaries use supplied dates only; they are not model predictions.")
                    .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
            }
            .padding(PPSpacing.lg)
            .frame(maxWidth: PPMetrics.screenContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(PPColors.background)
        .navigationTitle("Home Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image(systemName: "leaf.circle.fill").foregroundStyle(PPColors.primary).accessibilityHidden(true)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: onNotifications) { Image(systemName: "bell") }
                    .accessibilityLabel("Expiry reminders")
                    .accessibilityIdentifier("home.notifications")
                Button(action: onProfile) { Image(systemName: "person.crop.circle") }
                    .accessibilityLabel("Profile and settings")
                    .accessibilityIdentifier("home.profile")
            }
        }
        .tint(PPColors.actionText)
    }
}

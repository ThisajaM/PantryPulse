import SwiftUI

struct UseFirstView: View {
    let pantry: PantryViewModel
    let onSelect: (UUID) -> Void
    let onExpired: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PPSpacing.lg) {
                Text("Expiry dates come first. Experimental Core ML risk orders items with the same expiry day.")
                    .font(PPTypography.body).foregroundStyle(PPColors.secondaryText)
                PantrySectionMessage(title: "\(pantry.urgentCount + pantry.expiringSoonCount) items need attention",
                                     message: "Items due today or tomorrow come first, followed by foods expiring soon. These dates are not a food-safety assessment.")
                Button(action: onExpired) {
                    NavigationRowLabel(title: "Expired Items (\(pantry.expiredCount))", systemImage: "calendar.badge.exclamationmark")
                        .ppCard()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("useFirst.expired")
                SectionHeader(title: "Use First", badge: StatusBadge(title: "\(pantry.useFirst.count) items"))
                if pantry.useFirst.isEmpty {
                    PantrySectionMessage(title: "No upcoming expiry dates",
                                         message: "Foods with upcoming expiry dates will appear here. Expired records are listed separately.")
                }
                ForEach(pantry.useFirst) { food in
                    VStack(alignment: .leading, spacing: PPSpacing.xs) {
                        PantryFoodRow(food: food, onSelect: { onSelect(food.id) }, priorityExplanation: food.priorityExplanation)
                        if let level = pantry.wasteRisk[food.id]?.level {
                            StatusBadge(title: "\(level.rawValue) risk • Core ML", tone: level.statusTone)
                        } else {
                            Text("Expiry rules only • model risk unavailable or pending")
                                .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                        }
                    }
                }
                if !pantry.unknownExpiry.isEmpty {
                    SectionHeader(title: "No expiry date", badge: StatusBadge(title: "\(pantry.unknownExpiry.count) items"))
                    ForEach(pantry.unknownExpiry) { food in
                        PantryFoodRow(food: food, onSelect: { onSelect(food.id) }, priorityExplanation: food.priorityExplanation)
                    }
                }
            }
            .padding(PPSpacing.lg)
            .frame(maxWidth: PPMetrics.screenContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(PPColors.background)
        .navigationTitle("Use First")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ExpiredItemsView: View {
    let pantry: PantryViewModel
    let onSelect: (UUID) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: PPSpacing.lg) {
                PantrySectionMessage(title: "\(pantry.expiredCount) expired items",
                                     message: "These active records are past their recorded expiry dates. They are excluded from Use First recommendations. Open an item to review its details or correct its date.")
                if pantry.expiredFood.isEmpty {
                    PantrySectionMessage(title: "No expired items", message: "Your active pantry has no recorded dates in the past.")
                }
                ForEach(pantry.expiredFood) { food in
                    PantryFoodRow(food: food, onSelect: { onSelect(food.id) }, priorityExplanation: food.priorityExplanation)
                }
            }
            .padding(PPSpacing.lg)
            .frame(maxWidth: PPMetrics.screenContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(PPColors.background)
        .navigationTitle("Expired Items")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension PantryFoodDisplay {
    var priorityExplanation: String {
        switch freshness {
        case .urgent: "Due today or tomorrow. Review this item first."
        case .expiringSoon: "Due soon. Plan ahead to use it before its recorded date."
        case .fresh: "A later expiry date. Earlier dated items are shown first."
        case .unknown: "No expiry date is recorded, so date-based priority is unavailable."
        case .expired: "\(abs(daysUntilExpiry ?? 0)) calendar days past the recorded date. Review this item separately."
        }
    }
}

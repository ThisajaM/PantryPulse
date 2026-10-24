import Foundation

/// Date-based presentation, not an ML score or a food-safety assessment.
/// Calendar days separate expired, urgent (0–1), soon (2–3), and fresh (4+) items.
struct PantryFoodDisplay: Identifiable {
    let item: PantryItem
    let daysUntilExpiry: Int?
    let addedDescription: String?
    var id: UUID { item.id }

    init(item: PantryItem, referenceDate: Date, calendar: Calendar) {
        self.item = item
        let today = calendar.startOfDay(for: referenceDate)
        daysUntilExpiry = ExpiryService.assess(item.expiryDate, on: referenceDate, calendar: calendar).daysRemaining
        addedDescription = item.addedAt.map {
            if calendar.isDate($0, inSameDayAs: referenceDate) { return "Added today" }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), calendar.isDate($0, inSameDayAs: yesterday) { return "Added yesterday" }
            return "Added \($0.formatted(date: .abbreviated, time: .omitted))"
        }
    }

    var freshness: PantryFreshness { assessment.freshness }
    var expiryText: String { assessment.description }
    private var assessment: ExpiryAssessment { ExpiryAssessment(daysRemaining: daysUntilExpiry) }

    var subtitle: String? {
        let parts = [item.category.rawValue, item.quantityDescription, item.storageLocation].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }
}

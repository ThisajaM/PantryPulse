import Foundation

nonisolated struct WasteRiskFeatures: Sendable, Equatable {
    let category: String
    let storageType: String
    let daysUntilExpiry: Int
    let quantityValue: Double
    let quantityUnit: String
    let historyEventCount: Int
    let historicalWasteRate: Double
    let explanations: [String]
}

enum WasteRiskInputError: LocalizedError {
    case unsupported(String)
    var errorDescription: String? {
        switch self { case .unsupported(let reason): return reason }
    }
}

/// Matches the exported model's synthetic training schema. Never imputes missing expiry or storage.
enum WasteRiskFeatureBuilder {
    static func build(item: PantryItem, history: [UsageEvent], on date: Date,
                      calendar: Calendar = .autoupdatingCurrent) throws -> WasteRiskFeatures {
        guard item.status == .active else { throw WasteRiskInputError.unsupported("This item is no longer active.") }
        let expiry = ExpiryService.assess(item.expiryDate, on: date, calendar: calendar)
        guard let days = expiry.daysRemaining else {
            throw WasteRiskInputError.unsupported("Add an expiry date to enable model assessment.")
        }
        guard (0...120).contains(days) else {
            throw WasteRiskInputError.unsupported(days < 0
                ? "Past-expiry items are reviewed separately; the model was not trained on them."
                : "This expiry is beyond the model's 120-day training range.")
        }
        guard item.category != .snacks else {
            throw WasteRiskInputError.unsupported("The model was not trained on the Snacks category.")
        }
        guard let storage = item.storageLocation, ["Fridge", "Pantry", "Freezer"].contains(storage) else {
            throw WasteRiskInputError.unsupported("The model supports Fridge, Pantry or Freezer storage. Check the recorded location.")
        }
        guard let quantity = item.quantity, quantity.isFinite, quantity > 0,
              let unit = item.quantityUnit, ["pieces", "packs", "g", "kg", "ml", "L"].contains(unit.rawValue) else {
            throw WasteRiskInputError.unsupported("A positive quantity in pieces, packs, g, kg, ml or L is required by the model.")
        }
        // Event frequency is category-specific; never sum incompatible quantities or include future records.
        let events = history.filter { $0.category == item.category && $0.date <= date }
            .sorted { $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date }
            .prefix(30)
        let wasted = events.filter { $0.type == .wasted }.count
        let rate = events.isEmpty ? 0 : Double(wasted) / Double(events.count)
        return WasteRiskFeatures(category: item.category.rawValue, storageType: storage,
            daysUntilExpiry: days, quantityValue: quantity, quantityUnit: unit.rawValue,
            historyEventCount: events.count, historicalWasteRate: rate,
            explanations: [
                "Recorded expiry: \(expiry.description.lowercased()).",
                "Recorded storage: \(storage). Remaining quantity: \(quantity.formatted()) \(unit.rawValue).",
                events.isEmpty
                    ? "No recorded history for \(item.category.rawValue). The model uses its cold-start inputs; this is not evidence of no waste."
                    : "Of the latest \(events.count) recorded \(item.category.rawValue) events, \(wasted) were waste events. This is event frequency, not wasted weight."
            ])
    }
}

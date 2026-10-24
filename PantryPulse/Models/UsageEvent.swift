import Foundation

enum UsageEventType: String, CaseIterable, Identifiable {
    case consumed, wasted
    var id: Self { self }
    var title: String { self == .consumed ? "Consumed" : "Wasted" }
}

struct UsageEvent: Identifiable, Equatable {
    let id: UUID
    let itemID: UUID
    let itemName: String
    let category: FoodCategory
    let type: UsageEventType
    let quantity: Double
    let unit: QuantityUnit
    let date: Date
}

enum UsageError: LocalizedError, Equatable {
    case inactiveItem, conflictingRequest, staleItem, invalidHistory
    var errorDescription: String? {
        switch self {
        case .inactiveItem: "This food is no longer active. No usage was recorded."
        case .conflictingRequest: "This confirmation was already used for a different action. Reload the food before trying again."
        case .staleItem: "This food changed while you were reviewing it. Check its details and confirm again."
        case .invalidHistory: "A saved history record could not be read. Please try again."
        }
    }
}

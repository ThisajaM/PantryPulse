import Combine
import Foundation

@MainActor
protocol PantryRepositoryProtocol: AnyObject {
    /// Emitted after a successful mutation; subscribers can refetch saved values.
    var changes: AnyPublisher<Void, Never> { get }
    func create(_ draft: FoodDraft) throws -> PantryItem
    func fetchAll(sort: PantryFetchSort) throws -> [PantryItem]
    func fetchActive(sort: PantryFetchSort) throws -> [PantryItem]
    func fetch(id: UUID) throws -> PantryItem?
    func update(_ draft: FoodDraft) throws -> PantryItem
    func delete(id: UUID) throws
    func recordUsage(itemID: UUID, type: UsageEventType, eventID: UUID, expectedUpdatedAt: Date?) throws -> UsageEvent
    func fetchUsageEvents() throws -> [UsageEvent]
    func search(name: String, category: FoodCategory?, activeOnly: Bool, sort: PantryFetchSort) throws -> [PantryItem]
    func filter(category: FoodCategory, sort: PantryFetchSort) throws -> [PantryItem]
}

enum PantryRepositoryError: LocalizedError, Equatable {
    case itemNotFound(UUID), conflictingCreate(UUID), invalidRecord, duplicateIdentity(UUID)
    var errorDescription: String? {
        switch self {
        case .itemNotFound: "This food item no longer exists."
        case .conflictingCreate: "This food was already saved with different details. Reload it before editing."
        case .invalidRecord: "A stored food record contains missing or unsupported values."
        case .duplicateIdentity: "Multiple stored food records have the same identity."
        }
    }
}

import Combine
import CoreData
import Testing
@testable import PantryPulse

@MainActor
struct UsageEventTests {
    @Test(arguments: [UsageEventType.consumed, .wasted])
    func fullUsageIsAtomicIdempotentAndRefreshesInventory(type: UsageEventType) async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let repo = PantryRepository(container: try #require(storage.container))
        var draft = FoodDraft(name: "Rice")
        draft.quantity = 0.456
        draft.quantityUnit = .kilograms
        draft.category = .grainsPantry
        draft.expiryDate = Date().addingTimeInterval(86400)
        let original = try repo.create(draft)
        let pantry = PantryViewModel(repository: repo)
        #expect(pantry.useFirst.count == 1)
        let eventID = UUID()
        let event = try repo.recordUsage(itemID: draft.id, type: type, eventID: eventID, expectedUpdatedAt: original.updatedAt)
        #expect(event.id == eventID && event.itemID == draft.id)
        #expect(event.quantity == 0.456 && event.unit == .kilograms)
        #expect(event.itemName == "Rice" && event.category == .grainsPantry && event.type == type)
        let item = try #require(try repo.fetch(id: draft.id))
        #expect(item.quantity == 0)
        #expect(item.status == (type == .consumed ? .consumed : .wasted))
        #expect(item.createdAt == original.createdAt)
        let updatedAt = try #require(item.updatedAt)
        let createdAt = try #require(original.updatedAt)
        #expect(updatedAt > createdAt)
        #expect(pantry.itemCount == 0 && pantry.useFirst.isEmpty)
        #expect(pantry.usageEvents == [event])
        #expect(pantry.insights(period: .all).count(type) == 1)
        #expect(try repo.recordUsage(itemID: draft.id, type: type, eventID: eventID, expectedUpdatedAt: original.updatedAt) == event)
        #expect(throws: UsageError.inactiveItem) {
            try repo.recordUsage(itemID: draft.id, type: type, eventID: UUID(), expectedUpdatedAt: item.updatedAt)
        }
        #expect(throws: UsageError.conflictingRequest) {
            try repo.recordUsage(itemID: draft.id, type: type == .consumed ? .wasted : .consumed, eventID: eventID, expectedUpdatedAt: item.updatedAt)
        }
        #expect(throws: UsageError.inactiveItem) { try repo.update(draft) }
        #expect(try repo.fetchUsageEvents().count == 1)
        try repo.delete(id: draft.id)
        #expect(try repo.fetchUsageEvents() == [event])
        #expect(pantry.usageEvents == [event])
    }

    @Test func unknownAndExpiredItemsCanBeRecordedWithoutInventedDates() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let repo = PantryRepository(container: try #require(storage.container))
        let pantry = PantryViewModel(repository: repo)
        let unknown = try repo.create(FoodDraft(name: "Unknown date"))
        var expiredDraft = FoodDraft(name: "Past date")
        expiredDraft.expiryDate = Date().addingTimeInterval(-3 * 86400)
        let expired = try repo.create(expiredDraft)
        #expect(pantry.unknownExpiry.count == 1 && pantry.expiredFood.count == 1)
        _ = try repo.recordUsage(itemID: expired.id, type: .wasted, eventID: UUID(), expectedUpdatedAt: expired.updatedAt)
        _ = try repo.recordUsage(itemID: unknown.id, type: .consumed, eventID: UUID(), expectedUpdatedAt: unknown.updatedAt)
        #expect(pantry.expiredFood.isEmpty && pantry.unknownExpiry.isEmpty && pantry.useFirst.isEmpty)
        #expect(try repo.fetch(id: unknown.id)?.expiryDate == nil)
        #expect(pantry.insights(period: .all).count(.consumed) == 1)
        #expect(pantry.insights(period: .all).count(.wasted) == 1)
    }

    @Test func staleConfirmationRejectsChangedQuantityWithoutRecordingHistory() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let repo = PantryRepository(container: try #require(storage.container))
        var draft = FoodDraft(name: "Milk")
        let original = try repo.create(draft)
        draft.quantity = 2
        let updated = try repo.update(draft)
        #expect(throws: UsageError.staleItem) {
            try repo.recordUsage(itemID: draft.id, type: .consumed, eventID: UUID(), expectedUpdatedAt: original.updatedAt)
        }
        #expect(try repo.fetchUsageEvents().isEmpty)
        #expect(try repo.fetch(id: draft.id) == updated)
    }

    @Test func historySurvivesDeletionAndDiskReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("usage.sqlite")
        let storage = PersistenceController(storeURL: url)
        await storage.load()
        let container = try #require(storage.container)
        let repo = PantryRepository(container: container)
        let item = try repo.create(FoodDraft(name: "Bread"))
        let event = try repo.recordUsage(itemID: item.id, type: .wasted, eventID: UUID(), expectedUpdatedAt: item.updatedAt)
        try repo.delete(id: item.id)
        for store in container.persistentStoreCoordinator.persistentStores { try container.persistentStoreCoordinator.remove(store) }
        let reopened = PersistenceController(storeURL: url)
        await reopened.load()
        let restored = PantryRepository(container: try #require(reopened.container))
        #expect(try restored.fetchAll().isEmpty)
        #expect(try restored.fetchUsageEvents() == [event])
    }

    @Test func failedTransactionRollsBackEventAndInventoryTogether() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("readonly.sqlite")
        let storage = PersistenceController(storeURL: url)
        await storage.load()
        let container = try #require(storage.container)
        let writer = PantryRepository(container: container)
        let item = try writer.create(FoodDraft(name: "Milk"))
        for store in container.persistentStoreCoordinator.persistentStores { try container.persistentStoreCoordinator.remove(store) }
        let readOnly = NSPersistentContainer(name: "PantryPulse", managedObjectModel: container.managedObjectModel)
        let description = NSPersistentStoreDescription(url: url)
        description.isReadOnly = true
        readOnly.persistentStoreDescriptions = [description]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readOnly.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        let repo = PantryRepository(container: readOnly)
        var publications = 0
        let token = repo.changes.sink { publications += 1 }
        defer { token.cancel() }
        #expect(throws: (any Error).self) {
            try repo.recordUsage(itemID: item.id, type: .consumed, eventID: UUID(), expectedUpdatedAt: item.updatedAt)
        }
        #expect(try repo.fetchUsageEvents().isEmpty)
        #expect(try repo.fetch(id: item.id) == item)
        #expect(publications == 0)
    }

    @Test func insightsCountsSnapshotsWithoutCombiningUnitsAndFiltersCalendarPeriods() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Colombo"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12)))
        func event(_ type: UsageEventType, _ unit: QuantityUnit, _ quantity: Double, _ category: FoodCategory, _ days: Int = 0) -> UsageEvent {
            UsageEvent(id: UUID(), itemID: UUID(), itemName: "Snapshot", category: category, type: type,
                       quantity: quantity, unit: unit, date: calendar.date(byAdding: .day, value: days, to: now)!)
        }
        let events = [event(.consumed, .litres, 1, .dairy), event(.wasted, .grams, 500, .vegetables),
                      event(.wasted, .pieces, 2, .vegetables), event(.wasted, .kilograms, 1, .bakery, -40)]
        let all = UsageInsights(events: events, period: .all, now: now, calendar: calendar)
        #expect(all.count(.consumed) == 1 && all.count(.wasted) == 3)
        #expect(all.itemCount(.wasted) == 3)
        #expect(all.wastedCategories.first?.category == .vegetables)
        #expect(all.wastedCategories.first?.count == 2)
        #expect(all.events.map(\.unit).contains(.pieces))
        #expect(UsageInsights(events: events, period: .month, now: now, calendar: calendar).count(.wasted) == 2)
        #expect(UsageInsights(events: events, period: .last30Days, now: now, calendar: calendar).count(.wasted) == 2)
        #expect(UsageInsights(events: events, period: .year, now: now, calendar: calendar).events.count == 4)
        let empty = UsageInsights(events: [], period: .all, now: now)
        #expect(empty.events.isEmpty && empty.count(.consumed) == 0 && empty.wastedCategories.isEmpty)
    }
}

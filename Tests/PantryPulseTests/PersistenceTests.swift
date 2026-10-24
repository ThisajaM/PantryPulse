import CoreData
import Testing
@testable import PantryPulse

@MainActor
struct PersistenceTests {
    private func loaded(inMemory: Bool = true, url: URL? = nil) async throws -> PersistenceController {
        let controller = PersistenceController(inMemory: inMemory, storeURL: url)
        await controller.load()
        if let error = controller.loadError { throw error }
        #expect(controller.container != nil)
        return controller
    }

    private func addFood(to context: NSManagedObjectContext) -> UUID {
        let item = PantryItemRecord(context: context)
        let id = UUID()
        item.id = id
        item.name = "Test food"
        item.category = "Other"
        item.quantity = 2
        item.quantityUnit = "pieces"
        item.purchaseDate = Date()
        item.storageLocation = "Pantry"
        item.createdAt = Date()
        item.updatedAt = Date()
        item.status = "active"
        return id
    }

    @Test func modelLoadsEmptyAndStoresAreIsolated() async throws {
        let first = try await loaded()
        let second = try await loaded()
        let context = try #require(first.container?.viewContext)
        let model = try #require(first.container?.managedObjectModel)
        #expect(Set(model.entitiesByName.keys) == ["Item", "PantryItem", "UsageEvent"])
        #expect(model.entitiesByName["PantryItem"]?.attributesByName.count == 14)
        #expect(model.entitiesByName["UsageEvent"]?.attributesByName.count == 8)
        #expect(first.container?.persistentStoreCoordinator.persistentStores.first?.type == NSInMemoryStoreType)
        #expect(try context.count(for: PantryItemRecord.fetchRequest()) == 0)
        #expect(try context.count(for: UsageEventRecord.fetchRequest()) == 0)
        let id = addFood(to: context)
        let event = UsageEventRecord(context: context)
        event.id = UUID()
        event.eventType = "consumed"
        event.quantity = 1
        event.quantityUnit = "pieces"
        event.eventDate = Date()
        event.itemID = id
        event.itemNameSnapshot = "Test food"
        event.categorySnapshot = "Other"
        try first.save()
        let item = try #require(context.fetch(PantryItemRecord.fetchRequest()).first)
        context.delete(item)
        try first.save()
        #expect(try context.count(for: UsageEventRecord.fetchRequest()) == 1)
        let secondContext = try #require(second.container?.viewContext)
        #expect(try secondContext.count(for: PantryItemRecord.fetchRequest()) == 0)
    }

    @Test func diskStoreSurvivesReopening() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite")
        let first = try await loaded(inMemory: false, url: url)
        let context = try #require(first.container?.viewContext)
        let id = addFood(to: context)
        try first.save()
        let coordinator = try #require(first.container?.persistentStoreCoordinator)
        for store in coordinator.persistentStores { try coordinator.remove(store) }
        let reopened = try await loaded(inMemory: false, url: url)
        defer {
            if let coordinator = reopened.container?.persistentStoreCoordinator {
                for store in coordinator.persistentStores { try? coordinator.remove(store) }
            }
        }
        let newContext = try #require(reopened.container?.viewContext)
        #expect(try newContext.fetch(PantryItemRecord.fetchRequest()).first?.id == id)
    }

    @Test func invalidSaveAndUnavailableStoreSurfaceErrors() async throws {
        let controller = try await loaded()
        let context = try #require(controller.container?.viewContext)
        _ = PantryItemRecord(context: context)
        #expect(throws: (any Error).self) { try controller.save() }
        #expect(context.hasChanges)
        context.rollback()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blocker)
        let failed = PersistenceController(storeURL: blocker.appendingPathComponent("store.sqlite"))
        defer {
            if let coordinator = failed.container?.persistentStoreCoordinator {
                for store in coordinator.persistentStores { try? coordinator.remove(store) }
            }
        }
        await failed.load()
        #expect(failed.loadError != nil)
        #expect(failed.container == nil)
        #expect(!failed.isLoading)
        #expect(throws: (any Error).self) { try failed.save() }
        try FileManager.default.removeItem(at: blocker)
        try FileManager.default.createDirectory(at: blocker, withIntermediateDirectories: true)
        await failed.load()
        #expect(failed.loadError == nil)
        #expect(failed.container != nil)
    }

    @Test func legacyStoreMigratesWithoutLosingItems() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundleURL = try #require(Bundle.main.url(forResource: "PantryPulse", withExtension: "momd"))
        let oldModel = try #require(NSManagedObjectModel(contentsOf: bundleURL.appendingPathComponent("PantryPulse.mom")))
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: oldModel)
        let url = directory.appendingPathComponent("legacy.sqlite")
        let store = try coordinator.addPersistentStore(type: .sqlite, at: url)
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let item = NSEntityDescription.insertNewObject(forEntityName: "Item", into: context)
        item.setValue(timestamp, forKey: "timestamp")
        try context.save()
        try coordinator.remove(store)
        let migrated = try await loaded(inMemory: false, url: url)
        defer {
            if let coordinator = migrated.container?.persistentStoreCoordinator {
                for store in coordinator.persistentStores { try? coordinator.remove(store) }
            }
        }
        let newContext = try #require(migrated.container?.viewContext)
        let legacy = try newContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Item"))
        #expect(legacy.count == 1)
        #expect(legacy.first?.value(forKey: "timestamp") as? Date == timestamp)
        #expect(try newContext.count(for: PantryItemRecord.fetchRequest()) == 0)
    }
}

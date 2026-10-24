import Combine
import CoreData
import Testing
@testable import PantryPulse

@MainActor
struct PantryRepositoryTests {
    private func store(url: URL? = nil) async throws -> PersistenceController {
        let store = PersistenceController(inMemory: url == nil, storeURL: url)
        await store.load()
        if let error = store.loadError { throw error }
        return store
    }

    @Test func createNormalizesAndRoundTripsAllFields() async throws {
        let store = try await store()
        let repository = PantryRepository(container: try #require(store.container))
        var draft = FoodDraft(name: "  Milk \n")
        draft.category = .dairy; draft.quantity = 1.5; draft.quantityUnit = .litres
        draft.expiryDate = Date(timeIntervalSince1970: 1_900_000_000)
        draft.storageLocation = " Fridge "; draft.notes = " Opened "; draft.barcode = " 123 "
        draft.imagePath = " images/milk.jpg "
        let item = try repository.create(draft)
        #expect(item.id == draft.id)
        #expect(item.name == "Milk")
        #expect(item.quantity == 1.5 && item.quantityUnit == .litres)
        #expect(item.category == .dairy && item.storageLocation == "Fridge")
        #expect(item.expiryDate == draft.expiryDate && item.purchaseDate == draft.purchaseDate)
        #expect(item.notes == "Opened" && item.barcode == "123" && item.imagePath == "images/milk.jpg")
        #expect(item.createdAt != nil && item.createdAt == item.updatedAt)
        #expect(try repository.fetch(id: draft.id) == item)
    }

    @Test func repeatedCreateIsIdempotentAndConflictsDoNotOverwrite() async throws {
        let store = try await store()
        let repository = PantryRepository(container: try #require(store.container))
        var draft = FoodDraft(name: "Apples")
        let original = try repository.create(draft)
        #expect(try repository.create(draft) == original)
        draft.name = "Pears"
        #expect(throws: PantryRepositoryError.conflictingCreate(draft.id)) { try repository.create(draft) }
        #expect(try repository.fetchAll().count == 1)
        #expect(try repository.fetch(id: draft.id) == original)
        _ = try repository.create(FoodDraft(name: "Apples"))
        #expect(try repository.fetchAll().count == 2, "Distinct drafts can represent two purchases of the same food.")
    }

    @Test func fetchActiveSearchFilterAndSort() async throws {
        let store = try await store()
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        let repository = PantryRepository(container: try #require(store.container), now: { clock })
        var cheese = FoodDraft(name: "Crème cheese"); cheese.category = .dairy
        let first = try repository.create(cheese)
        clock = clock.addingTimeInterval(60)
        var milk = FoodDraft(name: "Milk"); milk.category = .dairy
        milk.expiryDate = clock.addingTimeInterval(86400)
        let second = try repository.create(milk)
        clock = clock.addingTimeInterval(60)
        var banana = FoodDraft(name: "Banana"); banana.category = .fruits; banana.status = .consumed
        banana.expiryDate = clock.addingTimeInterval(-86400)
        let third = try repository.create(banana)
        #expect(try repository.fetchAll(sort: .createdOldest).map(\.id) == [first.id, second.id, third.id])
        #expect(try repository.fetchAll(sort: .createdNewest).map(\.id) == [third.id, second.id, first.id])
        #expect(try repository.fetchAll(sort: .expirySoonest).map(\.id) == [third.id, second.id, first.id])
        #expect(try repository.fetchActive().count == 2)
        #expect(try repository.search(name: " CREME ").map(\.id) == [first.id])
        #expect(try repository.search(name: "milk", category: .fruits).isEmpty)
        #expect(try repository.search(name: "banana", activeOnly: true).isEmpty)
        #expect(try repository.filter(category: .dairy).count == 2)
        #expect(try repository.fetch(id: UUID()) == nil)
    }

    @Test func updatePreservesIdentityAndCreationDateAndClearsOptionals() async throws {
        let store = try await store()
        let repository = PantryRepository(container: try #require(store.container), now: { Date(timeIntervalSince1970: 100) })
        var draft = FoodDraft(name: "Milk"); draft.expiryDate = Date(); draft.notes = "Note"
        let original = try repository.create(draft)
        draft.name = "Oat milk"; draft.quantity = 3; draft.quantityUnit = .bottles
        draft.expiryDate = nil; draft.notes = " "; draft.status = .archived
        let changed = try repository.update(draft)
        #expect(changed.id == original.id && changed.createdAt == original.createdAt)
        #expect(try #require(changed.updatedAt) > #require(original.updatedAt))
        #expect(changed.name == "Oat milk" && changed.quantity == 3 && changed.quantityUnit == .bottles)
        #expect(changed.expiryDate == nil && changed.notes == nil)
        #expect(try repository.fetchActive().isEmpty)
        #expect(try repository.fetch(id: changed.id) == changed)
        let missing = FoodDraft(name: "Missing")
        #expect(throws: PantryRepositoryError.itemNotFound(missing.id)) { try repository.update(missing) }
    }

    @Test func deleteRemovesOnlyRequestedItem() async throws {
        let store = try await store()
        let repository = PantryRepository(container: try #require(store.container))
        let first = try repository.create(FoodDraft(name: "Milk"))
        let second = try repository.create(FoodDraft(name: "Bread"))
        try repository.delete(id: first.id)
        #expect(try repository.fetch(id: first.id) == nil)
        #expect(try repository.fetchAll().map(\.id) == [second.id])
        #expect(throws: PantryRepositoryError.itemNotFound(first.id)) { try repository.delete(id: first.id) }
    }

    @Test func validationRejectsBadInputWithoutMutatingSavedData() async throws {
        let store = try await store()
        let repository = PantryRepository(container: try #require(store.container))
        #expect(throws: FoodValidationError.emptyName) { try repository.create(FoodDraft(name: " \n ")) }
        for quantity in [0, -1, Double.nan, Double.infinity, -Double.infinity] {
            var draft = FoodDraft(name: "Milk"); draft.quantity = quantity
            #expect(throws: FoodValidationError.invalidQuantity) { try repository.create(draft) }
        }
        var draft = FoodDraft(name: "Milk"); draft.storageLocation = " "
        #expect(throws: FoodValidationError.emptyStorage) { try repository.create(draft) }
        #expect(try repository.fetchAll().isEmpty)
        draft.storageLocation = "Fridge"
        let original = try repository.create(draft)
        draft.quantity = -5
        #expect(throws: FoodValidationError.invalidQuantity) { try repository.update(draft) }
        #expect(try repository.fetch(id: draft.id) == original)
    }

    @Test func successfulMutationsRefreshSharedPresentationAndRetainFilters() async throws {
        let store = try await store()
        let repository = PantryRepository(container: try #require(store.container))
        let viewModel = PantryViewModel(repository: repository)
        viewModel.searchText = "milk"; viewModel.selectedCategory = .dairy
        var draft = FoodDraft(name: "Milk"); draft.category = .dairy
        _ = try repository.create(draft)
        #expect(viewModel.itemCount == 1 && viewModel.visibleFood.count == 1)
        #expect(viewModel.recentlyAdded.count == 1)
        draft.quantity = 2
        _ = try repository.update(draft)
        #expect(viewModel.items.first?.quantity == 2)
        try repository.delete(id: draft.id)
        #expect(viewModel.items.isEmpty)
        #expect(viewModel.searchText == "milk" && viewModel.selectedCategory == .dairy)
        #expect(viewModel.loadError == nil)
    }

    @Test func repositoryPersistsAcrossReopeningAndRetryDoesNotDuplicate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("repository.sqlite")
        let first = try await store(url: url)
        let repository = PantryRepository(container: try #require(first.container))
        let draft = FoodDraft(name: "Rice")
        let saved = try repository.create(draft)
        let coordinator = try #require(first.container?.persistentStoreCoordinator)
        for store in coordinator.persistentStores { try coordinator.remove(store) }
        let second = try await store(url: url)
        defer {
            if let coordinator = second.container?.persistentStoreCoordinator {
                for store in coordinator.persistentStores { try? coordinator.remove(store) }
            }
        }
        let reopened = PantryRepository(container: try #require(second.container))
        #expect(try reopened.fetch(id: saved.id) == saved)
        #expect(try reopened.create(draft) == saved)
        #expect(try reopened.fetchAll().count == 1)
    }

    @Test func corruptRecordSurfacesLoadErrorInsteadOfEmptySuccess() async throws {
        let store = try await store()
        let container = try #require(store.container)
        let repository = PantryRepository(container: container)
        let item = try repository.create(FoodDraft(name: "Rice"))
        let raw = try #require(container.viewContext.fetch(PantryItemRecord.fetchRequest()).first)
        raw.category = "Unsupported category"
        try store.save()
        let freshRepository = PantryRepository(container: container)
        #expect(throws: PantryRepositoryError.invalidRecord) { try freshRepository.fetch(id: item.id) }
        let viewModel = PantryViewModel(repository: freshRepository)
        #expect(viewModel.loadError != nil)
    }

    @Test func failedSaveRollsBackAndDoesNotPublishSuccess() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("readonly.sqlite")
        let original = try await store(url: url)
        let container = try #require(original.container)
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
        let readOnly = NSPersistentContainer(name: "PantryPulse", managedObjectModel: container.managedObjectModel)
        let description = NSPersistentStoreDescription(url: url)
        description.isReadOnly = true
        readOnly.persistentStoreDescriptions = [description]
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            readOnly.loadPersistentStores { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        defer {
            for store in readOnly.persistentStoreCoordinator.persistentStores {
                try? readOnly.persistentStoreCoordinator.remove(store)
            }
        }
        let repository = PantryRepository(container: readOnly)
        var notifications = 0
        let token = repository.changes.sink { notifications += 1 }
        defer { token.cancel() }
        #expect(throws: (any Error).self) { try repository.create(FoodDraft(name: "Unsaved")) }
        #expect(try repository.fetchAll().isEmpty)
        #expect(notifications == 0)
    }

}

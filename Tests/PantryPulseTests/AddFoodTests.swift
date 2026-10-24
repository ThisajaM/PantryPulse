import CoreData
import Testing
@testable import PantryPulse

@MainActor
struct AddFoodTests {
    private func loaded(url: URL? = nil) async throws -> PersistenceController {
        let storage = PersistenceController(inMemory: url == nil, storeURL: url)
        await storage.load()
        if let error = storage.loadError { throw error }
        return storage
    }

    @Test func validFormSavesAllFieldsAndRefreshesPantryOnlyOnce() async throws {
        let storage = try await loaded()
        let repository = PantryRepository(container: try #require(storage.container))
        let pantry = PantryViewModel(repository: repository)
        let form = AddFoodViewModel(save: pantry.createFood)
        form.draft.name = "  Yogurt  "
        form.draft.category = .dairy
        form.quantityText = "2.5"
        form.draft.quantityUnit = .kilograms
        form.draft.storageLocation = "Fridge"
        form.includesExpiry = true
        form.expiryDate = Date(timeIntervalSince1970: 1_900_000_000)
        form.notes = "  Opened today  "
        #expect(form.save())
        #expect(!form.save())
        let item = try #require(try repository.fetch(id: form.draft.id))
        #expect(item.name == "Yogurt")
        #expect(item.quantity == 2.5)
        #expect(item.category == .dairy)
        #expect(item.quantityUnit == .kilograms)
        #expect(item.purchaseDate == form.draft.purchaseDate)
        #expect(item.storageLocation == "Fridge")
        #expect(item.expiryDate == form.expiryDate)
        #expect(item.notes == "Opened today")
        #expect(pantry.items.count == 1)
        #expect(form.savedItem == item)
    }

    @Test func blankNameIsRejectedAndInputsRemainEditable() async throws {
        let storage = try await loaded()
        let repo = PantryRepository(container: try #require(storage.container))
        let form = AddFoodViewModel(save: repo.create)
        form.draft.name = " \n "
        #expect(!form.save())
        #expect(form.errorMessage == FoodValidationError.emptyName.localizedDescription)
        #expect(form.savedItem == nil)
        #expect(try repo.fetchAll().isEmpty)
        form.draft.name = "Apples"
        #expect(form.save())
        #expect(form.errorMessage == nil)
    }

    @Test func invalidQuantitiesNeverPersist() async throws {
        let storage = try await loaded()
        let repo = PantryRepository(container: try #require(storage.container))
        let form = AddFoodViewModel(locale: Locale(identifier: "en_US"), save: repo.create)
        form.draft.name = "Rice"
        for value in ["", "abc", "0", "-1", "NaN", "inf", "1.2.3", "2kg"] {
            form.quantityText = value
            #expect(!form.save())
            #expect(form.errorMessage == FoodValidationError.invalidQuantity.localizedDescription)
            #expect(form.savedItem == nil)
        }
        #expect(try repo.fetchAll().isEmpty)
    }

    @Test func omittedExpiryAndLocalizedQuantityPersistAfterDiskReopen() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("form.sqlite")
        let storage = try await loaded(url: url)
        let container = try #require(storage.container)
        let repo = PantryRepository(container: container)
        let form = AddFoodViewModel(locale: Locale(identifier: "fr_FR"), save: repo.create)
        form.draft.name = "Rice"
        form.quantityText = "1,5"
        form.includesExpiry = true
        form.includesExpiry = false
        #expect(form.save())
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
        let reopened = try await loaded(url: url)
        let reopenedContainer = try #require(reopened.container)
        defer {
            for store in reopenedContainer.persistentStoreCoordinator.persistentStores {
                try? reopenedContainer.persistentStoreCoordinator.remove(store)
            }
        }
        let fetched = try #require(try PantryRepository(container: reopenedContainer).fetch(id: form.draft.id))
        #expect(fetched.quantity == 1.5)
        #expect(fetched.expiryDate == nil)
        #expect(fetched.notes == nil)
        #expect(fetched.imagePath == nil)
    }

    @Test func failedSaveRetainsDraftAndAllowsRetry() async throws {
        let storage = try await loaded()
        let repo = PantryRepository(container: try #require(storage.container))
        var fail = true
        let form = AddFoodViewModel { draft in
            if fail { throw PersistenceError.storeUnavailable }
            return try repo.create(draft)
        }
        form.draft.name = "Bananas"
        let id = form.draft.id
        #expect(!form.save())
        #expect(form.errorMessage?.contains("Your entries are still here") == true)
        #expect(!form.isSaving)
        #expect(form.savedItem == nil)
        #expect(form.draft.name == "Bananas")
        #expect(try repo.fetchAll().isEmpty)
        fail = false
        #expect(form.save())
        #expect(form.savedItem?.id == id)
        #expect(try repo.fetchAll().count == 1)
    }
}

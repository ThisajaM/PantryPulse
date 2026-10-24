import CoreData
import Testing
@testable import PantryPulse

@MainActor
struct FoodDetailsTests {
    @Test func detailsTrackEditsAndDeletionByPersistentIdentity() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let repo = PantryRepository(container: try #require(storage.container))
        let pantry = PantryViewModel(repository: repo)
        var draft = FoodDraft(name: "Rice")
        draft.imagePath = "Documents/rice.jpg"
        draft.barcode = "12345"
        draft.notes = "Sealed"
        let original = try repo.create(draft)
        let details = pantry.detailsModel(id: original.id)
        #expect(details.item == original)
        let editing = try #require(try pantry.foodDraft(id: original.id))
        let form = AddFoodViewModel(draft: editing, save: pantry.updateFood)
        form.draft.name = "Brown Rice"
        form.quantityText = "2.5"
        #expect(form.save())
        #expect(details.item?.name == "Brown Rice")
        #expect(details.item?.quantity == 2.5)
        #expect(details.item?.expiryDate == nil)
        #expect(details.item?.barcode == "12345")
        #expect(details.item?.imagePath == "Documents/rice.jpg")
        #expect(details.item?.createdAt == original.createdAt)
        #expect(pantry.items.first?.name == "Brown Rice")
        #expect(details.delete())
        #expect(details.item == nil)
        #expect(pantry.isEmpty)
        #expect(try pantry.foodDraft(id: original.id) == nil)
        #expect(!form.save())
    }

    @Test func editingDeletedFoodFailsWithoutRecreatingIt() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let repo = PantryRepository(container: try #require(storage.container))
        let original = try repo.create(FoodDraft(name: "Apples"))
        let draft = try FoodDraft(item: original)
        let form = AddFoodViewModel(draft: draft, save: repo.update)
        try repo.delete(id: original.id)
        #expect(!form.save())
        #expect(form.errorMessage != nil)
        #expect(form.savedItem == nil)
        #expect(try repo.fetchAll().isEmpty)
        #expect(form.draft.name == "Apples")
    }

    @Test func deletedAndUnavailableRecordsAreHandled() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let repo = PantryRepository(container: try #require(storage.container))
        let details = FoodDetailsViewModel(id: UUID(), repository: repo)
        #expect(details.item == nil)
        #expect(details.errorMessage == nil)
        #expect(!details.delete())
        #expect(details.errorMessage != nil)
        let unavailable = FoodDetailsViewModel(id: UUID(), repository: nil)
        #expect(unavailable.item == nil)
        #expect(unavailable.errorMessage != nil)
    }
}

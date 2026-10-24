import CoreData
import Testing
@testable import PantryPulse

@MainActor
struct InventoryManagementTests {
    @Test func searchCategoryAndAllSortOrdersCombineOverSavedRecords() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let repo = PantryRepository(container: try #require(storage.container), now: { clock })
        let pantry = PantryViewModel(repository: repo)
        var apple = FoodDraft(name: "Apple juice")
        apple.category = .fruits
        apple.expiryDate = clock.addingTimeInterval(86_400)
        let first = try repo.create(apple)
        clock = clock.addingTimeInterval(1)
        var berry = FoodDraft(name: "berry juice")
        berry.category = .fruits
        let second = try repo.create(berry)
        clock = clock.addingTimeInterval(1)
        var carrot = FoodDraft(name: "Carrot juice")
        carrot.category = .vegetables
        carrot.expiryDate = clock
        _ = try repo.create(carrot)
        pantry.searchText = "  JUICE  "
        pantry.selectedCategory = .fruits
        let expected: [(PantrySortOrder, [UUID])] = [
            (.expirySoonest, [first.id, second.id]),
            (.recentlyAdded, [second.id, first.id]),
            (.name, [first.id, second.id]),
            (.nameDescending, [second.id, first.id])
        ]
        for (sort, ids) in expected {
            pantry.sortOrder = sort
            #expect(pantry.visibleFood.map(\.id) == ids)
        }
        pantry.selectedCategory = .dairy
        #expect(pantry.visibleFood.isEmpty)
        pantry.clearFilters()
        #expect(pantry.visibleFood.count == 3)
        #expect(pantry.sortOrder == .nameDescending)
        pantry.selectedCategory = .fruits
        var edited = try FoodDraft(item: first)
        edited.name = "Zesty juice"
        edited.category = .vegetables
        let updated = try pantry.updateFood(edited)
        #expect(updated.id == first.id)
        #expect(updated.createdAt == first.createdAt)
        #expect(try #require(updated.updatedAt) > #require(first.updatedAt))
        #expect(pantry.visibleFood.map(\.id) == [second.id])
        #expect(pantry.selectedCategory == .fruits)
        try repo.delete(id: second.id)
        #expect(pantry.visibleFood.isEmpty)
        #expect(pantry.itemCount == 2)
    }

    @Test func equalNamesHaveDeterministicUUIDTieBreaksInBothDirections() {
        let a = PantryItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Rice")
        let b = PantryItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Rice")
        let pantry = PantryViewModel(items: [b, a])
        for sort in [PantrySortOrder.name, .nameDescending] {
            pantry.sortOrder = sort
            #expect(pantry.visibleFood.map(\.id) == [a.id, b.id])
        }
    }
}

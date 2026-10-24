import Foundation
import Testing
import UIKit
@testable import PantryPulse

@MainActor struct AccountIsolationTests {
    @Test func accountStoresRestoreWithoutAdoptingLegacyData() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var stores: [PersistenceController] = []
        defer {
            for store in stores { try? store.close() }
            try? FileManager.default.removeItem(at: base)
        }
        let legacy = PersistenceController(storeURL: base.appendingPathComponent("PantryPulse.sqlite"))
        stores.append(legacy)
        await legacy.load()
        let legacyRepo = PantryRepository(container: try #require(legacy.container), photos: FoodPhotoStorage(root: base))
        _ = try legacyRepo.create(FoodDraft(name: "Unowned legacy food"))
        let a = AccountStoragePaths(uid: "A", base: base)
        let b = AccountStoragePaths(uid: "B", base: base)
        #expect(a.root != b.root)
        #expect(a.storeURL == AccountStoragePaths(uid: "A", base: base).storeURL)
        let storeA = PersistenceController(storeURL: a.storeURL)
        stores.append(storeA)
        await storeA.load()
        let repoA = PantryRepository(container: try #require(storeA.container), photos: a.photos)
        let image = try #require(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.jpegData(compressionQuality: 0.8))
        let path = try a.photos.save(image)
        var milk = FoodDraft(name: "Milk"); milk.imagePath = path; milk.quantity = 2; milk.quantityUnit = .litres
        let saved = try repoA.create(milk)
        _ = try repoA.create(FoodDraft(name: "Bananas"))
        _ = try repoA.create(FoodDraft(name: "Rice"))
        let historyFood = try repoA.create(FoodDraft(name: "History food"))
        _ = try repoA.recordUsage(itemID: historyFood.id, type: .wasted, eventID: UUID(), expectedUpdatedAt: historyFood.updatedAt)
        #expect(try repoA.fetchActive(sort: .createdNewest).count == 3)
        repoA.invalidate()
        #expect(throws: PersistenceError.self) { try repoA.create(FoodDraft(name: "Late A write")) }
        try storeA.close()
        let storeB = PersistenceController(storeURL: b.storeURL)
        stores.append(storeB)
        await storeB.load()
        let repoB = PantryRepository(container: try #require(storeB.container), photos: b.photos)
        #expect(try repoB.fetchAll(sort: .createdNewest).isEmpty)
        #expect(try repoB.fetchUsageEvents().isEmpty)
        #expect(throws: (any Error).self) { try b.photos.load(path) }
        #expect(throws: (any Error).self) { try b.photos.load(a.root.appendingPathComponent(path).path) }
        _ = try repoB.create(FoodDraft(name: "Apples"))
        repoB.invalidate(); try storeB.close()
        await storeA.load()
        let restored = PantryRepository(container: try #require(storeA.container), photos: a.photos)
        #expect(Set(try restored.fetchActive(sort: .createdNewest).map(\.name)) == ["Milk", "Bananas", "Rice"])
        #expect(try restored.fetch(id: saved.id)?.quantity == 2)
        #expect(try restored.fetchUsageEvents().count == 1)
        #expect(try UIImage(data: a.photos.load(path)) != nil)
        #expect(try Data(contentsOf: #require(a.photos.url(for: path))) == image)
        #expect(try legacyRepo.fetchAll(sort: .createdNewest).map(\.name) == ["Unowned legacy food"])
        restored.invalidate(); try storeA.close(); legacyRepo.invalidate(); try legacy.close()
    }

    @Test func workspacePreferencesAndUseFirstStayAccountScoped() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = AccountWorkspace()
        workspace.select(uid: "preferences-A", base: base)
        await workspace.waitForTransition()
        workspace.preferences.set("dark", forKey: "test.appearance")
        workspace.reminders?.setTime(hour: 14, minute: 15)
        var food = FoodDraft(name: "Only A")
        food.expiryDate = Date()
        _ = try #require(workspace.pantry).createFood(food)
        #expect(workspace.pantry?.useFirst.count == 1)
        workspace.select(uid: "preferences-B", base: base)
        await workspace.waitForTransition()
        #expect(workspace.preferences.string(forKey: "test.appearance") == nil)
        #expect(workspace.reminders?.preferences.hour == 9)
        #expect(workspace.pantry?.itemCount == 0)
        #expect(workspace.pantry?.useFirst.isEmpty == true)
        #expect(workspace.pantry?.insights(period: .all).events.isEmpty == true)
        workspace.select(uid: "preferences-A", base: base)
        await workspace.waitForTransition()
        #expect(workspace.preferences.string(forKey: "test.appearance") == "dark")
        #expect(workspace.reminders?.preferences.hour == 14)
        #expect(workspace.pantry?.useFirst.first?.item.name == "Only A")
        workspace.select(uid: nil, base: base)
        await workspace.waitForTransition()
        try FileManager.default.removeItem(at: base)
    }

    @Test func rapidTransitionsKeepOnlyLatestAccount() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let workspace = AccountWorkspace()
        workspace.select(uid: "A", base: base)
        workspace.select(uid: "B", base: base)
        workspace.select(uid: "C", base: base)
        await workspace.waitForTransition()
        #expect(workspace.uid == "C")
        #expect(workspace.pantry?.items.isEmpty == true)
        let old = try #require(workspace.pantry)
        workspace.select(uid: nil, base: base)
        #expect(workspace.pantry == nil)
        #expect(old.items.isEmpty)
        #expect(throws: PersistenceError.self) { try old.createFood(FoodDraft(name: "Stale")) }
        await workspace.waitForTransition()
        try FileManager.default.removeItem(at: base)
    }
}

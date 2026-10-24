import Foundation
import Testing
import UIKit
import CoreML
@testable import PantryPulse

@MainActor
struct FoodRecognitionTests {
    private func photo() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 320)).image { context in
            UIColor.orange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 320, height: 320))
        }
        return try #require(image.jpegData(compressionQuality: 0.8))
    }

    @Test func bundledModelLoadsAndChecksInferenceOrKnownSimulatorLimitation() async throws {
        let url = try #require(Bundle.main.url(forResource: "FoodRecognition", withExtension: "mlmodelc"))
        let loaded = try MLModel(contentsOf: url)
        #expect(loaded.modelDescription.classLabels?.count == 151)
        let result: FoodRecognitionResult
        do { result = try await FoodRecognitionService().recognize(photo()) }
        catch {
            #if targetEnvironment(simulator)
            let failure = error as NSError
            // This runtime cannot execute the export's Vision feature-print stage.
            // Device tests must still perform inference successfully.
            if failure.domain == "com.apple.Vision", failure.code == 9 { return }
            #endif
            throw error
        }
        #expect(result.supportedLabels.count == 151)
        #expect(result.supportedLabels.contains("Banana"))
        #expect(result.predictions.count == 151)
        #expect(result.predictions.allSatisfy { (0...1).contains($0.confidence) })
        #expect(abs(result.predictions.reduce(0) { $0 + $1.confidence } - 1) < 0.01)
        // A synthetic image verifies inference plumbing, not food-recognition accuracy.
    }

    @Test func missingModelAndUnreadablePhotoThrow() async throws {
        await #expect(throws: FoodRecognitionError.self) {
            _ = try await FoodRecognitionService(modelURL: nil).recognize(self.photo())
        }
        await #expect(throws: FoodRecognitionError.self) {
            _ = try await FoodRecognitionService().recognize(Data("not an image".utf8))
        }
    }

    @Test func uncertainScoresRequireReviewAndCategoriesAreConservative() {
        func result(_ a: Double, _ b: Double) -> FoodRecognitionResult {
            .init(predictions: [.init(label: "Apple", confidence: a), .init(label: "Pear", confidence: b)], supportedLabels: ["Apple", "Pear"])
        }
        #expect(result(0.59, 0.10).needsExtraReview)
        #expect(result(0.65, 0.55).needsExtraReview)
        #expect(!result(0.85, 0.10).needsExtraReview)
        #expect(FoodRecognitionResult(predictions: [], supportedLabels: []).needsExtraReview)
        #expect(FoodRecognitionCategory.category(for: "Banana") == .fruits)
        #expect(FoodRecognitionCategory.category(for: "Eggplant") == .vegetables)
        #expect(FoodRecognitionCategory.category(for: "pizza") == .other)
        #expect(FoodRecognitionCategory.category(for: "unsupported label") == .other)
    }

    @Test func correctionsRequireQuantityStorageAndPersistPhotoWithoutDuplicates() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let photos = FoodPhotoStorage(root: root)
        let url = root.appendingPathComponent("inventory.sqlite")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = PersistenceController(storeURL: url)
        await store.load()
        let repository = PantryRepository(container: try #require(store.container), photos: photos)
        let pantry = PantryViewModel(repository: repository)
        let model = AddFoodViewModel(recognizedName: "Apple", category: .fruits,
                                     photoData: try FoodPhotoStorage.prepare(photo()), photos: photos, save: pantry.createFood)
        #expect(model.quantityText.isEmpty && model.draft.storageLocation.isEmpty && !model.includesExpiry)
        #expect(pantry.itemCount == 0 && !model.save())
        model.draft.name = "Pear"
        model.quantityText = "2"
        #expect(!model.save())
        model.draft.storageLocation = "Fridge"
        #expect(model.save())
        #expect(!model.save())
        let item = try #require(model.savedItem)
        #expect(item.name == "Pear" && item.quantity == 2 && item.expiryDate == nil && item.barcode == nil)
        #expect(pantry.itemCount == 1)
        #expect(try photos.load(#require(item.imagePath)).count > 0)
        let reopened = PersistenceController(storeURL: url)
        await reopened.load()
        let reader = PantryRepository(container: try #require(reopened.container), photos: photos)
        #expect(try reader.fetchAll().count == 1)
        #expect(try reader.fetchAll().first?.name == "Pear")
    }

    @Test func cancellationAndPhotoChangeDiscardLatePredictions() async throws {
        let service = DelayedRecognition()
        let model = FoodRecognitionViewModel(service: service)
        model.recognize(Data([1]))
        model.recognize(Data([1]))
        try await Task.sleep(for: .milliseconds(20))
        model.reset()
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.result == nil && !model.isRecognizing && model.errorMessage == nil)
        #expect(await service.calls == 1)
    }
}

private actor DelayedRecognition: FoodRecognizing {
    var calls = 0
    func recognize(_ imageData: Data) async throws -> FoodRecognitionResult {
        calls += 1
        try? await Task.sleep(for: .milliseconds(100))
        return .init(predictions: [.init(label: "Apple", confidence: 0.8)], supportedLabels: ["Apple"])
    }
}

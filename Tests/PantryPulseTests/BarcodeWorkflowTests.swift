import AVFoundation
import CoreData
import Testing
import UIKit
@testable import PantryPulse

@MainActor
struct BarcodeWorkflowTests {
    private var product: ProductLookupResult {
        ProductLookupResult(barcode: "0012345678905", name: "Milk", brand: "Farm", quantityText: "500 ml",
                            categoryText: "Dairy", categoryTags: ["en:dairies"], imageURL: nil)
    }

    @Test func productDraftRequiresUserQuantityAndPreservesMetadata() {
        let draft = product.makeDraft()
        #expect(draft.name == "Milk" && draft.barcode == "0012345678905")
        #expect(draft.category == .dairy && draft.expiryDate == nil)
        #expect(draft.quantity == 0 && draft.notes?.contains("500 ml") == true)
        #expect(draft.notes?.contains("Open Food Facts contributors") == true)
        let partial = ProductLookupResult(barcode: "12345678", name: nil, brand: nil, quantityText: nil,
                                          categoryText: nil, categoryTags: [], imageURL: nil)
        #expect(partial.makeDraft().name.isEmpty && partial.suggestedCategory == nil)
    }

    @Test func confirmedProductPersistsUpdatesPantryAndDashboardWithoutDuplicates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.sqlite")
        let storage = FoodPhotoStorage(root: directory)
        let store = PersistenceController(storeURL: url)
        await store.load()
        let repository = PantryRepository(container: try #require(store.container), photos: storage)
        let pantry = PantryViewModel(repository: repository)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { context in
            UIColor.orange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
        let data = try FoodPhotoStorage.prepare(try #require(image.pngData()))
        let form = AddFoodViewModel(product: product, photoData: data, photos: storage, save: pantry.createFood)
        #expect(form.quantityText.isEmpty && !form.includesExpiry)
        #expect(!form.save() && pantry.itemCount == 0)
        form.quantityText = "2"
        form.draft.quantityUnit = .bottles
        form.draft.name = "My milk"
        #expect(form.save())
        #expect(!form.save())
        #expect(pantry.itemCount == 1 && pantry.unknownExpiryCount == 1)
        let saved = try #require(form.savedItem)
        #expect(saved.name == "My milk" && saved.barcode == product.barcode && saved.expiryDate == nil)
        #expect(saved.quantity == 2 && saved.quantityUnit == .bottles)
        let path = try #require(saved.imagePath)
        #expect(!path.hasPrefix("https:") && !path.hasPrefix("/"))
        #expect(try storage.load(path).count > 0)
        let reopened = PersistenceController(storeURL: url)
        await reopened.load()
        let reader = PantryRepository(container: try #require(reopened.container), photos: storage)
        #expect(try reader.fetch(id: saved.id)?.imagePath == path)
        #expect(try reader.fetchAll().count == 1)
    }

    @Test func repeatedLookupAndCancellationDoNotPublishLateSuccess() async throws {
        let service = DelayedProductService(product: product)
        let model = BarcodeLookupModel(service: service)
        model.barcode = product.barcode
        model.lookup(); model.lookup()
        let task = model.task
        await Task.yield()
        model.reset()
        await task?.value
        #expect(model.state == .idle && model.imageData == nil)
        #expect(await service.calls <= 1)
    }

    @Test func lookupSuccessPartialDataAndImageFailureRemainEditable() async throws {
        let photoProduct = ProductLookupResult(barcode: product.barcode, name: nil, brand: nil, quantityText: nil,
                                              categoryText: nil, categoryTags: [], imageURL: URL(string: "https://example.com/photo.jpg"))
        let model = BarcodeLookupModel(service: ImmediateProductService(product: photoProduct), images: FailedImageLoader())
        model.lookup(photoProduct.barcode)
        await model.task?.value
        #expect(model.state == .found(photoProduct))
        #expect(model.imageData == nil && model.imageError != nil && !model.isLoadingImage)
        let store = PersistenceController(inMemory: true)
        await store.load()
        let repository = PantryRepository(container: try #require(store.container))
        let form = AddFoodViewModel(product: photoProduct, photoData: nil, save: repository.create)
        form.quantityText = "1"
        #expect(!form.save())
        form.draft.name = "Label entered by user"
        #expect(form.save())
        #expect(try repository.fetchAll().count == 1)
    }

    @Test func lookupErrorsSurfaceAndRetryUsesNewInput() async {
        let model = BarcodeLookupModel(service: FailedProductService())
        model.lookup("12345678")
        await model.task?.value
        #expect(model.state == .networkUnavailable(ProductLookupError.network(.notConnectedToInternet).localizedDescription))
        model.reset()
        #expect(model.state == .idle)
    }

    @Test func cameraUnavailableAndDeniedNeverStartCapture() async {
        for available in [false, true] {
            let spy = CaptureSpy()
            let camera = BarcodeCameraModel(driver: spy, available: { available }, authorization: { .denied }, requestPermission: {
                Issue.record("Permission should not be requested"); return true
            })
            await camera.start { _ in Issue.record("No detection expected") }
            #expect(camera.state == (available ? .denied : .unavailable))
            #expect(spy.startCount == 0)
        }
    }

    @Test func cameraFirstDetectionStopsAndIgnoresRepeatsAndLateCallbacks() async throws {
        let spy = CaptureSpy()
        let camera = BarcodeCameraModel(driver: spy, available: { true }, authorization: { .authorized })
        var codes: [String] = []
        await camera.start { codes.append($0) }
        spy.emit(.detected("0123456789012", symbology: "EAN13"))
        spy.emit(.detected("0123456789012", symbology: "EAN13"))
        for _ in 0..<100 where codes.isEmpty { await Task.yield() }
        #expect(codes == ["0123456789012"])
        #expect(camera.detectedSymbology == "EAN13")
        #expect(camera.state == .paused && spy.stopCount >= 2)
        await camera.start { codes.append($0) }
        camera.stop() // The view calls this on dismissal, tab changes and inactive scene transitions.
        spy.emit(.detected("99999999"))
        for _ in 0..<10 { await Task.yield() }
        #expect(camera.state == .idle && codes.count == 1)
    }

    @Test func leavingDuringPermissionPromptCannotStartCameraLater() async {
        let spy = CaptureSpy()
        var continuation: CheckedContinuation<Bool, Never>?
        let camera = BarcodeCameraModel(driver: spy, available: { true }, authorization: { .notDetermined }, requestPermission: {
            await withCheckedContinuation { continuation = $0 }
        })
        let task = Task { await camera.start { _ in Issue.record("No detection expected") } }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        camera.stop()
        continuation?.resume(returning: true)
        await task.value
        #expect(spy.startCount == 0 && camera.state == .idle)
    }
}

private nonisolated struct ImmediateProductService: ProductLookupService {
    let product: ProductLookupResult
    func lookup(barcode: String) async throws -> ProductLookupResult { product }
}
private actor DelayedProductService: ProductLookupService {
    let product: ProductLookupResult
    var calls = 0
    init(product: ProductLookupResult) { self.product = product }
    func lookup(barcode: String) async throws -> ProductLookupResult {
        calls += 1
        // Return even on cancellation to verify that stale results are rejected by the caller.
        try? await Task.sleep(for: .milliseconds(30))
        return product
    }
}
private nonisolated struct FailedProductService: ProductLookupService {
    func lookup(barcode: String) async throws -> ProductLookupResult { throw ProductLookupError.network(.notConnectedToInternet) }
}
private nonisolated struct FailedImageLoader: ProductImageLoading {
    func load(_ url: URL) async throws -> Data { throw FoodPhotoError.invalidImage }
}
private nonisolated final class CaptureSpy: BarcodeCaptureDriving, @unchecked Sendable {
    private let lock = NSLock()
    private var starts = 0
    private var stops = 0
    private var handler: (@Sendable (BarcodeCaptureEvent) -> Void)?
    var startCount: Int { lock.withLock { starts } }
    var stopCount: Int { lock.withLock { stops } }
    func start(handler: @escaping @Sendable (BarcodeCaptureEvent) -> Void) { lock.withLock { starts += 1; self.handler = handler } }
    func stop() { lock.withLock { stops += 1 } }
    func setTorch(_ enabled: Bool) {}
    func emit(_ event: BarcodeCaptureEvent) { lock.withLock { handler }?(event) }
}

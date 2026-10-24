import Foundation
import CoreData
import Testing
import Vision
import UIKit
@testable import PantryPulse

@MainActor
struct ProductIdentificationTests {
    private func catalogue() -> ProductCatalogue {
        ProductCatalogue(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Products.json"))
    }
    private func product(_ code: String, name: String = "Confirmed packaging fixture") -> ProductLookupResult {
        ProductLookupResult(barcode: code, name: name, brand: nil, quantityText: nil, categoryText: nil, categoryTags: [], imageURL: nil, symbology: "Code128", usesOpenFoodFactsAttribution: false)
    }
    @Test func scannerFormats() {
        #expect(BarcodeCapture.supportedSymbologies == [.ean13, .ean8, .upce, .code128, .itf14])
    }
    @Test(arguments: ["00310062004566", "00310120003586", "00310115004826", "00310123003966", "ordinary-code"])
    func opaqueLabelsNeverInventMatches(_ raw: String) async throws {
        let scan = ScannedBarcode(rawValue: raw, symbology: "Code128")
        #expect(try scan.identity().key == "opaque:" + raw)
        #expect(try scan.identity().globalCode == nil)
        await #expect(throws: ProductLookupError.productNotFound) {
            try await ProductIdentificationService(catalogue: catalogue(), primary: UnexpectedProvider()).lookup(scan: scan)
        }
    }
    @Test(arguments: ["4792212012129", "4797777001229", "6294002420919", "3017620422003"])
    func validEANPreservesRaw(_ raw: String) async throws {
        let result = try await ProductIdentificationService(catalogue: catalogue(), primary: EchoProvider()).lookup(scan: ScannedBarcode(rawValue: raw, symbology: "EAN13"))
        #expect(result.barcode == raw)
    }
    @Test func checksumAndCanonicalIdentity() throws {
        #expect(throws: ProductLookupError.invalidBarcode) { try ScannedBarcode(rawValue: "4792212012128", symbology: "EAN13").identity() }
        #expect(throws: ProductLookupError.invalidBarcode) { try ScannedBarcode(rawValue: "00310062004566", symbology: "EAN13").identity() }
        #expect(try ScannedBarcode(rawValue: "034000470693", symbology: "UPCA").identity().key == ScannedBarcode(rawValue: "0034000470693", symbology: "EAN13").identity().key)
        #expect(try GTIN.expandUPCE("04252614") == "042100005264")
    }
    @Test func providerFailureAndOptionalFallback() async throws {
        let scan = ScannedBarcode(rawValue: "3017620422003", symbology: "EAN13")
        await #expect(throws: ProductLookupError.network(.notConnectedToInternet)) {
            try await ProductIdentificationService(catalogue: catalogue(), primary: OfflineProvider()).lookup(scan: scan)
        }
        let result = try await ProductIdentificationService(catalogue: catalogue(), primary: OfflineProvider(), additionalProviders: [EchoProvider()]).lookup(scan: scan)
        #expect(result.barcode == scan.rawValue)
    }
    @Test func confirmationPersistsInventoryAndReusableMetadataSeparately() async throws {
        let store = PersistenceController(inMemory: true)
        await store.load()
        let repository = PantryRepository(container: try #require(store.container))
        let cache = catalogue()
        defer { try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent()) }
        var input = product("00310062004566", name: "Brinjals")
        input.pantryCategory = "Vegetables"
        input.suggestedQuantity = LabelQuantity(value: 0.456, unit: "kg")
        let form = AddFoodViewModel(product: input, photoData: nil, catalogue: cache, save: repository.create)
        #expect(form.save())
        #expect(!form.save())
        let saved = try #require(repository.fetchAll().first)
        #expect(saved.quantity == 0.456 && saved.quantityUnit == .kilograms)
        #expect(saved.barcode == input.barcode && saved.expiryDate == nil)
        #expect(try repository.fetchAll().count == 1)
        let result = try await ProductIdentificationService(catalogue: ProductCatalogue(url: cache.url), primary: UnexpectedProvider()).lookup(scan: ScannedBarcode(rawValue: input.barcode, symbology: "Code128"))
        #expect(result.name == "Brinjals" && result.quantityText == nil && result.suggestedQuantity == nil)
        #expect(result.makeDraft().quantity == 0 && result.makeDraft().expiryDate == nil)
    }
    @Test func verifiedFixturesAreLocalOnlyAndCannotBeDowngraded() throws {
        let cache = catalogue()
        defer { try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent()) }
        // User-supplied exact-barcode retail evidence, never production seeds or live API results.
        for (code, name, size, category) in [("4792212012129", "Edinborough Mayonnaise", "360 g", "Grains & Pantry"), ("4797777001229", "Richlife Kiripani", "500 g", "Dairy")] {
            let scan = ScannedBarcode(rawValue: code, symbology: "EAN13")
            func record(_ confidence: ProductConfidence, _ name: String) throws -> CatalogueProduct {
                CatalogueProduct(key: try scan.identity().key, barcode: code, symbology: "EAN13", name: name, brand: nil, category: category, packageQuantity: size, imageReference: nil, source: "User-supplied retail listing fixture", evidenceURL: nil, usesOpenFoodFactsAttribution: false, confidence: confidence, updatedAt: Date())
            }
            try cache.save(record(.verified, name))
            #expect(try !cache.save(record(.suggested, "Unverified guess")))
            #expect(try ProductCatalogue(url: cache.url).lookup(scan)?.name == name)
        }
        #expect(try cache.lookup(ScannedBarcode(rawValue: "6294002420919", symbology: "EAN13")) == nil)
    }
    @Test(arguments: [("500 g", 500.0, "g"), ("360 g", 360.0, "g"), ("0.456 kg", 0.456, "kg"), ("1 L", 1.0, "L"), ("250 ml", 250.0, "ml")])
    func printedQuantities(_ value: (String, Double, String)) {
        #expect(ProductLabelOCR.quantity(in: value.0) == LabelQuantity(value: value.1, unit: value.2))
    }
    @Test func suggestionsRejectDatesNutritionAndLowConfidence() {
        let result = ProductLabelOCR.suggestions(from: [LabelText(text: "BRINJALS", confidence: 0.95), LabelText(text: "0.456 kg", confidence: 0.95), LabelText(text: "16-OCT-2026", confidence: 0.95), LabelText(text: "Brand: Guess", confidence: 0.2)])
        #expect(result.name == "Brinjals" && result.category == "Vegetables" && result.brand == nil)
        #expect(result.quantity == LabelQuantity(value: 0.456, unit: "kg"))
        #expect(ProductLabelOCR.quantity(in: "Protein 17 g") == nil)
        #expect(ProductLabelOCR.quantity(in: "16-OCT-2026") == nil)
    }
    @Test func failedInventorySaveDoesNotCreateCatalogueEntry() throws {
        let cache = catalogue()
        let input = product("00310062004566", name: "Brinjals")
        let form = AddFoodViewModel(product: input, photoData: nil, catalogue: cache, save: { _ in throw PantryRepositoryError.invalidRecord })
        form.quantityText = "1"
        #expect(!form.save())
        #expect(form.errorMessage != nil)
        #expect(try cache.lookup(ScannedBarcode(rawValue: input.barcode, symbology: "Code128")) == nil)
    }
    @Test func cataloguePhotoSurvivesPantryPhotoDeletion() async throws {
        let cache = catalogue()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: cache.url.deletingLastPathComponent()) }
        let photos = FoodPhotoStorage(root: root)
        let store = PersistenceController(inMemory: true)
        await store.load()
        let repo = PantryRepository(container: try #require(store.container))
        let data = try #require(UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40)).image { context in
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 40))
        }.pngData())
        let input = product("00310062004566", name: "Brinjals")
        let form = AddFoodViewModel(product: input, photoData: data, photos: photos, catalogue: cache, save: repo.create)
        form.quantityText = "1"
        #expect(form.save())
        let saved = try #require(form.savedItem)
        try photos.remove(#require(saved.imagePath))
        let result = try #require(try ProductCatalogue(url: cache.url).lookup(ScannedBarcode(rawValue: input.barcode, symbology: "Code128")))
        #expect(UIImage(data: try #require(result.localImageData)) != nil)
    }
    @Test func exactSearchEvidenceIsOnlyASuggestion() async throws {
        let scan = ScannedBarcode(rawValue: "00310062004566", symbology: "Code128")
        let candidate = ProductSearchCandidate(product: product(scan.rawValue, name: "Brinjals"), evidenceURL: URL(string: "https://example.com/product")!, evidenceText: "Brinjals 00310062004566")
        let result = try await ProductIdentificationService(catalogue: catalogue(), primary: UnexpectedProvider(), search: SearchFixture(value: candidate)).lookup(scan: scan)
        #expect(result.isSuggestion && !result.usesOpenFoodFactsAttribution)
        let mismatch = ProductSearchCandidate(product: candidate.product, evidenceURL: candidate.evidenceURL, evidenceText: "Brinjals 003100620045660")
        await #expect(throws: ProductLookupError.productNotFound) {
            try await ProductIdentificationService(catalogue: catalogue(), primary: UnexpectedProvider(), search: SearchFixture(value: mismatch)).lookup(scan: scan)
        }
    }
    @Test func ocrReadsTextAndRejectsCorruptPhoto() async throws {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 300)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 300))
            ("GREEN BEANS" as NSString).draw(at: CGPoint(x: 50, y: 70), withAttributes: [.font: UIFont.systemFont(ofSize: 70), .foregroundColor: UIColor.black])
        }
        let data = try #require(image.pngData())
        let lines = try await Task.detached { try ProductLabelOCR.recognize(data) }.value
        #expect(lines.contains { $0.uppercased().contains("GREEN BEANS") })
        #expect(throws: (any Error).self) { try ProductLabelOCR.recognize(Data("invalid".utf8)) }
    }
}
private nonisolated struct UnexpectedProvider: ProductLookupService {
    func lookup(barcode: String) async throws -> ProductLookupResult {
        Issue.record("Opaque or confirmed local barcode must not call the global provider")
        throw ProductLookupError.productNotFound
    }
}
private nonisolated struct EchoProvider: ProductLookupService {
    func lookup(barcode: String) async throws -> ProductLookupResult {
        ProductLookupResult(barcode: barcode, name: "HTTP fixture", brand: nil, quantityText: nil, categoryText: nil, categoryTags: [], imageURL: nil)
    }
}
private nonisolated struct OfflineProvider: ProductLookupService {
    func lookup(barcode: String) async throws -> ProductLookupResult { throw ProductLookupError.network(.notConnectedToInternet) }
}

private nonisolated struct SearchFixture: BarcodeCandidateSearching {
    let value: ProductSearchCandidate
    func candidate(for barcode: String) async throws -> ProductSearchCandidate? { value }
}

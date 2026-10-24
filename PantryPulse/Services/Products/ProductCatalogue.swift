import Foundation

nonisolated enum ProductConfidence: Int, Codable, Sendable { case suggested, provider, confirmed, verified }

nonisolated struct CatalogueProduct: Codable, Equatable, Sendable {
    let key: String
    let barcode: String
    let symbology: String
    let name: String
    let brand: String?
    let category: String
    let packageQuantity: String?
    var imageReference: String?
    let source: String
    let evidenceURL: URL?
    let usesOpenFoodFactsAttribution: Bool
    let confidence: ProductConfidence
    let updatedAt: Date
}

/// Barcode-keyed metadata, independent of inventory and its photo cleanup journal.
/// All read/modify/write operations are serialized and writes are atomic.
nonisolated struct ProductCatalogue: Sendable {
    let url: URL
    private static let lock = NSLock()
    static var defaultURL: URL {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if let suite = env["PANTRYPULSE_UI_TEST_DEFAULTS"], suite.hasPrefix("PantryPulse.UITests."),
           let id = UUID(uuidString: String(suite.dropFirst("PantryPulse.UITests.".count))) {
            return FileManager.default.temporaryDirectory.appendingPathComponent("Catalogue-\(id.uuidString)/Products.json")
        }
        if env["XCTestConfigurationFilePath"] != nil || env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return FileManager.default.temporaryDirectory.appendingPathComponent("Catalogue-tests-\(ProcessInfo.processInfo.processIdentifier)/Products.json")
        }
        #endif
        return URL.applicationSupportDirectory.appendingPathComponent("ProductCatalogue/Products.json")
    }
    init(url: URL = defaultURL) { self.url = url }

    func lookup(_ scan: ScannedBarcode) throws -> ProductLookupResult? {
        let key = try scan.identity().key
        return try Self.lock.withLock {
            guard let record = try records().first(where: { $0.key == key && $0.confidence.rawValue >= ProductConfidence.confirmed.rawValue }) else { return nil }
            var image: Data?
            if let reference = record.imageReference, let location = photoURL(reference), FileManager.default.fileExists(atPath: location.path) {
                // A missing catalogue photo must not discard usable product metadata.
                image = try? Data(contentsOf: location)
            }
            return ProductLookupResult(barcode: scan.rawValue, name: record.name, brand: record.brand,
                quantityText: record.packageQuantity, categoryText: record.category, categoryTags: [], imageURL: nil,
                symbology: scan.symbology, pantryCategory: record.category,
                dataSource: "Confirmed local catalogue · " + record.source, evidenceURL: record.evidenceURL,
                usesOpenFoodFactsAttribution: record.usesOpenFoodFactsAttribution, localImageData: image)
        }
    }

    /// Returns false when a lower-confidence update was intentionally refused.
    @discardableResult
    func save(_ record: CatalogueProduct, photoData: Data? = nil) throws -> Bool {
        try Self.lock.withLock {
            var all = try records()
            if let old = all.first(where: { $0.key == record.key }), old.confidence.rawValue > record.confidence.rawValue { return false }
            guard !record.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  record.key == (try ScannedBarcode(rawValue: record.barcode, symbology: record.symbology).identity().key) else { throw CatalogueError.invalidRecord }
            var record = record
            let oldImage = all.first(where: { $0.key == record.key })?.imageReference
            var newImage: URL?
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                if let photoData {
                    let filename = UUID().uuidString + ".jpg"
                    let location = url.deletingLastPathComponent().appendingPathComponent(filename)
                    newImage = location
                    try FoodPhotoStorage.prepare(photoData).write(to: location, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                    record.imageReference = filename
                } else { record.imageReference = nil }
                all.removeAll { $0.key == record.key }
                all.append(record)
                try JSONEncoder().encode(all).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            } catch {
                if let newImage, FileManager.default.fileExists(atPath: newImage.path) { try FileManager.default.removeItem(at: newImage) }
                throw error
            }
            // Never touch pantry photos or a file referenced by another catalogue entry.
            if let oldImage, oldImage != record.imageReference, !all.contains(where: { $0.imageReference == oldImage }),
               let location = photoURL(oldImage), FileManager.default.fileExists(atPath: location.path) {
                try FileManager.default.removeItem(at: location)
            }
            return true
        }
    }
    private func photoURL(_ reference: String) -> URL? {
        guard reference.hasSuffix(".jpg"), UUID(uuidString: String(reference.dropLast(4))) != nil else { return nil }
        return url.deletingLastPathComponent().appendingPathComponent(reference)
    }
    private func records() throws -> [CatalogueProduct] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([CatalogueProduct].self, from: Data(contentsOf: url))
    }
}

nonisolated enum CatalogueError: LocalizedError {
    case invalidRecord
    var errorDescription: String? { "The product catalogue entry has an invalid name or barcode identity." }
}

import Foundation

nonisolated struct LabelQuantity: Equatable, Sendable {
    let value: Double
    let unit: String
    var text: String { "\(value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")))) \(unit)" }
}

/// Provider/catalogue metadata and optional unconfirmed OCR input. Never a saved pantry item.
nonisolated struct ProductLookupResult: Equatable, Sendable {
    var barcode: String
    var name: String?
    var brand: String?
    var quantityText: String?
    var categoryText: String?
    var categoryTags: [String]
    var imageURL: URL?
    var symbology: String = ""
    var pantryCategory: String? = nil
    var suggestedQuantity: LabelQuantity? = nil
    var dataSource: String? = nil
    var evidenceURL: URL? = nil
    var usesOpenFoodFactsAttribution = true
    var isSuggestion = false
    var localImageData: Data? = nil
}

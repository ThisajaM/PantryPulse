import Foundation

extension ProductLookupResult {
    /// Conservative taxonomy suggestions; the user can always choose a different pantry category.
    var suggestedCategory: FoodCategory? {
        if let pantryCategory { return FoodCategory(rawValue: pantryCategory) }
        let tags = Set(categoryTags)
        let matches: [(FoodCategory, Set<String>)] = [
            (.dairy, ["en:dairies", "en:milks", "en:cheeses", "en:yogurts"]),
            (.fruits, ["en:fruits", "en:fresh-fruits"]),
            (.vegetables, ["en:vegetables", "en:fresh-vegetables"]),
            (.bakery, ["en:breads", "en:bakery-products"]),
            (.snacks, ["en:snacks"]),
            (.meatSeafood, ["en:meats", "en:seafoods"]),
            (.grainsPantry, ["en:condiments", "en:sauces", "en:cereals", "en:mayonnaises"]),
            (.beverages, ["en:beverages"])
        ]
        return matches.first { !$0.1.isDisjoint(with: tags) }?.0
    }

    var sourceURL: URL? {
        if let evidenceURL { return evidenceURL }
        guard usesOpenFoodFactsAttribution else { return nil }
        return URL(string: "https://world.openfoodfacts.org/product/\(barcode)")
    }

    func makeDraft() -> FoodDraft {
        var draft = FoodDraft(name: name ?? "")
        draft.barcode = barcode
        draft.category = suggestedCategory ?? .other
        if let suggestedQuantity, let unit = QuantityUnit(rawValue: suggestedQuantity.unit) { draft.quantityUnit = unit }
        draft.quantity = suggestedQuantity?.value ?? 0 // Only explicitly accepted label text supplies a quantity suggestion.
        draft.expiryDate = nil
        draft.notes = [dataSource, brand.map { "Brand: \($0)" }, quantityText.map { "Package: \($0)" },
                       sourceURL.map { "Source: \($0.absoluteString)" + (usesOpenFoodFactsAttribution ? " — Open Food Facts contributors (ODbL; images CC BY-SA)." : "") }]
            .compactMap { $0 }.joined(separator: "\n")
        return draft
    }
}

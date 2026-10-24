import Foundation

// Raw values are persisted; changing them requires a data migration.
enum FoodCategory: String, CaseIterable, Identifiable {
    case fruits = "Fruits", vegetables = "Vegetables", dairy = "Dairy"
    case bakery = "Bakery", snacks = "Snacks", other = "Other"
    case meatSeafood = "Meat & Seafood", grainsPantry = "Grains & Pantry", beverages = "Beverages"
    var id: Self { self }
}

enum QuantityUnit: String, CaseIterable, Identifiable {
    case pieces, grams = "g", kilograms = "kg", millilitres = "ml", litres = "L"
    case bottles, packs, cans, loaves
    var id: Self { self }
}

enum PantryItemStatus: String, CaseIterable {
    case active, consumed, wasted, archived
}

enum PantryFetchSort {
    case expirySoonest, createdNewest, createdOldest
}

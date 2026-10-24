import Foundation

/// Inventory value, independent of Core Data's generated `PantryItemRecord` type.
/// Managed objects never leave the repository; preview metadata may be absent.
struct PantryItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var category: FoodCategory = .other
    var quantityDescription: String? = nil
    var storageLocation: String? = nil
    var imageAssetName: String? = nil
    var expiryDate: Date? = nil
    var addedAt: Date? = nil
    var quantity: Double? = nil
    var quantityUnit: QuantityUnit? = nil
    var purchaseDate: Date? = nil
    var imagePath: String? = nil
    var notes: String? = nil
    var barcode: String? = nil
    var updatedAt: Date? = nil
    var status: PantryItemStatus = .active

    var createdAt: Date? { addedAt }
}

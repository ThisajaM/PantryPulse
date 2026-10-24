import Foundation

/// Cloud schema excludes device-only image paths and UI preview metadata.
struct CloudPantryDocument: Codable, Equatable {
    let schemaVersion: Int
    let ownerID: String
    let id: String
    let name: String
    let category: String
    let quantity: Double
    let quantityUnit: String
    let purchaseDate: Date
    let expiryDate: Date?
    let storageLocation: String
    let notes: String?
    let barcode: String?
    let createdAt: Date
    let updatedAt: Date
    let status: String

    init(item: PantryItem, ownerID: String) throws {
        let draft = try FoodDraft(item: item).validated()
        guard !ownerID.isEmpty, let created = item.createdAt, let updated = item.updatedAt,
              updated >= created else { throw CloudPantryError.invalidDocument }
        schemaVersion = 1
        self.ownerID = ownerID
        id = item.id.uuidString
        name = draft.name
        category = draft.category.rawValue
        quantity = draft.quantity
        quantityUnit = draft.quantityUnit.rawValue
        purchaseDate = draft.purchaseDate
        expiryDate = draft.expiryDate
        storageLocation = draft.storageLocation
        notes = draft.notes
        barcode = draft.barcode
        createdAt = created
        updatedAt = updated
        status = draft.status.rawValue
    }
}


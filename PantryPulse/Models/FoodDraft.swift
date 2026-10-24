import Foundation

/// Keep the same draft ID when retrying a save. A new draft represents a separate food item.
struct FoodDraft: Equatable {
    let id: UUID
    var name: String
    var category: FoodCategory = .other
    var quantity: Double = 1
    var quantityUnit: QuantityUnit = .pieces
    var purchaseDate: Date = Date()
    var expiryDate: Date? = nil
    var storageLocation: String = "Pantry"
    var imagePath: String? = nil
    var notes: String? = nil
    var barcode: String? = nil
    var status: PantryItemStatus = .active

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    init(item: PantryItem) throws {
        guard let quantity = item.quantity, let unit = item.quantityUnit,
              let purchased = item.purchaseDate, let location = item.storageLocation else {
            throw PantryRepositoryError.invalidRecord
        }
        self.init(id: item.id, name: item.name)
        category = item.category
        self.quantity = quantity
        quantityUnit = unit
        purchaseDate = purchased
        expiryDate = item.expiryDate
        storageLocation = location
        imagePath = item.imagePath
        notes = item.notes
        barcode = item.barcode
        status = item.status
    }

    func validated() throws -> FoodDraft {
        var result = self
        result.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.name.isEmpty else { throw FoodValidationError.emptyName }
        guard quantity.isFinite, quantity > 0 || (quantity == 0 && (status == .consumed || status == .wasted)) else { throw FoodValidationError.invalidQuantity }
        result.storageLocation = storageLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.storageLocation.isEmpty else { throw FoodValidationError.emptyStorage }
        result.notes = Self.clean(notes)
        result.barcode = Self.clean(barcode)
        result.imagePath = Self.clean(imagePath)
        return result
    }

    private static func clean(_ text: String?) -> String? {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}

enum FoodValidationError: LocalizedError, Equatable {
    case emptyName, invalidQuantity, emptyStorage
    var errorDescription: String? {
        switch self {
        case .emptyName: "Enter a food name."
        case .invalidQuantity: "Quantity must be a finite number greater than zero."
        case .emptyStorage: "Enter a storage location."
        }
    }
}

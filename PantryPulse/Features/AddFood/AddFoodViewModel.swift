import Foundation
import Observation

@MainActor
@Observable
final class AddFoodViewModel {
    var draft = FoodDraft(name: "")
    var quantityText = "1"
    var includesExpiry = false
    var expiryDate = Date()
    var notes = ""
    var errorMessage: String?
    var catalogueWarning: String?
    var productBrand = ""
    var packageQuantity = ""
    private(set) var identification: ProductLookupResult?
    private var catalogue = ProductCatalogue()
    let photoSelection = FoodPhotoSelectionState()
    var photoData: Data?
    var isLoadingPhoto = false
    var removedPhoto = false
    private let photos: FoodPhotoStorage

    func removePhoto() {
        photoData = nil
        removedPhoto = true
    }

    func selectPhoto(_ data: Data) {
        photoData = data
        removedPhoto = false
    }
    private(set) var isSaving = false
    private(set) var savedItem: PantryItem?
    private let saveFood: (FoodDraft) throws -> PantryItem
    private let locale: Locale

    init(draft: FoodDraft? = nil, locale: Locale = .current, photos: FoodPhotoStorage = FoodPhotoStorage(), save: @escaping (FoodDraft) throws -> PantryItem) {
        let draft = draft ?? FoodDraft(name: "")
        self.draft = draft
        let quantity = String(draft.quantity)
        quantityText = (quantity.hasSuffix(".0") ? String(quantity.dropLast(2)) : quantity)
            .replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
        includesExpiry = draft.expiryDate != nil
        expiryDate = draft.expiryDate ?? Date()
        notes = draft.notes ?? ""
        self.locale = locale
        self.photos = photos
        self.saveFood = save
    }

    convenience init(product: ProductLookupResult, photoData: Data?, photos: FoodPhotoStorage = FoodPhotoStorage(), catalogue: ProductCatalogue = ProductCatalogue(),
                     save: @escaping (FoodDraft) throws -> PantryItem) {
        self.init(draft: product.makeDraft(), photos: photos, save: save)
        identification = product
        self.catalogue = catalogue
        productBrand = product.brand ?? ""
        packageQuantity = product.quantityText ?? ""
        notes = ""
        if product.suggestedQuantity == nil { quantityText = "" }
        if let photoData { selectPhoto(photoData) }
    }

    convenience init(recognizedName: String, category: FoodCategory, photoData: Data?,
                     photos: FoodPhotoStorage = FoodPhotoStorage(), save: @escaping (FoodDraft) throws -> PantryItem) {
        var draft = FoodDraft(name: recognizedName)
        draft.category = category
        draft.storageLocation = ""
        self.init(draft: draft, photos: photos, save: save)
        quantityText = ""
        if let photoData { selectPhoto(photoData) }
    }

    /// The draft identity survives validation errors and persistence retries.
    func save() -> Bool {
        guard !isSaving, !isLoadingPhoto, savedItem == nil else { return false }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        var newPhotoPath: String?
        do {
            var input = draft
            let text = quantityText.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: locale.decimalSeparator ?? ".", with: ".")
            guard let quantity = Double(text) else { throw FoodValidationError.invalidQuantity }
            input.quantity = quantity
            input.expiryDate = includesExpiry ? expiryDate : nil
            input.notes = notes
            if var product = identification {
                product.barcode = input.barcode ?? product.barcode
                _ = try ScannedBarcode(rawValue: product.barcode, symbology: product.symbology).identity()
                product.brand = productBrand.isEmpty ? nil : productBrand
                product.quantityText = packageQuantity.isEmpty ? nil : packageQuantity
                input.notes = [notes, product.makeDraft().notes ?? ""].filter { !$0.isEmpty }.joined(separator: "\n")
            }
            input = try input.validated()
            if let photoData {
                newPhotoPath = try photos.save(photoData)
                input.imagePath = newPhotoPath
            } else if removedPhoto {
                input.imagePath = nil
            }
            savedItem = try saveFood(input)
            if let product = identification, let barcode = input.barcode {
                do {
                    let key = try ScannedBarcode(rawValue: barcode, symbology: product.symbology).identity().key
                    let record = CatalogueProduct(key: key, barcode: barcode, symbology: product.symbology,
                        name: input.name, brand: productBrand.isEmpty ? nil : productBrand,
                        category: input.category.rawValue, packageQuantity: packageQuantity.isEmpty ? nil : packageQuantity,
                        imageReference: nil, source: product.dataSource ?? "Open Food Facts contributors",
                        evidenceURL: product.sourceURL, usesOpenFoodFactsAttribution: product.usesOpenFoodFactsAttribution,
                        confidence: .confirmed, updatedAt: Date())
                    if try !catalogue.save(record, photoData: removedPhoto ? nil : photoData) {
                        catalogueWarning = "Your food was saved. An existing verified catalogue record was retained instead of replacing it with these details."
                    }
                } catch {
                    catalogueWarning = "Your food was saved, but the reusable catalogue could not be fully updated: " + error.localizedDescription
                }
            }
            return true
        } catch let error as FoodValidationError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Your food could not be saved. Your entries are still here. Please try again.\n\n" + error.localizedDescription
        }
        if let newPhotoPath {
            do { try photos.remove(newPhotoPath) }
            catch { errorMessage = (errorMessage ?? "Unable to save food.") + "\nPhoto cleanup will be retried when the pantry reloads: " + error.localizedDescription }
        }
        return false
    }
}

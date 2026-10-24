import SwiftUI

/// One editable fallback for every barcode. Text recognition supplies suggestions, not verified matches.
struct ProductLabelConfirmationView: View {
    @Environment(\.accountResources) private var resources
    let scan: ScannedBarcode
    let startWithPhoto: Bool
    let save: (FoodDraft) throws -> PantryItem
    let onSaved: () -> Void
    @FocusState private var fieldFocused: Bool
    @State private var name = ""
    @State private var brand = ""
    @State private var labelQuantity = ""
    @State private var reusablePackageSize = false
    @State private var useQuantity = false
    @State private var category: FoodCategory = .other
    @State private var error: String?
    @State private var showingForm = false
    @State private var showPhoto = false
    @State private var recognizing = false
    @State private var usedOCR = false
    @State private var lines: [String] = []
    @State private var photoModel = AddFoodViewModel(save: { _ in throw PantryRepositoryError.invalidRecord })
    @State private var ocrTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                Text("Product details need confirmation.")
                LabeledContent("Barcode", value: scan.rawValue)
                Text("Confirm details from the packaging. No expiry date will be inferred.")
            }
            Section("Product details") {
                TextField("Product name", text: $name).focused($fieldFocused).accessibilityIdentifier("label.name")
                TextField("Brand (optional)", text: $brand).focused($fieldFocused)
                Picker("Category", selection: $category) {
                    ForEach(FoodCategory.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Quantity printed on label", text: $labelQuantity).focused($fieldFocused)
                    .accessibilityIdentifier("label.quantity")
                Toggle("Reusable package size", isOn: $reusablePackageSize)
                Text("Leave this off for a per-purchase weighed amount. Only reusable package size is saved in the product catalogue.")
                    .font(PPTypography.caption)
                Toggle("Use label amount as remaining quantity", isOn: $useQuantity)
                    .disabled(ProductLabelOCR.quantity(in: labelQuantity) == nil)
                    .accessibilityIdentifier("label.useQuantity")
                Button("Scan Product Label") { fieldFocused = false; showPhoto = true }
            }
            if showPhoto {
                Section("Packaging photo") {
                    FoodPhotoSelectionView(model: photoModel)
                    Button("Read Label Text") { fieldFocused = false; recognize() }
                        .disabled(photoModel.photoData == nil || recognizing || photoModel.isLoadingPhoto)
                    if recognizing { ProgressView("Reading label…") }
                    Text("OCR suggestions are unverified. Review every field. Supported languages are checked on this device; Sinhala and Tamil support is not assumed.")
                        .font(PPTypography.caption)
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Menu(line) {
                            Button("Use as name") { name = line }
                            Button("Use as brand") { brand = line }
                            if ProductLabelOCR.quantity(in: line) != nil { Button("Use as label quantity") { labelQuantity = line } }
                        }
                    }
                }
            }
            Section {
                Text("Reusable product details are saved locally only after you confirm and save the food in the next step.")
                Button("Review & Add to Pantry") { fieldFocused = false; showingForm = true }
                    .disabled(photoModel.isLoadingPhoto || recognizing)
                    .accessibilityIdentifier("label.continue")
                if let error { Text(error).foregroundStyle(PPColors.dangerText) }
            }
        }
        .font(PPTypography.body)
        .scrollContentBackground(.hidden)
        .background(PPColors.background)
        .tint(PPColors.actionText)
        .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { fieldFocused = false } } }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Confirm Product")
        .onAppear { if startWithPhoto { showPhoto = true } }
        .navigationDestination(isPresented: $showingForm) {
            AddFoodView(product: ProductLookupResult(barcode: scan.rawValue, name: name, brand: brand.isEmpty ? nil : brand,
                quantityText: reusablePackageSize && !labelQuantity.isEmpty ? labelQuantity : nil,
                categoryText: category.rawValue, categoryTags: [], imageURL: nil,
                symbology: scan.symbology, pantryCategory: category.rawValue,
                suggestedQuantity: useQuantity ? ProductLabelOCR.quantity(in: labelQuantity) : nil,
                dataSource: usedOCR ? "Packaging OCR, reviewed by user" : "Manual packaging confirmation",
                usesOpenFoodFactsAttribution: false, isSuggestion: usedOCR),
                photoData: photoModel.photoData, resources: resources, save: save, onSaved: onSaved)
        }
        .onDisappear { ocrTask?.cancel() }
    }
    private func recognize() {
        guard let data = photoModel.photoData else { return }
        recognizing = true; error = nil
        ocrTask = Task {
            defer { recognizing = false }
            do {
                let result = try await Task.detached { try ProductLabelOCR.analyze(data) }.value
                guard !Task.isCancelled else { return }
                lines = result.lines; usedOCR = true
                // Never replace fields the user has already typed.
                if name.isEmpty { name = result.name ?? "" }
                if brand.isEmpty { brand = result.brand ?? "" }
                if labelQuantity.isEmpty { labelQuantity = result.quantity?.text ?? "" }
                if category == .other, let raw = result.category, let suggested = FoodCategory(rawValue: raw) { category = suggested }
                if result.lines.isEmpty { error = "No readable text found. Try a clearer photo or enter details manually." }
            } catch { if !Task.isCancelled { self.error = "Label text could not be read. Try another photo or enter details manually." } }
        }
    }
}

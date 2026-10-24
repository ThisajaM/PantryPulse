import SwiftUI
import PhotosUI

struct AddFoodView: View {
    private let isEditing: Bool
    private var onSaved: (() -> Void)?
    private var recognitionNotice: String?
    private var onRetake: (() -> Void)?
    @State private var model: AddFoodViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    private enum Field: Hashable { case name, quantity, notes, brand, packageQuantity }
    @FocusState private var focusedField: Field?

    init(draft: FoodDraft? = nil, resources: AccountResources = AccountResources(), save: @escaping (FoodDraft) throws -> PantryItem) {
        isEditing = draft != nil
        _model = State(initialValue: AddFoodViewModel(draft: draft ?? FoodDraft(name: ""), photos: resources.photos, save: save))
    }

    init(product: ProductLookupResult, photoData: Data?, resources: AccountResources = AccountResources(), save: @escaping (FoodDraft) throws -> PantryItem,
         onSaved: @escaping () -> Void) {
        isEditing = false
        self.onSaved = onSaved
        _model = State(initialValue: AddFoodViewModel(product: product, photoData: photoData, photos: resources.photos, catalogue: resources.catalogue, save: save))
    }

    init(recognizedName: String, category: FoodCategory, photoData: Data?,
         recognitionNotice: String? = nil, onRetake: (() -> Void)? = nil,
         resources: AccountResources = AccountResources(), save: @escaping (FoodDraft) throws -> PantryItem, onSaved: @escaping () -> Void) {
        isEditing = false
        self.onSaved = onSaved
        self.recognitionNotice = recognitionNotice
        self.onRetake = onRetake
        _model = State(initialValue: AddFoodViewModel(recognizedName: recognizedName, category: category,
                                                     photoData: photoData, photos: resources.photos, save: save))
    }

    var body: some View {
        @Bindable var model = model
        ScrollView {
          VStack(spacing: PPSpacing.md) {
            formCard { FoodPhotoSelectionView(model: model) }
            if let recognitionNotice {
                formCard("Review recognition") {
                    Text(recognitionNotice).font(PPTypography.caption)
                    if let onRetake { Button("Retake Photo", systemImage: "camera", action: onRetake) }
                }
            }
            formCard {
                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    fieldLabel("Food name")
                    TextField("Food name", text: $model.draft.name, prompt: Text("e.g. Greek Yogurt"))
                        .accessibilityLabel("Food name")
                        .accessibilityIdentifier("addFood.name")
                        .focused($focusedField, equals: .name)
                        .padding(PPSpacing.sm)
                        .background(PPColors.mutedSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: PPCornerRadius.small))
                }
                Picker("Category", selection: $model.draft.category) {
                    ForEach(FoodCategory.allCases) { Text($0.rawValue).tag($0) }
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: PPSpacing.xs) {
                        ForEach(FoodCategory.allCases) { category in
                            Button { model.draft.category = category } label: {
                                Text(category.rawValue).font(PPTypography.caption)
                                    .padding(.horizontal, PPSpacing.sm).frame(minHeight: 44)
                                    .foregroundStyle(model.draft.category == category ? PPColors.surface : PPColors.secondaryText)
                                    .background(model.draft.category == category ? PPColors.text : PPColors.mutedSurface, in: Capsule())
                            }.buttonStyle(.plain)
                             .accessibilityAddTraits(model.draft.category == category ? .isSelected : [])
                        }
                    }
                }
            }

            if model.identification != nil {
                formCard("Reusable product details") {
                    TextField("Brand (optional)", text: $model.productBrand)
                        .focused($focusedField, equals: .brand)
                    TextField("Package size (optional)", text: $model.packageQuantity)
                        .focused($focusedField, equals: .packageQuantity)
                    Text("Package size is product metadata. Enter the amount you actually have below; expiry and purchase date are never stored in the product catalogue.")
                        .font(PPTypography.caption)
                }
            }
            formCard("Quantity & units") {
                LabeledContent("Quantity") {
                    TextField("Quantity", text: $model.quantityText)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .accessibilityLabel("Quantity")
                        .accessibilityIdentifier("addFood.quantity")
                        .focused($focusedField, equals: .quantity)
                }
                Picker("Quantity unit", selection: $model.draft.quantityUnit) {
                    ForEach(QuantityUnit.allCases) { Text($0.rawValue).tag($0) }
                }
            }

            formCard {
                DatePicker("Purchase date", selection: $model.draft.purchaseDate, displayedComponents: .date)
                Toggle("Include expiry date", isOn: $model.includesExpiry)
                    .accessibilityIdentifier("addFood.includesExpiry")
                if model.includesExpiry {
                    DatePicker("Expiry date", selection: $model.expiryDate, displayedComponents: .date)
                }
            }
            Group {
                Text("Leave expiry off if the date is unknown. No expiry date will be estimated.")
            }

            formCard("Storage location") {
                Picker("Store in", selection: $model.draft.storageLocation) {
                    if !["Pantry", "Fridge", "Freezer"].contains(model.draft.storageLocation) {
                        Text(model.draft.storageLocation.isEmpty ? "Choose storage location" : model.draft.storageLocation).tag(model.draft.storageLocation)
                    }
                    ForEach(["Pantry", "Fridge", "Freezer"], id: \.self) { Text($0).tag($0) }
                }
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: PPSpacing.xs)) : AnyLayout(HStackLayout(spacing: PPSpacing.xs))
                layout {
                    storageTile("Pantry", symbol: "cabinet")
                    storageTile("Fridge", symbol: "refrigerator")
                    storageTile("Freezer", symbol: "snowflake")
                }
            }

            formCard("Notes & details (optional)") {
                TextField("Brand, opened date, or other notes", text: $model.notes, axis: .vertical)
                    .lineLimit(3...6)
                    .focused($focusedField, equals: .notes)
                    .accessibilityIdentifier("addFood.notes")
                    .padding(PPSpacing.sm)
                    .background(PPColors.mutedSurface.opacity(0.6), in: RoundedRectangle(cornerRadius: PPCornerRadius.small))
            }
            if typeSize.isAccessibilitySize {
                formCard {
                    saveButton
                }
                .listRowBackground(Color.clear)
            }
          }
          .padding(PPSpacing.lg)
          .frame(maxWidth: PPMetrics.screenContentWidth)
          .frame(maxWidth: .infinity)
        }
        .font(PPTypography.body)
        .scrollContentBackground(.hidden)
        .background(PPColors.background)
        .scrollDismissesKeyboard(.immediately)
        .navigationTitle(isEditing ? "Edit Food" : "Add Food")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !typeSize.isAccessibilitySize && focusedField == nil {
                saveButton
                    .padding(PPSpacing.md)
                    .background(PPColors.background)
            }
        }
        .onSubmit { focusedField = nil }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            focusedField = nil
        }
        .alert(model.savedItem != nil ? "Food saved" : (isEditing ? "Unable to save changes" : "Unable to add food"), isPresented: Binding(
            get: { model.errorMessage != nil || model.catalogueWarning != nil },
            set: { if !$0 { model.errorMessage = nil; model.catalogueWarning = nil } }
        )) {
            Button("OK", role: .cancel) { if model.savedItem != nil { finish() }; model.errorMessage = nil; model.catalogueWarning = nil }
        } message: {
            Text(model.errorMessage ?? model.catalogueWarning ?? "Please try again.")
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased()).font(PPTypography.caption).fontWeight(.semibold)
            .tracking(0.6).foregroundStyle(PPColors.secondaryText)
            .onTapGesture { focusedField = nil }
    }

    private func formCard<Content: View>(_ title: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            if let title { fieldLabel(title) }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppCard()
    }

    private func storageTile(_ title: String, symbol: String) -> some View {
        Button { model.draft.storageLocation = title } label: {
            VStack(spacing: PPSpacing.xs) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(PPTypography.caption)
            }
            .frame(maxWidth: .infinity).padding(PPSpacing.sm)
            .foregroundStyle(model.draft.storageLocation == title ? PPColors.actionText : PPColors.secondaryText)
            .background(model.draft.storageLocation == title ? PPColors.primary.opacity(0.15) : PPColors.mutedSurface.opacity(0.6),
                        in: RoundedRectangle(cornerRadius: PPCornerRadius.small))
        }.buttonStyle(.plain)
         .accessibilityLabel("Store in " + title)
         .accessibilityAddTraits(model.draft.storageLocation == title ? .isSelected : [])
    }

    private func finish() {
        if let onSaved { onSaved() } else { dismiss() }
    }

    private var saveButton: some View {
        PrimaryButton(title: isEditing ? "Save Changes" : "Add to Pantry", systemImage: "checkmark.circle", isLoading: model.isSaving) {
            focusedField = nil
            if model.save() {
                if model.catalogueWarning == nil { finish() }
            }
        }
        .disabled(model.savedItem != nil || model.isLoadingPhoto)
        .accessibilityIdentifier("addFood.save")
    }
}

#Preview {
    NavigationStack {
        AddFoodView { _ in throw PersistenceError.storeUnavailable }
    }
}

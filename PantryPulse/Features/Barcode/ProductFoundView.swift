import SwiftUI

struct ProductFoundView: View {
    let product: ProductLookupResult
    @Bindable var lookup: BarcodeLookupModel
    let onContinue: () -> Void
    let onRescan: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                StatusBadge(title: product.isSuggestion ? "Suggested product — please confirm" : "Product information retrieved", tone: .success)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: PPSpacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: PPCornerRadius.image).fill(PPColors.mutedSurface)
                        if let data = lookup.imageData, let image = UIImage(data: data) {
                            Image(uiImage: image).resizable().scaledToFit().padding(PPSpacing.sm)
                        } else if lookup.isLoadingImage { ProgressView("Loading product photo…") }
                        else { Label("No product photo available", systemImage: "photo").font(PPTypography.caption) }
                    }
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: PPCornerRadius.image))
                    if let brand = product.brand { Text(brand).font(PPTypography.body).foregroundStyle(PPColors.secondaryText) }
                    Text(product.name ?? "Product name unavailable").font(PPTypography.screenTitle)
                        .accessibilityIdentifier("barcode.productName")
                    if let quantity = product.quantityText { Text("Package: \(quantity)").font(PPTypography.body) }
                    LabeledContent("Barcode", value: product.barcode).font(PPTypography.caption)
                    LabeledContent("Suggested category", value: product.suggestedCategory?.rawValue ?? "Choose in the next step")
                        .font(PPTypography.body)
                    if let categories = product.categoryText {
                        Text(categories).font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                    }
                }.ppCard()
                if lookup.imageData != nil {
                    Toggle("Use this product photo", isOn: $lookup.acceptsImage).tint(PPColors.success)
                    Text("You can replace or remove the photo in Add Food.").font(PPTypography.caption)
                }
                if let error = lookup.imageError {
                    Text(error).font(PPTypography.caption).foregroundStyle(PPColors.dangerText)
                    Button("Retry Photo") { lookup.retryImage() }
                }
                Text("Confirm your remaining quantity, purchase date, storage and optional expiry in the next step.")
                    .font(PPTypography.body).ppCard()
                PrimaryButton(title: "Review & Add to Pantry", systemImage: "plus", action: onContinue)
                    .disabled(lookup.isLoadingImage)
                    .accessibilityIdentifier("barcode.continue")
                SecondaryButton(title: "Scan another barcode", systemImage: "barcode.viewfinder", action: onRescan)
                VStack(alignment: .leading, spacing: PPSpacing.xs) {
                    if let source = product.dataSource { Text(source) }
                    if let url = product.sourceURL { Link(product.usesOpenFoodFactsAttribution ? "Product data: Open Food Facts contributors" : "Product source", destination: url) }
                    if product.usesOpenFoodFactsAttribution, let terms = URL(string: "https://world.openfoodfacts.org/terms-of-use") {
                        Link("Data: ODbL · Images: CC BY-SA", destination: terms)
                    }
                    Text("Product data may be incomplete. Check the package before saving.")
                }.font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
            }
            .padding(PPSpacing.lg)
            .frame(maxWidth: PPMetrics.screenContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(PPColors.background)
        .foregroundStyle(PPColors.text)
    }
}

import SwiftUI

extension PantryFreshness {
    var tone: PPStatusTone {
        switch self {
        case .unknown: .neutral
        case .fresh: .success
        case .expiringSoon: .warning
        case .urgent, .expired: .danger
        }
    }
}

struct PantryFoodGrid: View {
    let food: [PantryFoodDisplay]
    let onSelect: (UUID) -> Void
    var imageAspectRatio: CGFloat = 1
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        LazyVGrid(columns: typeSize.isAccessibilitySize
                  ? [GridItem(.flexible())]
                  : [GridItem(.adaptive(minimum: PPMetrics.foodCardMinimumWidth), spacing: PPSpacing.sm)],
                  alignment: .leading, spacing: PPSpacing.md) {
            ForEach(food) { food in
                Button { onSelect(food.id) } label: {
                    PantryStoredFoodCard(food: food, imageAspectRatio: imageAspectRatio)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens food details")
            }
        }
    }
}

private struct PantryStoredFoodCard: View {
    let food: PantryFoodDisplay
    let imageAspectRatio: CGFloat
    @State private var photo = FoodPhotoLoader()
    var body: some View {
        FoodCard(title: food.item.name, subtitle: food.subtitle,
                 image: photo.image.map { Image(uiImage: $0) } ?? food.item.imageAssetName.map { Image($0) },
                 imageAspectRatio: imageAspectRatio,
                 expiry: StatusBadge(title: food.expiryText, tone: food.freshness.tone),
                 status: StatusBadge(title: food.freshness.title, tone: food.freshness.tone))
            .task(id: food.item.imagePath) { await photo.load(food.item.imagePath) }
    }
}

struct PantryFoodRow: View {
    @State private var photo = FoodPhotoLoader()
    let food: PantryFoodDisplay
    let onSelect: () -> Void
    var priorityExplanation: String? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onSelect) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: PPSpacing.sm))
                : AnyLayout(HStackLayout(spacing: PPSpacing.sm))
            layout {
                thumbnail
                VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                    Text(food.item.name).font(PPTypography.cardTitle).foregroundStyle(PPColors.text)
                    Text([food.addedDescription, food.expiryText].compactMap { $0 }.joined(separator: " • "))
                        .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                    if let priorityExplanation {
                        StatusBadge(title: food.freshness.title, tone: food.freshness.tone)
                        Text(priorityExplanation).font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let quantity = food.item.quantityDescription {
                    StatusBadge(title: quantity)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .ppCard(padding: PPSpacing.sm)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens food details")
    }

    private var thumbnail: some View {
        PPColors.mutedSurface
            .frame(width: PPMetrics.foodThumbnail, height: PPMetrics.foodThumbnail)
            .overlay {
                if let image = photo.image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let name = food.item.imageAssetName {
                    Image(name).resizable().scaledToFill()
                } else {
                    Image(systemName: "carrot").foregroundStyle(PPColors.secondaryText)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: PPCornerRadius.small))
            .accessibilityHidden(true)
            .task(id: food.item.imagePath) { await photo.load(food.item.imagePath) }
    }
}

struct PantrySectionMessage: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.xs) {
            Text(title).font(PPTypography.cardTitle).foregroundStyle(PPColors.text)
            Text(message).font(PPTypography.body).foregroundStyle(PPColors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .ppCard()
    }
}

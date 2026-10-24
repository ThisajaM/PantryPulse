#if DEBUG
import Foundation
import SwiftUI

/// Figma-inspired fixtures, only referenced by previews. Never seeded into the app.
@MainActor
enum PantryPreviewData {
    static let referenceDate = Date(timeIntervalSince1970: 1_800_000_000)
    static let items: [PantryItem] = [
        item(1, "Whole Milk", .dairy, "2 bottles", "Fridge", "FoodMilk", 1, 3),
        item(2, "Ripe Bananas", .fruits, "6 pieces", "Counter", "FoodBanana", 2, 2),
        item(3, "Artisan Sourdough", .bakery, "1 loaf", "Breadbox", "FoodBread", 1, 2),
        item(4, "Farm Fresh Eggs", .other, "12 pieces", "Fridge", "FoodEggs", 5, 1),
        item(5, "Vine Tomatoes", .vegetables, "500 g", "Counter", "FoodTomatoes", 6, 0),
        item(6, "Broccoli Crown", .vegetables, "1 head", "Crisper", "FoodBroccoli", 4, 1)
    ]

    static func viewModel() -> PantryViewModel {
        PantryViewModel(items: items, now: { referenceDate })
    }

    private static func item(_ id: Int, _ name: String, _ category: FoodCategory,
                             _ quantity: String, _ location: String, _ image: String,
                             _ expiryDays: Int, _ addedDaysAgo: Int) -> PantryItem {
        PantryItem(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", id))!,
                   name: name, category: category, quantityDescription: quantity,
                   storageLocation: location, imageAssetName: image,
                   expiryDate: Calendar.current.date(byAdding: .day, value: expiryDays, to: referenceDate),
                   addedAt: Calendar.current.date(byAdding: .day, value: -addedDaysAgo, to: referenceDate))
    }
}

#Preview("Home — empty production state") {
    AppRootView()
}

#Preview("Home — sample data") {
    AppRootView(pantry: PantryPreviewData.viewModel())
}

#Preview("Pantry — sample data") {
    AppRootView(pantry: PantryPreviewData.viewModel(), initialTab: .pantry)
}

#Preview("Pantry — empty") {
    AppRootView(initialTab: .pantry)
}

#Preview("Pantry — accessibility") {
    AppRootView(pantry: PantryPreviewData.viewModel(), initialTab: .pantry)
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("Home — dark") {
    AppRootView(pantry: PantryPreviewData.viewModel()).preferredColorScheme(.dark)
}
#endif

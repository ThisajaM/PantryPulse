import Foundation

nonisolated struct FoodPrediction: Equatable, Identifiable, Sendable {
    let label: String
    let confidence: Double
    var id: String { label }
    var displayName: String { label.replacingOccurrences(of: "_", with: " ").capitalized }
}

nonisolated struct FoodRecognitionResult: Sendable {
    let predictions: [FoodPrediction]
    let supportedLabels: [String]

    /// A conservative UI review rule, not an evaluated unknown-food detector.
    var needsExtraReview: Bool {
        guard let first = predictions.first else { return true }
        let second = predictions.dropFirst().first?.confidence ?? 0
        return first.confidence < 0.60 || first.confidence - second < 0.15
    }
}

/// Exact labels only. Mixed dishes remain Other rather than inferring ingredients.
enum FoodRecognitionCategory {
    static func category(for label: String) -> FoodCategory {
        let fruits: Set<String> = ["Apple", "Avocado", "Banana", "Blackberry", "Blueberry", "Dates", "Dragonfruit", "Fig", "Grapes", "Guava", "Kiwi", "Lemon", "Mango", "Olive", "Orange", "Pear", "Pineapple", "Pomegranate", "Rambutan", "Strawberry", "Watermelon"]
        let vegetables: Set<String> = ["Beetroot", "Broccoli", "Cabbage", "Capsicum", "Carrot", "Cauliflower", "Chilli Peper", "Corn", "Cucumber", "Eggplant", "Garlic", "Ginger", "Jalepeno", "Lettuce", "Mushroom", "Okra", "Onion", "Paprika", "Peas", "Potato", "Pumpkin", "Raddish", "Soy Beans", "Spinach", "Sweetcorn", "Sweetpotato", "Tomato", "Turnip", "edamame"]
        if fruits.contains(label) { return .fruits }
        if vegetables.contains(label) { return .vegetables }
        if label == "Peanuts" { return .grainsPantry }
        if ["cheese_plate", "frozen_yogurt", "ice_cream"].contains(label) { return .dairy }
        if ["garlic_bread", "donuts", "macarons", "cup_cakes"].contains(label) { return .bakery }
        if ["grilled_salmon", "steak", "mussels", "oysters", "scallops", "sashimi", "pork_chop", "prime_rib", "filet_mignon"].contains(label) { return .meatSeafood }
        return .other
    }
}

import Foundation

/// Proportions of the dashboard's existing classifications; no expiry thresholds live here.
struct FreshnessPulseDistribution: Equatable {
    enum Category: CaseIterable {
        case fresh, expiringSoon, attention, unknown
    }

    struct Band: Equatable {
        let category: Category
        let start: Double
        let end: Double
    }

    let bands: [Band]

    init(fresh: Int, expiringSoon: Int, urgent: Int, expired: Int, unknown: Int) {
        let counts = [max(0, fresh), max(0, expiringSoon), max(0, urgent) + max(0, expired), max(0, unknown)]
        let total = counts.reduce(0, +)
        guard total > 0 else {
            bands = [Band(category: .unknown, start: 0, end: 1)]
            return
        }
        var cumulative = 0
        bands = zip(Category.allCases, counts).compactMap { category, count in
            guard count > 0 else { return nil }
            let start = Double(cumulative) / Double(total)
            cumulative += count
            return Band(category: category, start: start, end: Double(cumulative) / Double(total))
        }
    }
}

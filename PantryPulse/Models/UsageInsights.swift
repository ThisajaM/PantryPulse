import Foundation

enum InsightsPeriod: String, CaseIterable, Identifiable {
    case all = "All history", month = "This month", last30Days = "Last 30 days", year = "This year"
    var id: Self { self }
}

struct UsageCategoryCount: Identifiable {
    let category: FoodCategory
    let count: Int
    var id: FoodCategory { category }
}

/// Counts events and distinct inventory identities; never sums unlike physical units.
struct UsageInsights {
    let events: [UsageEvent]
    init(events: [UsageEvent], period: InsightsPeriod, now: Date, calendar: Calendar = .autoupdatingCurrent) {
        let start: Date
        switch period {
        case .all: start = .distantPast
        case .month: start = calendar.dateInterval(of: .month, for: now)?.start ?? now
        case .year: start = calendar.dateInterval(of: .year, for: now)?.start ?? now
        case .last30Days: start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now)) ?? now
        }
        self.events = events.filter { $0.date >= start && $0.date <= now }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
        }
    }
    func count(_ type: UsageEventType) -> Int { events.filter { $0.type == type }.count }
    func itemCount(_ type: UsageEventType) -> Int { Set(events.filter { $0.type == type }.map(\.itemID)).count }
    var wastedCategories: [UsageCategoryCount] {
        Dictionary(grouping: events.filter { $0.type == .wasted }, by: \.category)
            .map { UsageCategoryCount(category: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.category.rawValue < $1.category.rawValue : $0.count > $1.count }
    }
}

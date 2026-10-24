import Foundation
import Testing
@testable import PantryPulse

@MainActor
struct PantryPresentationTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12))! }

    @Test func productionInventoryIsEmpty() {
        let model = PantryViewModel()
        #expect(model.items.isEmpty)
        #expect(model.urgentCount == 0)
        #expect(model.expiringSoonCount == 0)
        #expect(model.useFirst.isEmpty)
        #expect(model.recentlyAdded.isEmpty)
    }

    @Test func expiryUsesCalendarDaysAndDoesNotRecommendOverdueFood() {
        let reference = today
        let dates = [-1, 0, 1, 2, 3, 4]
        var items = dates.map { day in
            PantryItem(id: UUID(), name: "Day \(day)", expiryDate: calendar.date(byAdding: .day, value: day, to: reference))
        }
        items.append(PantryItem(id: UUID(), name: "Unknown date"))
        let model = PantryViewModel(items: items, now: { reference }, calendar: calendar)
        #expect(model.urgentCount == 2)
        #expect(model.expiredCount == 1)
        #expect(model.expiringSoonCount == 2)
        #expect(model.freshCount == 1)
        #expect(model.unknownExpiryCount == 1)
        #expect(model.useFirst.map(\.item.name) == ["Day 0", "Day 1", "Day 2", "Day 3", "Day 4"])
        #expect(model.visibleFood.last?.item.name == "Unknown date")
        let earlyToday = calendar.startOfDay(for: reference)
        let row = PantryFoodDisplay(item: PantryItem(id: UUID(), name: "Today", expiryDate: earlyToday), referenceDate: reference, calendar: calendar)
        #expect(row.daysUntilExpiry == 0)
        #expect(row.expiryText == "Expires today")
    }

    @Test func searchAndCategoryCombineWithoutChangingDashboardTotals() {
        let items = [
            PantryItem(id: UUID(), name: "Crème cheese", category: .dairy),
            PantryItem(id: UUID(), name: "Banana", category: .fruits),
            PantryItem(id: UUID(), name: "Milk", category: .dairy)
        ]
        let model = PantryViewModel(items: items)
        model.searchText = "  CREME  "
        model.selectedCategory = .dairy
        #expect(model.visibleFood.map(\.item.name) == ["Crème cheese"])
        model.selectedCategory = .fruits
        #expect(model.visibleFood.isEmpty)
        #expect(model.itemCount == 3)
        #expect(model.count(in: .dairy) == 2)
        model.clearFilters()
        model.sortOrder = .name
        #expect(model.visibleFood.map(\.item.name) == ["Banana", "Crème cheese", "Milk"])
        #expect(model.recentlyAdded.isEmpty, "Unknown added dates must not be presented as recently added.")
    }
}

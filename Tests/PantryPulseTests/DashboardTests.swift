import CoreData
import Testing
@testable import PantryPulse

@MainActor
struct DashboardTests {
    private func calendar(_ zone: String = "America/New_York") -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: zone)!
        return result
    }

    @Test(arguments: [3, 11])
    func calendarBoundariesAcrossDaylightSaving(month: Int) {
        let calendar = calendar()
        // Both the 23-hour spring day and 25-hour autumn day must count as one day.
        let reference = calendar.date(from: DateComponents(year: 2026, month: month, day: month == 3 ? 8 : 1, hour: 23, minute: 59))!
        let expected: [PantryFreshness] = [.expired, .urgent, .urgent, .expiringSoon, .expiringSoon, .fresh]
        for (offset, classification) in zip(-1...4, expected) {
            let expiry = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: reference))!
            let display = PantryFoodDisplay(item: PantryItem(id: UUID(), name: "Boundary", expiryDate: expiry), referenceDate: reference, calendar: calendar)
            #expect(display.daysUntilExpiry == offset)
            #expect(display.freshness == classification)
        }
        let missing = PantryFoodDisplay(item: PantryItem(id: UUID(), name: "Undated"), referenceDate: reference, calendar: calendar)
        #expect(missing.freshness == .unknown)
    }

    @Test func dashboardTracksRealActiveRecordsAndMutations() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let calendar = calendar("Asia/Colombo")
        var clock = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 12))!
        let repo = PantryRepository(container: try #require(storage.container), now: { clock })
        let dashboard = PantryViewModel(repository: repo, now: { clock }, calendar: calendar)
        var drafts: [FoodDraft] = []
        for offset in -1...4 {
            var draft = FoodDraft(name: "Offset \(offset)")
            draft.expiryDate = calendar.date(byAdding: .day, value: offset, to: clock)
            _ = try repo.create(draft)
            drafts.append(draft)
            clock = clock.addingTimeInterval(1)
        }
        let undated = try repo.create(FoodDraft(name: "Undated"))
        for status in [PantryItemStatus.consumed, .wasted, .archived] {
            var draft = FoodDraft(name: status.rawValue)
            draft.status = status
            draft.expiryDate = clock
            _ = try repo.create(draft)
        }
        #expect(dashboard.itemCount == 7)
        #expect(dashboard.expiredCount == 1)
        #expect(dashboard.urgentCount == 2)
        #expect(dashboard.expiringSoonCount == 2)
        #expect(dashboard.freshCount == 1)
        #expect(dashboard.unknownExpiryCount == 1)
        #expect(dashboard.itemCount == dashboard.expiredCount + dashboard.urgentCount + dashboard.expiringSoonCount + dashboard.freshCount + dashboard.unknownExpiryCount)
        #expect(dashboard.useFirst.map(\.id) == Array(drafts.dropFirst()).map(\.id))
        #expect(dashboard.recentlyAdded.first?.id == undated.id)
        var edited = drafts[1]
        edited.expiryDate = nil
        _ = try repo.update(edited)
        #expect(dashboard.urgentCount == 1)
        #expect(dashboard.unknownExpiryCount == 2)
        edited.status = .consumed
        _ = try repo.update(edited)
        #expect(dashboard.itemCount == 6)
        #expect(!dashboard.recentlyAdded.contains { $0.id == edited.id })
        try repo.delete(id: drafts[2].id)
        #expect(dashboard.urgentCount == 0)
        #expect(dashboard.itemCount == 5)
        #expect(dashboard.useFirst.map(\.id) == Array(drafts.suffix(3)).map(\.id))
        // Reopening the presentation layer must derive the same values from saved records.
        let reopened = PantryViewModel(repository: repo, now: { clock }, calendar: calendar)
        #expect(reopened.itemCount == dashboard.itemCount)
        #expect(reopened.useFirst.map(\.id) == dashboard.useFirst.map(\.id))
    }

    @Test func refreshReclassifiesAtLocalMidnightWithoutInventoryChanges() {
        let calendar = calendar("Asia/Colombo")
        var clock = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 23, minute: 59))!
        let item = PantryItem(id: UUID(), name: "Today", expiryDate: clock)
        let dashboard = PantryViewModel(items: [item], now: { clock }, calendar: calendar)
        #expect(dashboard.urgentCount == 1)
        clock = clock.addingTimeInterval(120)
        dashboard.reload()
        #expect(dashboard.expiredCount == 1)
        #expect(dashboard.urgentCount == 0)
        #expect(dashboard.useFirst.isEmpty)
    }
}

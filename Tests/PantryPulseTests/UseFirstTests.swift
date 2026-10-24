import Foundation
import Testing
@testable import PantryPulse

@MainActor
struct UseFirstTests {
    @Test func prioritySeparatesExpiredAndUnknownAndMatchesDashboard() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Colombo"))
        var now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 23, minute: 59)))
        var items = [-3, 0, 1, 2, 3, 4, 10].map { offset in
            PantryItem(id: UUID(), name: "Day \(offset)", expiryDate: calendar.date(byAdding: .day, value: offset, to: now))
        }
        let unknown = PantryItem(id: UUID(), name: "Undated")
        items.append(unknown)
        items.append(PantryItem(id: UUID(), name: "Consumed", expiryDate: now, status: .consumed))
        items.append(PantryItem(id: UUID(), name: "Wasted", expiryDate: now, status: .wasted))
        let dashboard = PantryViewModel(items: items.reversed(), now: { now }, calendar: calendar)
        #expect(dashboard.useFirst.map(\.item.name) == ["Day 0", "Day 1", "Day 2", "Day 3", "Day 4", "Day 10"])
        #expect(dashboard.unknownExpiry.map(\.id) == [unknown.id])
        #expect(dashboard.expiredFood.map(\.item.name) == ["Day -3"])
        #expect(dashboard.expiredCount == dashboard.expiredFood.count)
        #expect(dashboard.itemCount == dashboard.useFirst.count + dashboard.expiredFood.count + dashboard.unknownExpiry.count)
        now = now.addingTimeInterval(120)
        dashboard.reload()
        #expect(dashboard.useFirst.first?.item.name == "Day 1")
        #expect(dashboard.expiredFood.count == 2)
        #expect(dashboard.expiredCount == 2)
    }

    @Test func tiesHaveStableIdentityOrderingAndEmptyIsEmpty() {
        let date = Date()
        let first = PantryItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Rice", expiryDate: date)
        let second = PantryItem(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, name: "Rice", expiryDate: date)
        #expect(ExpiryPrioritizer.group([second, first], on: date).upcoming.map(\.id) == [first.id, second.id])
        let empty = ExpiryPrioritizer.group([], on: date)
        #expect(empty.upcoming.isEmpty && empty.expired.isEmpty && empty.unknown.isEmpty)
    }
}

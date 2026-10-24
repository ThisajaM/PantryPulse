import Foundation
import Testing
import UserNotifications
@testable import PantryPulse

@MainActor
struct ExpiryReminderTests {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Colombo")!
        return calendar
    }
    private func date(_ day: Int, hour: Int = 8) -> Date {
        calendar().date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func defaults() -> UserDefaults { UserDefaults(suiteName: "PantryPulse.ReminderTests.\(UUID())")! }

    @Test func futureOffsetsMissingDatesInactiveAndStableIdentifiers() {
        let item = PantryItem(id: UUID(), name: "Milk", expiryDate: date(24))
        let preferences = ReminderPreferences(enabled: true)
        var inactive = item
        inactive.status = .consumed
        let planned = ExpiryReminderPlanner.plan(items: [item, item, inactive, PantryItem(id: UUID(), name: "Unknown")],
                                                preferences: preferences, now: date(21), calendar: calendar())
        #expect(planned.count == 3)
        #expect(planned.map(\.fireDate) == [date(21, hour: 9), date(23, hour: 9), date(24, hour: 9)])
        #expect(Set(planned.map(\.identifier)).count == 3)
        #expect(planned.allSatisfy { $0.identifier.contains(item.id.uuidString) })
        #expect(ExpiryReminderPlanner.plan(items: [item], preferences: preferences, now: date(21, hour: 9), calendar: calendar()).count == 2)
        #expect(ExpiryReminderPlanner.plan(items: [item], preferences: preferences, now: date(25), calendar: calendar()).isEmpty)
        #expect(ExpiryReminderPlanner.plan(items: [item], preferences: ReminderPreferences(), now: date(21), calendar: calendar()).isEmpty)
    }

    @Test func boundedScheduleAndCalendarDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        for month in [3, 11] {
            let day = month == 3 ? 8 : 1
            let expiry = try #require(calendar.date(from: DateComponents(year: 2026, month: month, day: day + 1)))
            let now = try #require(calendar.date(byAdding: .day, value: -4, to: expiry))
            let items = (0..<100).map { PantryItem(id: UUID(), name: "Item \($0)", expiryDate: expiry) }
            let planned = ExpiryReminderPlanner.plan(items: items, preferences: ReminderPreferences(enabled: true), now: now, calendar: calendar, capacity: 10)
            #expect(planned.count == 10)
            #expect(planned.allSatisfy { calendar.component(.hour, from: $0.fireDate) == 9 })
            let one = ExpiryReminderPlanner.plan(items: [items[0]], preferences: ReminderPreferences(enabled: true), now: now, calendar: calendar)
            #expect(one.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: $0.fireDate), to: calendar.startOfDay(for: expiry)).day } == [3, 1, 0])
        }
    }

    @Test func permissionIsRequestedOnlyOnEnableAndDeniedAccessCancelsOwnedRequests() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let repo = PantryRepository(container: try #require(storage.container))
        let center = TestExpiryNotificationCenter()
        center.status = .notDetermined
        center.grantsPermission = false
        center.requests = ["unrelated": PendingExpiryNotification(identifier: "unrelated", title: "Other", body: "", components: nil)]
        let service = NotificationService(repository: repo, center: center, defaults: defaults())
        service.refresh()
        await service.waitForReconciliation()
        #expect(center.permissionRequests == 0)
        await service.setEnabled(true)
        #expect(center.permissionRequests == 1)
        #expect(service.authorization == .denied)
        #expect(service.pendingCount == 0)
        #expect(center.requests["unrelated"] != nil)
        await service.setEnabled(false)
        #expect(center.permissionRequests == 1)
    }

    @Test func reconciliationTracksEditsDeletionInactivityPreferencesAndRestart() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let repo = PantryRepository(container: try #require(storage.container))
        let center = TestExpiryNotificationCenter()
        let settings = defaults()
        var now = date(21)
        let service = NotificationService(repository: repo, center: center, defaults: settings, now: { now }, calendar: calendar)
        var draft = FoodDraft(name: "Milk")
        draft.expiryDate = date(24)
        _ = try repo.create(draft)
        await service.waitForReconciliation()
        #expect(center.requests.isEmpty)
        await service.setEnabled(true)
        #expect(center.requests.count == 3)
        let originalIDs = Set(center.requests.keys)
        let additions = center.additions
        service.refresh()
        await service.waitForReconciliation()
        #expect(center.additions == additions)
        draft.expiryDate = date(25)
        draft.name = "Oat Milk"
        _ = try repo.update(draft)
        await service.waitForReconciliation()
        #expect(Set(center.requests.keys) == originalIDs)
        #expect(center.requests.values.allSatisfy { $0.body.contains("Oat Milk") })
        service.setTime(hour: 10, minute: 30)
        service.setKind(.threeDays, enabled: false)
        await service.waitForReconciliation()
        #expect(center.requests.count == 2)
        #expect(center.requests.values.allSatisfy { $0.components?.hour == 10 && $0.components?.minute == 30 })
        #expect(ReminderPreferences.load(from: settings) == service.preferences)
        let reopened = NotificationService(repository: repo, center: center, defaults: settings, now: { now }, calendar: calendar)
        reopened.refresh()
        await reopened.waitForReconciliation()
        #expect(center.requests.count == 2)
        for status in [PantryItemStatus.consumed, .wasted, .archived] {
            draft.status = status
            _ = try repo.update(draft)
            await service.waitForReconciliation()
            await reopened.waitForReconciliation()
            #expect(center.requests.isEmpty)
            draft.status = .active
            _ = try repo.update(draft)
            await service.waitForReconciliation()
            await reopened.waitForReconciliation()
        }
        now = date(26)
        service.refresh()
        await service.waitForReconciliation()
        #expect(center.requests.isEmpty)
        now = date(21)
        service.refresh()
        await service.waitForReconciliation()
        #expect(center.requests.count == 2)
        try repo.delete(id: draft.id)
        await service.waitForReconciliation()
        await reopened.waitForReconciliation()
        #expect(center.requests.isEmpty)
    }

    @Test func inventoryChangesDuringSchedulingConvergeToLatestState() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let repo = PantryRepository(container: try #require(storage.container))
        var draft = FoodDraft(name: "Changing item")
        draft.expiryDate = date(24)
        _ = try repo.create(draft)
        let center = TestExpiryNotificationCenter()
        center.afterAdd = { do { try repo.delete(id: draft.id) } catch { Issue.record(error) } }
        let service = NotificationService(repository: repo, center: center, defaults: defaults(), now: { date(21) }, calendar: calendar)
        await service.setEnabled(true)
        #expect(try repo.fetchAll().isEmpty)
        #expect(center.requests.isEmpty)
        #expect(service.pendingCount == 0)
    }

    @Test func disabledMissingExpiryAndFailedEditRemoveObsoleteNotifications() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let repo = PantryRepository(container: try #require(storage.container))
        var draft = FoodDraft(name: "Changing date")
        draft.expiryDate = date(24)
        _ = try repo.create(draft)
        let center = TestExpiryNotificationCenter()
        let service = NotificationService(repository: repo, center: center, defaults: defaults(), now: { date(21) }, calendar: calendar)
        await service.setEnabled(true)
        #expect(center.requests.count == 3)
        center.failAdds = true
        draft.expiryDate = date(25)
        _ = try repo.update(draft)
        await service.waitForReconciliation()
        #expect(service.errorMessage != nil)
        #expect(center.requests.isEmpty, "An old expiry must not remain scheduled if replacement fails")
        center.failAdds = false
        service.refresh()
        await service.waitForReconciliation()
        #expect(center.requests.count == 3)
        draft.expiryDate = nil
        _ = try repo.update(draft)
        await service.waitForReconciliation()
        #expect(center.requests.isEmpty)
        draft.expiryDate = date(24)
        _ = try repo.update(draft)
        await service.waitForReconciliation()
        await service.setEnabled(false)
        #expect(center.requests.isEmpty)
    }

    @Test func confirmedUsageCancelsRemindersAndUpdatesDashboardAndInsights() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let repo = PantryRepository(container: try #require(storage.container))
        var draft = FoodDraft(name: "Milk")
        draft.expiryDate = date(24)
        let item = try repo.create(draft)
        let pantry = PantryViewModel(repository: repo, now: { date(21) }, calendar: calendar())
        let center = TestExpiryNotificationCenter()
        let service = NotificationService(repository: repo, center: center, defaults: defaults(), now: { date(21) }, calendar: calendar)
        await service.setEnabled(true)
        #expect(center.requests.count == 3 && pantry.useFirst.count == 1)
        _ = try repo.recordUsage(itemID: item.id, type: .consumed, eventID: UUID(), expectedUpdatedAt: item.updatedAt)
        await service.waitForReconciliation()
        #expect(center.requests.isEmpty)
        #expect(pantry.itemCount == 0 && pantry.useFirst.isEmpty)
        #expect(pantry.usageEvents.count == 1)
    }

    @Test func deactivatedAccountStopsAddingRemindersAndIgnoresLaterChanges() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let repo = PantryRepository(container: try #require(storage.container))
        var draft = FoodDraft(name: "Account A food")
        draft.expiryDate = date(24)
        _ = try repo.create(draft)
        let center = TestExpiryNotificationCenter()
        let service = NotificationService(repository: repo, center: center, defaults: defaults(), now: { date(21) }, calendar: calendar)
        center.afterAdd = { service.deactivate() }
        await service.setEnabled(true)
        #expect(center.additions == 1)
        center.remove(identifiers: Array(center.requests.keys))
        _ = try repo.create(draft)
        service.refresh()
        await service.waitForReconciliation()
        #expect(center.requests.isEmpty)
        #expect(center.additions == 1)
    }

    @Test func errorsAreVisibleAndRetryRecovers() async throws {
        let storage = PersistenceController(inMemory: true)
        await storage.load()
        let repo = PantryRepository(container: try #require(storage.container))
        var draft = FoodDraft(name: "Bread")
        draft.expiryDate = date(24)
        _ = try repo.create(draft)
        let center = TestExpiryNotificationCenter()
        center.failAdds = true
        let service = NotificationService(repository: repo, center: center, defaults: defaults(), now: { date(21) }, calendar: calendar)
        await service.setEnabled(true)
        #expect(service.errorMessage != nil)
        center.failAdds = false
        service.refresh()
        await service.waitForReconciliation()
        #expect(service.errorMessage == nil)
        #expect(service.pendingCount == 3)
        center.status = .denied
        service.refresh()
        await service.waitForReconciliation()
        #expect(center.requests.isEmpty)
    }
}

@MainActor
private final class TestExpiryNotificationCenter: ExpiryNotificationCenter {
    var status: UNAuthorizationStatus = .authorized
    var grantsPermission = true
    var permissionRequests = 0
    var additions = 0
    var failAdds = false
    var afterAdd: (() -> Void)?
    var requests: [String: PendingExpiryNotification] = [:]
    func authorizationStatus() async -> UNAuthorizationStatus { status }
    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        status = grantsPermission ? .authorized : .denied
        return grantsPermission
    }
    func pending() async -> [PendingExpiryNotification] { Array(requests.values) }
    func add(_ reminder: ExpiryReminder) async throws {
        if failAdds { throw NSError(domain: "NotificationTest", code: 1) }
        additions += 1
        requests[reminder.identifier] = PendingExpiryNotification(identifier: reminder.identifier, title: reminder.title, body: reminder.body, components: reminder.components)
        let callback = afterAdd
        afterAdd = nil
        callback?()
    }
    func remove(identifiers: [String]) { for id in identifiers { requests.removeValue(forKey: id) } }
}

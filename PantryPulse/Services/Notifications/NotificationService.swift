import Combine
import Foundation
import Observation
import UserNotifications

struct PendingExpiryNotification {
    let identifier: String
    let title: String
    let body: String
    let components: DateComponents?

    func matches(_ reminder: ExpiryReminder) -> Bool {
        identifier == reminder.identifier && title == reminder.title && body == reminder.body
            && components == reminder.components
    }
}

/// The OS boundary is injectable; tests never request permission or schedule real alerts.
@MainActor
protocol ExpiryNotificationCenter {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func pending() async -> [PendingExpiryNotification]
    func add(_ reminder: ExpiryReminder) async throws
    func remove(identifiers: [String])
}

@MainActor
final class SystemExpiryNotificationCenter: ExpiryNotificationCenter {
    private let center = UNUserNotificationCenter.current()
    func authorizationStatus() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func requestAuthorization() async throws -> Bool { try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
    func pending() async -> [PendingExpiryNotification] {
        await center.pendingNotificationRequests().map {
            PendingExpiryNotification(identifier: $0.identifier, title: $0.content.title, body: $0.content.body,
                                      components: ($0.trigger as? UNCalendarNotificationTrigger)?.dateComponents)
        }
    }
    func add(_ reminder: ExpiryReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.body
        content.sound = .default
        try await center.add(UNNotificationRequest(identifier: reminder.identifier, content: content,
                                                   trigger: UNCalendarNotificationTrigger(dateMatching: reminder.components, repeats: false)))
    }
    func remove(identifiers: [String]) { center.removePendingNotificationRequests(withIdentifiers: identifiers) }
}

/// One worker reconciles the latest saved inventory after writes, preference changes and clock changes.
/// Coalescing avoids overlapping reconciliations leaving stale notifications behind.
@MainActor
@Observable
final class NotificationService {
    private(set) var preferences: ReminderPreferences
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    private(set) var errorMessage: String?
    private(set) var pendingCount = 0
    private(set) var isRequestingPermission = false
    private let repository: any PantryRepositoryProtocol
    private let center: any ExpiryNotificationCenter
    private let defaults: UserDefaults
    private let now: () -> Date
    private let calendar: () -> Calendar
    private var subscription: AnyCancellable?
    private var worker: Task<Void, Never>?
    private var needsReconciliation = false

    init(repository: any PantryRepositoryProtocol, center: (any ExpiryNotificationCenter)? = nil,
         defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         calendar: @escaping () -> Calendar = { .autoupdatingCurrent }) {
        self.repository = repository
        self.center = center ?? SystemExpiryNotificationCenter()
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        preferences = ReminderPreferences.load(from: defaults)
        subscription = repository.changes.sink { [weak self] in self?.refresh() }
    }

    func setEnabled(_ enabled: Bool) async {
        guard !isRequestingPermission else { return }
        if enabled {
            isRequestingPermission = true
            defer { isRequestingPermission = false }
            authorization = await center.authorizationStatus()
            if authorization == .notDetermined {
                do {
                    _ = try await center.requestAuthorization()
                    authorization = await center.authorizationStatus()
                } catch {
                    errorMessage = "Unable to request reminders: \(error.localizedDescription)"
                    return
                }
            }
        }
        // Retain the user's preference when OS access is denied, so Settings can explain how to enable access.
        preferences.enabled = enabled
        persistAndRefresh()
        await waitForReconciliation()
    }

    func setTime(hour: Int, minute: Int) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return }
        preferences.hour = hour
        preferences.minute = minute
        persistAndRefresh()
    }

    func setKind(_ kind: ExpiryReminderKind, enabled: Bool) {
        if enabled { preferences.kinds.insert(kind) } else { preferences.kinds.remove(kind) }
        persistAndRefresh()
    }

    private func persistAndRefresh() {
        do { defaults.set(try JSONEncoder().encode(preferences), forKey: ReminderPreferences.storageKey) }
        catch { errorMessage = "Unable to save reminder preferences: \(error.localizedDescription)"; return }
        refresh()
    }

    private var active = true
    func deactivate() {
        active = false
        needsReconciliation = false
        subscription?.cancel()
        worker?.cancel()
    }
    func refresh() {
        guard active else { return }
        needsReconciliation = true
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            while self.needsReconciliation {
                self.needsReconciliation = false
                await self.reconcile()
            }
            self.worker = nil
        }
    }

    func waitForReconciliation() async { await worker?.value }

    private func reconcile() async {
        authorization = await center.authorizationStatus()
        let pending = await center.pending()
        guard active, !Task.isCancelled else { return }
        let owned = pending.filter { $0.identifier.hasPrefix(ExpiryReminder.prefix) }
        let permitted = authorization == .authorized || authorization == .provisional || authorization == .ephemeral
        guard preferences.enabled, permitted else {
            center.remove(identifiers: owned.map(\.identifier))
            pendingCount = 0
            errorMessage = nil
            return
        }
        do {
            let items = try repository.fetchActive(sort: .createdNewest)
            let desired = ExpiryReminderPlanner.plan(items: items, preferences: preferences, now: now(), calendar: calendar(),
                                                     capacity: max(0, ExpiryReminderPlanner.pendingBudget - (pending.count - owned.count)))
            center.remove(identifiers: owned.filter { existing in
                !desired.contains { existing.matches($0) }
            }.map(\.identifier))
            for reminder in desired {
                guard active, !Task.isCancelled else { return }
                // Remove outdated content first, so an add failure cannot leave an incorrect old date scheduled.
                if !owned.contains(where: { $0.matches(reminder) }) { try await center.add(reminder) }
            }
            pendingCount = desired.count
            errorMessage = nil
        } catch {
            // Keep a visible error and retry on the next change/foreground activation or explicit retry.
            errorMessage = "Unable to update expiry reminders: \(error.localizedDescription)"
            pendingCount = await center.pending().filter { $0.identifier.hasPrefix(ExpiryReminder.prefix) }.count
        }
    }
}

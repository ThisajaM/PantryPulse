import Foundation

enum ExpiryReminderKind: String, CaseIterable, Codable, Identifiable {
    case threeDays, oneDay, expiryDay
    var id: Self { self }
    var daysBefore: Int {
        switch self { case .threeDays: 3; case .oneDay: 1; case .expiryDay: 0 }
    }
    var title: String {
        switch self { case .threeDays: "Three days before"; case .oneDay: "One day before"; case .expiryDay: "On expiry day" }
    }
}

struct ReminderPreferences: Codable, Equatable {
    var enabled = false
    var hour = 9
    var minute = 0
    var kinds = Set(ExpiryReminderKind.allCases)

    static let storageKey = "pantrypulse.expiryReminders"
    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: storageKey),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              (0...23).contains(value.hour), (0...59).contains(value.minute) else { return Self() }
        return value
    }
}

struct ExpiryReminder: Equatable {
    static let prefix = "pantrypulse.expiry."
    let identifier: String
    let title: String
    let body: String
    let fireDate: Date
    let components: DateComponents
}

/// Pure scheduling policy. The nearest reminders get the bounded pending budget.
enum ExpiryReminderPlanner {
    static let pendingBudget = 60

    static func plan(items: [PantryItem], preferences: ReminderPreferences, now: Date,
                     calendar: Calendar = .autoupdatingCurrent, capacity: Int = pendingBudget) -> [ExpiryReminder] {
        guard preferences.enabled, (0...23).contains(preferences.hour),
              (0...59).contains(preferences.minute), capacity > 0 else { return [] }
        var reminders: [String: ExpiryReminder] = [:]
        for item in items where item.status == .active {
            guard let expiry = item.expiryDate,
                  ExpiryService.assess(expiry, on: now, calendar: calendar).freshness != .expired else { continue }
            for kind in preferences.kinds {
                guard let day = calendar.date(byAdding: .day, value: -kind.daysBefore, to: calendar.startOfDay(for: expiry)),
                      let date = calendar.date(bySettingHour: preferences.hour, minute: preferences.minute, second: 0,
                                               of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward),
                      calendar.isDate(date, inSameDayAs: day), date > now else { continue }
                let id = "\(ExpiryReminder.prefix)\(item.id.uuidString).\(kind.rawValue)"
                var components = calendar.dateComponents([.era, .year, .month, .day, .hour, .minute, .second], from: date)
                components.calendar = calendar
                components.timeZone = calendar.timeZone
                let message = kind == .expiryDay
                    ? "\(item.name) reaches its recorded expiry date today. Review it in your pantry."
                    : "\(item.name) reaches its recorded expiry date in \(kind.daysBefore) days."
                reminders[id] = ExpiryReminder(identifier: id, title: "PantryPulse expiry reminder", body: message,
                                              fireDate: date, components: components)
            }
        }
        return Array(reminders.values.sorted {
            $0.fireDate == $1.fireDate ? $0.identifier < $1.identifier : $0.fireDate < $1.fireDate
        }.prefix(min(capacity, pendingBudget)))
    }
}

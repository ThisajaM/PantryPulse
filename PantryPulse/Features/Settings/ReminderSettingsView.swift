import SwiftUI

struct ReminderSettingsView: View {
    let service: NotificationService
    @Environment(\.openURL) private var openURL

    var body: some View {
        Form {
            Section {
                Toggle("Expiry Reminders", isOn: Binding(get: { service.preferences.enabled }, set: { enabled in
                    Task { await service.setEnabled(enabled) }
                }))
                .disabled(service.isRequestingPermission)
                .accessibilityIdentifier("reminders.enabled")
                if service.isRequestingPermission { ProgressView("Checking notification permission") }
            } footer: {
                Text("Reminders use the expiry dates you enter. They do not determine whether food is safe to eat.")
            }
            if service.preferences.enabled {
                Section("Schedule") {
                    DatePicker("Reminder Time", selection: Binding(get: {
                        Calendar.current.date(from: DateComponents(hour: service.preferences.hour, minute: service.preferences.minute)) ?? Date()
                    }, set: { date in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                        service.setTime(hour: parts.hour ?? 9, minute: parts.minute ?? 0)
                    }), displayedComponents: .hourAndMinute)
                    ForEach(ExpiryReminderKind.allCases) { kind in
                        Toggle(kind.title, isOn: Binding(get: { service.preferences.kinds.contains(kind) }, set: { service.setKind(kind, enabled: $0) }))
                    }
                }
                Section("Notification access") {
                    if service.authorization == .denied {
                        Text("Notifications are blocked in iOS Settings. No expiry reminders will be scheduled until access is allowed.")
                        Button("Open iOS Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                    } else {
                        Text("\(service.pendingCount) reminders scheduled")
                    }
                    Text("Only future reminders for active foods with expiry dates are scheduled. Up to 60 of the nearest reminders are kept; opening the app refreshes the schedule. Delivery may be affected by iOS Focus and notification settings.")
                        .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                }
            }
            if let error = service.errorMessage {
                Section("Reminders need attention") {
                    Text(error)
                    Button("Retry") { service.refresh() }
                }
            }
        }
        .tint(PPColors.actionText)
        .scrollContentBackground(.hidden)
        .background(PPColors.background)
        .navigationTitle("Expiry Reminders")
        .navigationBarTitleDisplayMode(.inline)
        .task { service.refresh() }
    }
}

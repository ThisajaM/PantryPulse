import SwiftUI

/// Account access and device-local preferences.
struct SettingsView: View {
    @Environment(AccountSession.self) private var session
    let onStorage: () -> Void
    let onNotifications: () -> Void
    let onRecognition: () -> Void
    let onAbout: () -> Void
    @State private var showsIntroduction = false

    var body: some View {
        List {
            Section {
                VStack(spacing: PPSpacing.sm) {
                    Image(systemName: "leaf.circle").font(.largeTitle).foregroundStyle(PPColors.actionText)
                        .accessibilityHidden(true)
                    Text(profileTitle).font(PPTypography.screenTitle)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("settings.profileName")
                    Text("Your pantry preferences").font(PPTypography.body).foregroundStyle(PPColors.secondaryText)
                }
                .frame(maxWidth: .infinity).padding(.vertical, PPSpacing.md)
            }
            .listRowBackground(PPColors.surface)

            Section {
                setting("Default Storage", symbol: "refrigerator", action: onStorage)
                setting("Expiry Reminders", symbol: "bell", action: onNotifications)
                setting("AI Recognition", symbol: "sparkles", action: onRecognition)
                LabeledContent("Appearance", value: "System")
                    .font(PPTypography.body)
            } header: {
                Text("Preferences")
            }
            .listRowBackground(PPColors.surface)

            Section("Account") {
                NavigationLink { AccountView() } label: {
                    Label("Account & Profile", systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
            .listRowBackground(PPColors.surface)

            Section("Application") {
                setting("Review Introduction", symbol: "book") { showsIntroduction = true }
                setting("About PantryPulse", symbol: "info.circle", action: onAbout)
            }
            .listRowBackground(PPColors.surface)
        }
        .foregroundStyle(PPColors.text)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(PPColors.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $showsIntroduction) {
            OnboardingView { showsIntroduction = false }
        }
    }

    private var profileTitle: String {
        guard let profile = session.profile else { return "PantryPulse" }
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? profile.email : name
    }

    private func setting(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { NavigationRowLabel(title: title, systemImage: symbol) }
            .tint(PPColors.actionText)
    }
}

#Preview {
    NavigationStack { SettingsView(onStorage: {}, onNotifications: {}, onRecognition: {}, onAbout: {}) }
        .environment(AccountSession())
}

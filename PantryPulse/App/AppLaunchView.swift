import SwiftUI

/// Onboarding is installation-wide; pantry storage and locking are account-specific.
struct AppLaunchView: View {
    @Environment(AccountSession.self) private var session
    @Environment(AppLock.self) private var lock
    @AppStorage("pantrypulse.onboardingCompleted") private var onboardingCompleted = false
    @State private var workspace = AccountWorkspace()

    var body: some View {
        Group {
            if !onboardingCompleted {
                OnboardingView { onboardingCompleted = true }
            } else if session.restoring {
                LoadingStateView(title: "Restoring account")
            } else if let profile = session.profile {
                if workspace.uid == profile.id, let pantry = workspace.pantry {
                    AppRootView(pantry: pantry, reminders: workspace.reminders)
                        .environment(\.accountResources, workspace.resources)
                        .defaultAppStorage(workspace.preferences)
                        .id(profile.id)
                } else if let error = workspace.error {
                    ContentUnavailableView {
                        Label("Storage unavailable", systemImage: "externaldrive.badge.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Retry") { selectAccount() }
                        Button("Sign Out") { session.signOut() }
                    }
                } else {
                    LoadingStateView(title: "Opening your pantry")
                }
            } else {
                NavigationStack { AccountView() }
            }
        }
        .onChange(of: session.profile?.id, initial: true) { _, _ in selectAccount() }
    }

    private func selectAccount() {
        lock.selectAccount(session.profile?.id)
        workspace.select(uid: session.profile?.id, base: storageBase)
    }

    private var storageBase: URL {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["PANTRYPULSE_UI_TEST_DEFAULTS"],
           suite.hasPrefix("PantryPulse.UITests."),
           let id = UUID(uuidString: String(suite.dropFirst("PantryPulse.UITests.".count))) {
            return FileManager.default.temporaryDirectory.appendingPathComponent("AccountsUITest-\(id)")
        }
        #endif
        return .applicationSupportDirectory
    }
}

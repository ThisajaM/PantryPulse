import SwiftUI
import FirebaseCore

@main
struct PantryPulseApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var session = AccountSession()
    @State private var appLock: AppLock

    init() {
        #if DEBUG
        if let suite = ProcessInfo.processInfo.environment["PANTRYPULSE_UI_TEST_DEFAULTS"],
           suite.hasPrefix("PantryPulse.UITests."), let defaults = UserDefaults(suiteName: suite) {
            _appLock = State(initialValue: AppLock(defaults: defaults))
            if let fixture = ProcessInfo.processInfo.environment["PANTRYPULSE_UI_TEST_ACCOUNT"] {
                _session = State(initialValue: AccountSession(client: AccountUITestClient(defaults: defaults, initialUID: fixture.isEmpty ? nil : fixture)))
            }
        } else if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            _appLock = State(initialValue: AppLock(defaults: UserDefaults(suiteName: "PantryPulse.LockTests.\(UUID())")!))
        } else {
            _appLock = State(initialValue: AppLock())
        }
        #else
        _appLock = State(initialValue: AppLock())
        #endif
        // Unit/UI fixtures never contact the production authentication backend.
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["XCTestConfigurationFilePath"] != nil || environment["PANTRYPULSE_UI_TEST_DEFAULTS"] != nil || environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return }
        #endif
        if FirebaseApp.app() == nil,
           let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let options = FirebaseOptions(contentsOfFile: path),
           options.bundleID == Bundle.main.bundleIdentifier {
            FirebaseApp.configure(options: options)
        }
    }

    var body: some Scene {
        WindowGroup {
            AppLaunchView()
                .defaultAppStorage(preferences)
                .environment(session)
                .environment(appLock)
                .disabled(appLock.locked)
                .accessibilityHidden(appLock.locked)
                .background(AppPrivacyShield(lock: appLock, phase: scenePhase, session: session))
                .task { session.start() }
                .onChange(of: scenePhase) { _, phase in appLock.sceneChanged(phase) }
        }
    }

    private var preferences: UserDefaults {
        #if DEBUG
        // UI tests get an isolated, persistent suite without resetting user preferences.
        if let suite = ProcessInfo.processInfo.environment["PANTRYPULSE_UI_TEST_DEFAULTS"],
           suite.hasPrefix("PantryPulse.UITests."), let defaults = UserDefaults(suiteName: suite) {
            return defaults
        }
        #endif
        return .standard
    }
}

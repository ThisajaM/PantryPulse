import FirebaseAuth
import FirebaseCore
import Foundation
import Testing
@testable import PantryPulse

/// Explicit opt-in integration check. Uses a real Firebase project and a user-authorized test email.
/// The generated password is never logged or persisted by the test; the user receives a reset email.
@MainActor
struct FirebaseLiveAccountTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PANTRYPULSE_AUTH_TEST_EMAIL"] != nil))
    func liveRegistrationLoginProfileResetAndLogout() async throws {
        let email = try #require(ProcessInfo.processInfo.environment["PANTRYPULSE_AUTH_TEST_EMAIL"])
        let path = try #require(Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"))
        let options = try #require(FirebaseOptions(contentsOfFile: path))
        let name = "AccountIntegrationCheck"
        if FirebaseApp.app(name: name) == nil { FirebaseApp.configure(name: name, options: options) }
        let app = try #require(FirebaseApp.app(name: name))
        let auth = Auth.auth(app: app)
        print("Live auth: clear isolated test session")
        try auth.signOut()
        let password = UUID().uuidString + "aA7!"
        let client = FirebaseAccountClient(auth: auth)
        print("Live auth: register authorized test account")
        let created = try await client.register(email: email, password: password)
        #expect(created.email == email)
        let profile = try await client.updateName("PantryPulse Test")
        #expect(profile.name == "PantryPulse Test")
        do {
            _ = try await client.register(email: email, password: password)
            Issue.record("Duplicate account registration unexpectedly succeeded")
        } catch {
            #expect((error as NSError).code == AuthErrorCode.emailAlreadyInUse.rawValue)
        }
        try client.signOut()
        #expect(auth.currentUser == nil)
        do {
            try await client.signIn(email: email, password: UUID().uuidString)
            Issue.record("Incorrect credentials unexpectedly succeeded")
        } catch {
            #expect(auth.currentUser == nil)
        }
        try await client.signIn(email: email, password: password)
        #expect(auth.currentUser?.uid == created.id)
        try await client.resetPassword(email: email)
        try client.signOut()
        #expect(auth.currentUser == nil)
        // Leave only the isolated integration session for a separate-process restore check.
        try await client.signIn(email: email, password: password)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["PANTRYPULSE_AUTH_RESTORE_EMAIL"] != nil))
    func restoresSessionInSeparateProcessThenLogsOut() throws {
        let email = try #require(ProcessInfo.processInfo.environment["PANTRYPULSE_AUTH_RESTORE_EMAIL"])
        let path = try #require(Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"))
        let options = try #require(FirebaseOptions(contentsOfFile: path))
        let name = "AccountIntegrationCheck"
        if FirebaseApp.app(name: name) == nil { FirebaseApp.configure(name: name, options: options) }
        let app = try #require(FirebaseApp.app(name: name))
        let auth = Auth.auth(app: app)
        #expect(auth.currentUser?.email == email)
        try auth.signOut()
        #expect(auth.currentUser == nil)
    }
}

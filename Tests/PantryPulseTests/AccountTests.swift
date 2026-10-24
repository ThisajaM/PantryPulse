import Foundation
import Testing
import SwiftUI
@testable import PantryPulse

@MainActor
struct AccountTests {
    @Test func sessionRestorationRegistrationLoginLogoutAndReset() async {
        let backend = TestAccountClient()
        let session = AccountSession(client: backend)
        session.start()
        #expect(!session.restoring)
        await session.submit(email: " test@example.com ", password: "test-password", name: " Test User ")
        #expect(session.profile?.name == "Test User")
        #expect(backend.email == "test@example.com")
        await session.resetPassword(email: "test@example.com")
        #expect(backend.resetRequested)
        session.signOut()
        #expect(session.profile == nil)
        #expect(session.signOutRevision == 1)
        await session.submit(email: "test@example.com", password: "test-password", name: nil)
        #expect(session.profile?.id == "fixture-account")
        let restored = AccountSession(client: backend)
        restored.start()
        #expect(restored.profile == session.profile)
    }

    @Test func validationAndBackendFailureDoNotInventSession() async {
        let backend = TestAccountClient()
        let session = AccountSession(client: backend)
        session.start()
        await session.submit(email: "", password: "", name: nil)
        #expect(backend.calls == 0)
        backend.failure = NSError(domain: "FIRAuthErrorDomain", code: 17020)
        await session.submit(email: "test@example.com", password: "test-password", name: nil)
        #expect(session.profile == nil)
        #expect(session.message?.contains("internet") == true)
        #expect(!session.busy)
        #expect(AccountSession.explanation(NSError(domain: "FIRAuthErrorDomain", code: 17007)).contains("already"))
        #expect(AccountSession.explanation(NSError(domain: "FIRAuthErrorDomain", code: 17009)).contains("incorrect"))
    }

    @Test func failedSignOutDoesNotRestartApp() async {
        let backend = TestAccountClient()
        let session = AccountSession(client: backend)
        session.start()
        await session.submit(email: "test@example.com", password: "password", name: nil)
        backend.failure = NSError(domain: "FIRAuthErrorDomain", code: 17020)
        session.signOut()
        #expect(session.profile != nil)
        #expect(session.signOutRevision == 0)
        #expect(session.message != nil)
    }

    @Test func unavailableAuthenticationDoesNotEnableLock() async throws {
        let suite = "PantryPulse.AuthTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = TestDeviceAuthenticator()
        device.failure = NSError(domain: "com.apple.LocalAuthentication", code: -6)
        let lock = AppLock(defaults: defaults, authenticator: device)
        lock.selectAccount("A")
        await lock.setEnabled(true)
        #expect(!lock.enabled && !lock.locked)
        #expect(lock.message?.contains("Face ID") == true)
    }

    @Test func backgroundRejectsLateAuthenticationSuccess() async throws {
        let suite = "PantryPulse.AuthTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "pantrypulse.faceID." + AccountStoragePaths(uid: "A").key)
        let device = SuspendedAuthenticator()
        let lock = AppLock(defaults: defaults, authenticator: device)
        lock.selectAccount("A")
        let pending = Task { await lock.unlock() }
        while device.continuation == nil { await Task.yield() }
        lock.sceneChanged(.background)
        device.continuation?.resume(returning: true)
        await pending.value
        #expect(lock.locked)
    }

    @Test func faceIDPreferenceIsAccountSpecificAndUnavailableDeviceCannotEnableIt() async throws {
        let suite = "PantryPulse.AuthTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = TestDeviceAuthenticator()
        let lock = AppLock(defaults: defaults, authenticator: device)
        lock.selectAccount("A")
        await lock.setEnabled(true)
        #expect(lock.enabled)
        lock.selectAccount("B")
        #expect(!lock.enabled && !lock.locked)
        device.faceIDAvailable = false
        await lock.setEnabled(true)
        #expect(!lock.enabled)
        lock.selectAccount("A")
        #expect(lock.enabled && lock.locked)
        device.succeeds = false
        await lock.unlock()
        #expect(lock.locked)
        lock.selectAccount(nil)
        #expect(!lock.locked && !lock.enabled)
        lock.selectAccount("A")
        #expect(lock.locked)
        lock.recoverAfterSignOut(uid: "A")
        #expect(lock.locked)
        lock.selectAccount(nil)
        lock.selectAccount("B")
        #expect(!lock.enabled)
        lock.selectAccount("A")
        #expect(!lock.enabled && !lock.locked)
    }

    @Test func lockPersistsAndRelocksOnlyAfterBackground() async throws {
        let suite = "PantryPulse.AuthTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let device = TestDeviceAuthenticator()
        let lock = AppLock(defaults: defaults, authenticator: device)
        lock.selectAccount("A")
        await lock.setEnabled(true)
        #expect(lock.enabled && !lock.locked)
        lock.sceneChanged(.inactive)
        #expect(!lock.locked)
        lock.sceneChanged(.background)
        #expect(lock.locked)
        #expect(device.cancelled)
        let restored = AppLock(defaults: defaults, authenticator: device)
        restored.selectAccount("A")
        #expect(restored.locked)
        device.succeeds = false
        await restored.unlock()
        #expect(restored.locked)
        device.succeeds = true
        await restored.unlock()
        #expect(!restored.locked)
        await restored.setEnabled(false)
        #expect(!restored.enabled)
    }
}

@MainActor
private final class TestAccountClient: AccountClient {
    var profile: AccountProfile?
    var callback: (@MainActor (AccountProfile?) -> Void)?
    var email = ""
    var calls = 0
    var resetRequested = false
    var failure: Error?
    func observe(_ change: @escaping @MainActor (AccountProfile?) -> Void) { callback = change; change(profile) }
    func register(email: String, password: String) async throws -> AccountProfile {
        try await signIn(email: email, password: password)
        return profile!
    }
    func signIn(email: String, password: String) async throws {
        calls += 1
        if let failure { throw failure }
        self.email = email
        profile = AccountProfile(id: "fixture-account", email: email, name: "")
        callback?(profile)
    }
    func updateName(_ name: String) async throws -> AccountProfile {
        let updated = AccountProfile(id: "fixture-account", email: email, name: name)
        profile = updated; callback?(updated); return updated
    }
    func resetPassword(email: String) async throws { resetRequested = true }
    func signOut() throws { if let failure { throw failure }; profile = nil; callback?(nil) }
}

@MainActor
private final class TestDeviceAuthenticator: DeviceAuthenticator {
    var faceIDAvailable = true
    var succeeds = true
    var cancelled = false
    var failure: Error?
    func authenticate(reason: String) async throws -> Bool {
        if let failure { throw failure }
        return succeeds
    }
    func cancel() { cancelled = true }
}

@MainActor
private final class SuspendedAuthenticator: DeviceAuthenticator {
    var faceIDAvailable = true
    var continuation: CheckedContinuation<Bool, Never>?
    func authenticate(reason: String) async throws -> Bool {
        await withCheckedContinuation { continuation = $0 }
    }
    func cancel() {}
}

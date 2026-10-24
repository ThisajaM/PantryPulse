#if DEBUG
import Foundation

/// Explicit UI-test boundary; never constructed in Release or during a normal launch.
@MainActor final class AccountUITestClient: AccountClient {
    private let defaults: UserDefaults
    private var callback: (@MainActor (AccountProfile?) -> Void)?
    private var profile: AccountProfile?
    init(defaults: UserDefaults, initialUID: String?) {
        self.defaults = defaults
        let uid = defaults.object(forKey: "test.account.uid") == nil ? initialUID : defaults.string(forKey: "test.account.uid")
        if let uid, !uid.isEmpty { profile = AccountProfile(id: uid, email: uid + "@example.com", name: defaults.string(forKey: "test.account.name.\(uid)") ?? "Test User") }
    }
    func observe(_ change: @escaping @MainActor (AccountProfile?) -> Void) { callback = change; change(profile) }
    func register(email: String, password: String) async throws -> AccountProfile {
        try await signIn(email: email, password: password)
        return profile!
    }
    func signIn(email: String, password: String) async throws {
        let uid = email.components(separatedBy: "@")[0]
        profile = AccountProfile(id: uid, email: email, name: defaults.string(forKey: "test.account.name.\(uid)") ?? "Test User")
        defaults.set(uid, forKey: "test.account.uid")
        callback?(profile)
    }
    func updateName(_ name: String) async throws -> AccountProfile {
        guard let old = profile else { throw PersistenceError.storeUnavailable }
        let updated = AccountProfile(id: old.id, email: old.email, name: name)
        profile = updated
        defaults.set(name, forKey: "test.account.name.\(old.id)")
        callback?(updated)
        return updated
    }
    func resetPassword(email: String) async throws {}
    func signOut() throws { profile = nil; defaults.set("", forKey: "test.account.uid"); callback?(nil) }
}
#endif

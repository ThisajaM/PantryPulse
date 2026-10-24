import FirebaseAuth

@MainActor
protocol AccountClient: AnyObject {
    func observe(_ change: @escaping @MainActor (AccountProfile?) -> Void)
    func register(email: String, password: String) async throws -> AccountProfile
    func signIn(email: String, password: String) async throws
    func updateName(_ name: String) async throws -> AccountProfile
    func resetPassword(email: String) async throws
    func signOut() throws
}

@MainActor
final class FirebaseAccountClient: AccountClient {
    private let auth: Auth
    private var listener: AuthStateDidChangeListenerHandle?
    init(auth: Auth) { self.auth = auth }

    func observe(_ change: @escaping @MainActor (AccountProfile?) -> Void) {
        if let listener { auth.removeStateDidChangeListener(listener) }
        listener = auth.addStateDidChangeListener { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let current = self.auth.currentUser
                change(current.map { AccountProfile(id: $0.uid, email: $0.email ?? "", name: $0.displayName ?? "") })
            }
        }
    }

    func register(email: String, password: String) async throws -> AccountProfile {
        let user = try await auth.createUser(withEmail: email, password: password).user
        return AccountProfile(id: user.uid, email: user.email ?? "", name: user.displayName ?? "")
    }
    func signIn(email: String, password: String) async throws {
        _ = try await auth.signIn(withEmail: email, password: password)
    }
    func updateName(_ name: String) async throws -> AccountProfile {
        guard let user = auth.currentUser else { throw NSError(domain: "Account", code: 0) }
        let request = user.createProfileChangeRequest()
        request.displayName = name
        try await request.commitChanges()
        return AccountProfile(id: user.uid, email: user.email ?? "", name: user.displayName ?? name)
    }
    func resetPassword(email: String) async throws { try await auth.sendPasswordReset(withEmail: email) }
    func signOut() throws { try auth.signOut() }
}

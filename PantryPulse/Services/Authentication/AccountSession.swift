import FirebaseAuth
import FirebaseCore
import Observation

struct AccountProfile: Equatable {
    let id: String
    let email: String
    let name: String
}

@MainActor
@Observable
final class AccountSession {
    private(set) var profile: AccountProfile?
    private(set) var restoring = true
    private(set) var busy = false
    private(set) var signOutRevision = 0
    var message: String?
    private var client: (any AccountClient)?
    private var started = false

    init(client: (any AccountClient)? = nil) { self.client = client }

    func start() {
        guard !started else { return }
        started = true
        if client == nil, FirebaseApp.app() != nil {
            client = FirebaseAccountClient(auth: Auth.auth())
        }
        guard let client else {
            restoring = false
            message = "Sign-in is unavailable right now. Please try again later."
            return
        }
        client.observe { [weak self] profile in
            self?.profile = profile
            self?.restoring = false
        }
    }

    func submit(email: String, password: String, name: String?) async {
        guard !busy, let client else { return }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !password.isEmpty else { message = "Enter your email and password."; return }
        if let name, name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = "Enter your name."; return
        }
        busy = true
        message = nil
        defer { busy = false }
        do {
            if let name {
                let registered = try await client.register(email: email, password: password)
                guard profile?.id == registered.id else { return }
                do {
                    let updated = try await client.updateName(name.trimmingCharacters(in: .whitespacesAndNewlines))
                    guard profile?.id == registered.id, updated.id == registered.id else { return }
                    profile = updated
                }
                catch { message = "Your account was created, but your name could not be saved. Try updating it in Profile." }
            } else {
                try await client.signIn(email: email, password: password)
            }
        } catch { message = Self.explanation(error) }
    }

    func updateName(_ name: String) async {
        guard !busy, let client, profile != nil else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { message = "Enter your name."; return }
        busy = true
        defer { busy = false }
        do {
            let uid = profile?.id
            let updated = try await client.updateName(name)
            guard profile?.id == uid, updated.id == uid else { return }
            profile = updated
            message = "Profile updated."
        } catch { message = Self.explanation(error) }
    }

    func resetPassword(email: String) async {
        guard !busy, let client else { return }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty else { message = "Enter your account email first."; return }
        busy = true
        defer { busy = false }
        do {
            try await client.resetPassword(email: email)
            message = "If this email has an account, a password reset email will arrive shortly. Check your spam folder too."
        } catch { message = Self.explanation(error) }
    }

    func signOut() {
        guard !busy, let client else { return }
        do {
            try client.signOut()
            profile = nil
            message = nil
            signOutRevision += 1
        }
        catch { message = Self.explanation(error) }
    }

    static func explanation(_ error: Error) -> String {
        switch AuthErrorCode(rawValue: (error as NSError).code) {
        case .invalidEmail: "Enter a valid email address."
        case .emailAlreadyInUse: "An account already uses this email. Sign in or reset your password."
        case .weakPassword: "Choose a stronger password that meets the account password policy."
        case .wrongPassword, .invalidCredential, .userNotFound: "The email or password is incorrect. Try again or reset your password."
        case .networkError: "Unable to connect. Check your internet connection and try again."
        case .tooManyRequests: "Too many attempts. Please wait before trying again."
        case .userDisabled: "This account has been disabled. Contact the app administrator."
        case .operationNotAllowed: "Sign-in is unavailable right now. Please try again later."
        default: "The account request could not be completed. Please try again."
        }
    }
}

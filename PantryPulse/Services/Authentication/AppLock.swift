import LocalAuthentication
import Observation
import SwiftUI

@MainActor
protocol DeviceAuthenticator {
    func authenticate(reason: String) async throws -> Bool
    var faceIDAvailable: Bool { get }
    func cancel()
}

@MainActor
final class SystemDeviceAuthenticator: DeviceAuthenticator {
    private var context: LAContext?
    var faceIDAvailable: Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) && context.biometryType == .faceID
    }
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        self.context = context
        defer { self.context = nil }
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error), context.biometryType == .faceID else {
            throw error ?? NSError(domain: LAError.errorDomain, code: LAError.biometryNotAvailable.rawValue)
        }
        context.localizedFallbackTitle = ""
        return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
    }
    func cancel() { context?.invalidate() }
}

@MainActor
@Observable
final class AppLock {
    private let defaults: UserDefaults
    private let authenticator: any DeviceAuthenticator
    private(set) var enabled: Bool
    private(set) var locked: Bool
    private(set) var evaluating = false
    var message: String?
    private var generation = 0
    private var preferenceKey: String?
    private var recoveryUID: String?
    var faceIDAvailable: Bool { authenticator.faceIDAvailable }

    init(defaults: UserDefaults = .standard, authenticator: (any DeviceAuthenticator)? = nil) {
        self.defaults = defaults
        self.authenticator = authenticator ?? SystemDeviceAuthenticator()
        enabled = false
        locked = false
    }

    func selectAccount(_ uid: String?) {
        generation += 1
        authenticator.cancel()
        preferenceKey = uid.map { "pantrypulse.faceID." + AccountStoragePaths(uid: $0).key }
        if let uid, uid == recoveryUID, let preferenceKey {
            // Recovery is requested only after genuine sign-out; the next account session
            // must be authenticated again before this device preference can be cleared.
            defaults.set(false, forKey: preferenceKey)
            recoveryUID = nil
        }
        enabled = preferenceKey.map { defaults.bool(forKey: $0) } ?? false
        locked = enabled
        message = enabled && !faceIDAvailable ? "Face ID is unavailable. Try again after enabling Face ID in Settings, or sign out to use account authentication." : nil
    }

    func recoverAfterSignOut(uid: String) { recoveryUID = uid }

    func sceneChanged(_ phase: ScenePhase) {
        if phase == .background {
            generation += 1
            authenticator.cancel()
            if enabled { locked = true }
        }
    }

    func setEnabled(_ value: Bool) async {
        guard !evaluating, let preferenceKey else { return }
        guard !value || faceIDAvailable else { message = "Face ID is unavailable or not enrolled on this device."; return }
        guard await authenticate(reason: value ? "Enable protection for your local pantry." : "Turn off pantry app locking.") else { return }
        enabled = value
        locked = false
        defaults.set(value, forKey: preferenceKey)
    }

    func unlock() async {
        if await authenticate(reason: "Unlock your PantryPulse data.") { locked = false }
    }

    private func authenticate(reason: String) async -> Bool {
        guard !evaluating else { return false }
        evaluating = true
        message = nil
        let request = generation
        defer { evaluating = false }
        do {
            let success = try await authenticator.authenticate(reason: reason)
            return success && request == generation
        } catch {
            guard request == generation else { return false }
            if (error as NSError).code == LAError.biometryNotAvailable.rawValue {
                message = "Face ID is unavailable or not enrolled on this device."
            } else {
                message = "Face ID did not unlock PantryPulse. Try again, or sign out to return to account authentication."
            }
            return false
        }
    }
}

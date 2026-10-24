import CoreData
import CryptoKit
import Observation
import SwiftUI
import UserNotifications

/// Stable UID paths deliberately exclude the unowned, pre-account store.
nonisolated struct AccountStoragePaths: Sendable {
    let root: URL
    let key: String
    init(uid: String, base: URL = .applicationSupportDirectory) {
        key = SHA256.hash(data: Data(uid.utf8)).map { String(format: "%02x", $0) }.joined()
        root = base.appendingPathComponent("Accounts/\(key)", isDirectory: true)
    }
    var storeURL: URL { root.appendingPathComponent("PantryPulse.sqlite") }
    var photos: FoodPhotoStorage { FoodPhotoStorage(root: root, allowsLegacyPaths: false) }
    var catalogue: ProductCatalogue { ProductCatalogue(url: root.appendingPathComponent("ProductCatalogue/Products.json")) }
}

struct AccountResources: Sendable {
    var photos = FoodPhotoStorage()
    var catalogue = ProductCatalogue()
}
private struct AccountResourcesKey: EnvironmentKey {
    static let defaultValue = AccountResources()
}
extension EnvironmentValues {
    var accountResources: AccountResources {
        get { self[AccountResourcesKey.self] }
        set { self[AccountResourcesKey.self] = newValue }
    }
}

/// Account transitions hide snapshots synchronously, then serialize notification/store teardown.
@MainActor @Observable
final class AccountWorkspace {
    private(set) var uid: String?
    private(set) var pantry: PantryViewModel?
    private(set) var reminders: NotificationService?
    private(set) var resources = AccountResources()
    private(set) var preferences = UserDefaults.standard
    private(set) var error: String?
    private var persistence: PersistenceController?
    private var repository: PantryRepository?
    private var transition: Task<Void, Never>?
    private var revision = UUID()

    func select(uid: String?, base: URL = .applicationSupportDirectory) {
        let revision = UUID()
        self.revision = revision
        let oldPersistence = persistence
        let oldReminders = reminders
        pantry?.deactivate()
        repository?.invalidate()
        oldReminders?.deactivate()
        pantry = nil; reminders = nil; repository = nil; persistence = nil
        self.uid = nil; error = nil
        let previous = transition
        transition = Task {
            await previous?.value
            await oldReminders?.waitForReconciliation()
            await Self.clearReminders()
            do { try oldPersistence?.close() }
            catch { if self.revision == revision { self.error = "Unable to close local storage. Please restart the app." }; return }
            guard self.revision == revision, let uid else { return }
            let paths = AccountStoragePaths(uid: uid, base: base)
            let storage = PersistenceController(storeURL: paths.storeURL)
            await storage.load()
            guard self.revision == revision else { try? storage.close(); return }
            guard let container = storage.container else {
                self.error = storage.loadError?.localizedDescription ?? "Unable to open your pantry."
                return
            }
            let repository = PantryRepository(container: container, photos: paths.photos)
            self.persistence = storage
            self.repository = repository
            self.resources = AccountResources(photos: paths.photos, catalogue: paths.catalogue)
            let suite = base == URL.applicationSupportDirectory
                ? "PantryPulse.Account.\(paths.key)"
                : "PantryPulse.TestAccount.\(AccountStoragePaths(uid: base.path).key).\(paths.key)"
            self.preferences = UserDefaults(suiteName: suite)!
            self.pantry = PantryViewModel(repository: repository, riskService: WasteRiskService())
            self.reminders = NotificationService(repository: repository, defaults: self.preferences)
            self.uid = uid
        }
    }

    func waitForTransition() async { await transition?.value }

    private static func clearReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.filter { $0.identifier.hasPrefix(ExpiryReminder.prefix) }.map(\.identifier))
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix(ExpiryReminder.prefix) }.map { $0.request.identifier })
    }
}

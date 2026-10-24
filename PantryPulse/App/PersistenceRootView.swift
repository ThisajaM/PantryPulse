import CoreData
import SwiftUI

/// Keeps the existing launch flow intact once the local store is ready.
struct PersistenceRootView: View {
    private let preferences: UserDefaults
    @State private var persistence: PersistenceController

    init(inMemory: Bool = false, storeURL: URL? = nil, preferences: UserDefaults = .standard) {
        self.preferences = preferences
        _persistence = State(initialValue: PersistenceController(inMemory: inMemory, storeURL: storeURL))
    }

    var body: some View {
        Group {
            if let container = persistence.container {
                StoredPantryLaunchView(container: container, preferences: preferences)
                    .environment(\.managedObjectContext, container.viewContext)
            } else if let error = persistence.loadError {
                ContentUnavailableView {
                    Label("Storage unavailable", systemImage: "externaldrive.badge.exclamationmark")
                } description: {
                    Text(error.localizedDescription)
                } actions: {
                    Button("Retry") { Task { await persistence.load() } }
                }
            } else {
                LoadingStateView(title: "Opening your pantry")
            }
        }
        .task { await persistence.load() }
    }
}

#Preview { PersistenceRootView(inMemory: true) }


private struct StoredPantryLaunchView: View {
    @State private var pantry: PantryViewModel

    @State private var reminders: NotificationService

    init(container: NSPersistentContainer, preferences: UserDefaults) {
        let repository = PantryRepository(container: container)
        _pantry = State(initialValue: PantryViewModel(repository: repository, riskService: WasteRiskService()))
        _reminders = State(initialValue: NotificationService(repository: repository, defaults: preferences))
    }

    var body: some View { AppRootView(pantry: pantry, reminders: reminders) }
}

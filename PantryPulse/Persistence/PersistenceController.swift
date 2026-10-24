//
//  PersistenceController.swift
//  PantryPulse
//
//  Created by Thisaja Mudalige on 2026-10-14.
//

import CoreData
import Observation

@MainActor
@Observable
final class PersistenceController {
    private(set) var container: NSPersistentContainer?
    private(set) var isLoading = false
    private(set) var loadError: Error?
    private let inMemory: Bool
    private let storeURL: URL?

    // Share model metadata, not stores or contexts, across preview/test containers.
    private static let model: Result<NSManagedObjectModel, Error> = Result {
        guard let url = Bundle.main.url(forResource: "PantryPulse", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: url) else {
            throw PersistenceError.modelUnavailable
        }
        return model
    }

    init(inMemory: Bool = false, storeURL: URL? = nil) {
        self.inMemory = inMemory
        self.storeURL = storeURL
    }

    /// Loads once; a failed attempt can be retried without replacing or deleting the store.
    func load() async {
        guard container == nil, !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            let model = try Self.model.get()
            let candidate = NSPersistentContainer(name: "PantryPulse", managedObjectModel: model)
            let description = NSPersistentStoreDescription()
            description.type = inMemory ? NSInMemoryStoreType : NSSQLiteStoreType
            if !inMemory {
                description.url = storeURL ?? NSPersistentContainer.defaultDirectoryURL()
                    .appendingPathComponent("PantryPulse.sqlite")
            }
            if let url = description.url, !inMemory {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            description.shouldAddStoreAsynchronously = true
            candidate.persistentStoreDescriptions = [description]
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                candidate.loadPersistentStores { _, error in
                    if let error { continuation.resume(throwing: error) }
                    else { continuation.resume() }
                }
            }
            candidate.viewContext.automaticallyMergesChangesFromParent = true
            candidate.viewContext.mergePolicy = NSErrorMergePolicy
            container = candidate
        } catch {
            loadError = error
        }
    }

    func close() throws {
        guard let container else { return }
        container.viewContext.reset()
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
        self.container = nil
    }

    /// Callers handle save failures; pending edits are retained for correction or explicit rollback.
    func save() throws {
        guard let context = container?.viewContext else { throw PersistenceError.storeUnavailable }
        if context.hasChanges { try context.save() }
    }
}

enum PersistenceError: LocalizedError {
    case modelUnavailable, storeUnavailable

    var errorDescription: String? {
        switch self {
        case .modelUnavailable: "The pantry data model could not be loaded."
        case .storeUnavailable: "Local storage is not available."
        }
    }
}

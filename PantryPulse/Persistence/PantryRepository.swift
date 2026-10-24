import Combine
import CoreData
import OSLog

/// Synchronous main-actor operations serialize fetch/check/save, including repeated submissions.
/// Owns a context so rolling back a failed save cannot discard another feature's pending edits.
@MainActor
final class PantryRepository: PantryRepositoryProtocol {
    private var valid = true
    func invalidate() {
        valid = false
        context.reset()
        context.persistentStoreCoordinator = nil
    }
    private func requireActive() throws {
        guard valid else { throw PersistenceError.storeUnavailable }
    }
    private let context: NSManagedObjectContext
    private let now: () -> Date
    private let photos: FoodPhotoStorage
    private var pendingPhotoCleanup = Set<String>()
    private let didChange = PassthroughSubject<Void, Never>()
    var changes: AnyPublisher<Void, Never> { didChange.eraseToAnyPublisher() }

    init(container: NSPersistentContainer, photos: FoodPhotoStorage = FoodPhotoStorage(), now: @escaping () -> Date = Date.init) {
        context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = container.persistentStoreCoordinator
        context.mergePolicy = NSErrorMergePolicy
        context.undoManager = nil
        self.now = now
        self.photos = photos
        cleanupPhotos()
    }

    func create(_ input: FoodDraft) throws -> PantryItem {
        try requireActive()
        let draft = try input.validated()
        if let existing = try record(id: draft.id) {
            guard try readDraft(existing) == draft else { throw PantryRepositoryError.conflictingCreate(draft.id) }
            return try value(existing)
        }
        let item = PantryItemRecord(context: context)
        item.id = draft.id
        item.createdAt = now()
        item.updatedAt = item.createdAt
        apply(draft, to: item)
        return try commit(item)
    }

    func update(_ input: FoodDraft) throws -> PantryItem {
        let draft = try input.validated()
        guard let item = try record(id: draft.id) else { throw PantryRepositoryError.itemNotFound(draft.id) }
        _ = try value(item)
        guard item.quantity > 0 else { throw UsageError.inactiveItem }
        let oldPhoto = item.imagePath
        if let oldPhoto, oldPhoto != draft.imagePath { try photos.markForCleanup(oldPhoto) }
        apply(draft, to: item)
        item.updatedAt = max(now(), (item.updatedAt ?? .distantPast).addingTimeInterval(0.000001))
        let result = try commit(item)
        if let oldPhoto, oldPhoto != draft.imagePath { pendingPhotoCleanup.insert(oldPhoto) }
        cleanupPhotos()
        return result
    }

    func delete(id: UUID) throws {
        guard let item = try record(id: id) else { throw PantryRepositoryError.itemNotFound(id) }
        let oldPhoto = item.imagePath
        if let oldPhoto { try photos.markForCleanup(oldPhoto) }
        context.delete(item)
        do { try context.save() } catch { context.rollback(); throw error }
        if let oldPhoto { pendingPhotoCleanup.insert(oldPhoto) }
        cleanupPhotos()
        didChange.send()
    }

    /// Full-item usage and its immutable snapshot commit together in this repository's context.
    func recordUsage(itemID: UUID, type: UsageEventType, eventID: UUID, expectedUpdatedAt: Date?) throws -> UsageEvent {
        try requireActive()
        let request = UsageEventRecord.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", eventID as NSUUID)
        let previous = try context.fetch(request)
        guard previous.count <= 1 else { throw UsageError.invalidHistory }
        if let record = previous.first {
            let event = try usageValue(record)
            guard event.itemID == itemID, event.type == type else { throw UsageError.conflictingRequest }
            return event
        }
        guard let item = try record(id: itemID) else { throw PantryRepositoryError.itemNotFound(itemID) }
        let snapshot = try value(item)
        guard snapshot.status == .active else { throw UsageError.inactiveItem }
        guard snapshot.updatedAt == expectedUpdatedAt else { throw UsageError.staleItem }
        guard let quantity = snapshot.quantity, quantity.isFinite, quantity > 0,
              let unit = snapshot.quantityUnit else { throw PantryRepositoryError.invalidRecord }
        let timestamp = now()
        let event = UsageEventRecord(context: context)
        event.id = eventID
        event.itemID = itemID
        event.itemNameSnapshot = snapshot.name
        event.categorySnapshot = snapshot.category.rawValue
        event.eventType = type.rawValue
        event.quantity = quantity
        event.quantityUnit = unit.rawValue
        event.eventDate = timestamp
        item.quantity = 0
        item.status = type == .consumed ? PantryItemStatus.consumed.rawValue : PantryItemStatus.wasted.rawValue
        item.updatedAt = max(timestamp, (item.updatedAt ?? .distantPast).addingTimeInterval(0.000001))
        let result: UsageEvent
        do {
            result = try usageValue(event)
            _ = try value(item)
            try context.save()
        } catch { context.rollback(); throw error }
        didChange.send()
        return result
    }

    func fetchUsageEvents() throws -> [UsageEvent] {
        try requireActive()
        return try context.fetch(UsageEventRecord.fetchRequest()).map(usageValue).sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date > $1.date
        }
    }

    private func usageValue(_ record: UsageEventRecord) throws -> UsageEvent {
        guard let id = record.id, let itemID = record.itemID, let name = record.itemNameSnapshot,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let category = record.categorySnapshot.flatMap(FoodCategory.init(rawValue:)),
              let type = record.eventType.flatMap(UsageEventType.init(rawValue:)),
              let unit = record.quantityUnit.flatMap(QuantityUnit.init(rawValue:)), let date = record.eventDate,
              record.quantity.isFinite, record.quantity > 0 else { throw UsageError.invalidHistory }
        return UsageEvent(id: id, itemID: itemID, itemName: name, category: category, type: type,
                          quantity: record.quantity, unit: unit, date: date)
    }

    func fetch(id: UUID) throws -> PantryItem? { try record(id: id).map(value) }
    func fetchAll(sort: PantryFetchSort = .createdNewest) throws -> [PantryItem] {
        try search(name: "", category: nil, activeOnly: false, sort: sort)
    }
    func fetchActive(sort: PantryFetchSort = .createdNewest) throws -> [PantryItem] {
        try search(name: "", category: nil, activeOnly: true, sort: sort)
    }
    func filter(category: FoodCategory, sort: PantryFetchSort = .expirySoonest) throws -> [PantryItem] {
        try search(name: "", category: category, activeOnly: false, sort: sort)
    }
    func search(name: String, category: FoodCategory? = nil, activeOnly: Bool = false,
                sort: PantryFetchSort = .expirySoonest) throws -> [PantryItem] {
        let request = PantryItemRecord.fetchRequest()
        var predicates: [NSPredicate] = []
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty { predicates.append(NSPredicate(format: "name CONTAINS[cd] %@", query)) }
        if let category { predicates.append(NSPredicate(format: "category == %@", category.rawValue)) }
        if activeOnly { predicates.append(NSPredicate(format: "status == %@", PantryItemStatus.active.rawValue)) }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        try requireActive()
        return try context.fetch(request).map(value).sorted { lhs, rhs in
            switch sort {
            case .expirySoonest:
                let a = lhs.expiryDate ?? .distantFuture, b = rhs.expiryDate ?? .distantFuture
                if a != b { return a < b }
            case .createdNewest:
                if lhs.createdAt != rhs.createdAt { return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast) }
            case .createdOldest:
                if lhs.createdAt != rhs.createdAt { return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast) }
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    private func cleanupPhotos() {
        do {
            pendingPhotoCleanup.formUnion(try photos.pendingPaths())
            let records = try context.fetch(PantryItemRecord.fetchRequest())
            let referenced = Set(records.compactMap(\.imagePath))
            for path in pendingPhotoCleanup {
                if referenced.contains(path) {
                    try photos.finishCleanup(path)
                } else {
                    try photos.markForCleanup(path)
                    try photos.remove(path)
                }
                pendingPhotoCleanup.remove(path)
            }
        } catch {
            // The database transaction already succeeded; retry cleanup on the next write or launch.
            Logger(subsystem: "PantryPulse", category: "PhotoStorage").error("Photo cleanup will be retried: \(error.localizedDescription, privacy: .private)")
        }
    }

    private func record(id: UUID) throws -> PantryItemRecord? {
        try requireActive()
        let request = PantryItemRecord.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        request.fetchLimit = 2
        let matches = try context.fetch(request)
        guard matches.count < 2 else { throw PantryRepositoryError.duplicateIdentity(id) }
        return matches.first
    }

    private func apply(_ draft: FoodDraft, to item: PantryItemRecord) {
        item.name = draft.name; item.category = draft.category.rawValue
        item.quantity = draft.quantity; item.quantityUnit = draft.quantityUnit.rawValue
        item.purchaseDate = draft.purchaseDate; item.expiryDate = draft.expiryDate
        item.storageLocation = draft.storageLocation; item.imagePath = draft.imagePath
        item.notes = draft.notes; item.barcode = draft.barcode; item.status = draft.status.rawValue
    }

    private func readDraft(_ item: PantryItemRecord) throws -> FoodDraft {
        guard let id = item.id, let name = item.name,
              let category = item.category.flatMap(FoodCategory.init(rawValue:)),
              let unit = item.quantityUnit.flatMap(QuantityUnit.init(rawValue:)),
              let purchased = item.purchaseDate, let storage = item.storageLocation,
              let status = item.status.flatMap(PantryItemStatus.init(rawValue:)) else {
            throw PantryRepositoryError.invalidRecord
        }
        var draft = FoodDraft(id: id, name: name)
        draft.category = category; draft.quantity = item.quantity; draft.quantityUnit = unit
        draft.purchaseDate = purchased; draft.expiryDate = item.expiryDate
        draft.storageLocation = storage; draft.imagePath = item.imagePath
        draft.notes = item.notes; draft.barcode = item.barcode; draft.status = status
        return try draft.validated()
    }

    private func value(_ item: PantryItemRecord) throws -> PantryItem {
        let draft = try readDraft(item)
        guard let created = item.createdAt, let updated = item.updatedAt else { throw PantryRepositoryError.invalidRecord }
        return PantryItem(id: draft.id, name: draft.name, category: draft.category,
                          quantityDescription: "\(draft.quantity.formatted()) \(draft.quantityUnit.rawValue)",
                          storageLocation: draft.storageLocation, expiryDate: draft.expiryDate, addedAt: created,
                          quantity: draft.quantity, quantityUnit: draft.quantityUnit, purchaseDate: draft.purchaseDate,
                          imagePath: draft.imagePath, notes: draft.notes, barcode: draft.barcode,
                          updatedAt: updated, status: draft.status)
    }

    private func commit(_ item: PantryItemRecord) throws -> PantryItem {
        let result: PantryItem
        do { result = try value(item); try context.save() }
        catch { context.rollback(); throw error }
        cleanupPhotos()
        didChange.send()
        return result
    }
}

import Foundation
import Combine
import Observation

@MainActor
@Observable
final class FoodDetailsViewModel {
    private(set) var wasteRisk: WasteRiskAssessment?
    private let riskService: any WasteRiskPredicting
    private var riskTask: Task<Void, Never>?
    private var riskRevision = UUID()
    let id: UUID
    private(set) var item: PantryItem?
    private(set) var errorMessage: String?
    private let repository: (any PantryRepositoryProtocol)?
    private var referenceDate = Date()
    private var subscription: AnyCancellable?

    init(id: UUID, repository: (any PantryRepositoryProtocol)?, riskService: any WasteRiskPredicting = WasteRiskService()) {
        self.riskService = riskService
        self.id = id
        self.repository = repository
        subscription = repository?.changes.sink { [weak self] in self?.reload() }
        reload()
    }

    var expiryDescription: String? {
        item.map { PantryFoodDisplay(item: $0, referenceDate: referenceDate, calendar: .autoupdatingCurrent).expiryText }
    }

    func reload() {
        referenceDate = Date()
        riskTask?.cancel()
        let revision = UUID()
        riskRevision = revision
        wasteRisk = nil
        do {
            guard let repository else { throw PersistenceError.storeUnavailable }
            item = try repository.fetch(id: id)
            errorMessage = nil
            if let item {
                let history = try repository.fetchUsageEvents()
                let date = referenceDate
                let service = riskService
                riskTask = Task { [weak self] in
                    let result = await WasteRiskAssessment.evaluate(item: item, history: history,
                        on: date, calendar: .autoupdatingCurrent, service: service)
                    guard !Task.isCancelled, self?.riskRevision == revision else { return }
                    self?.wasteRisk = result
                }
            }
        } catch {
            wasteRisk = WasteRiskAssessment(level: nil, explanation: [],
                unavailableReason: "Inventory or history could not be loaded. Try again.")
            errorMessage = error.localizedDescription
        }
    }

    func recordUsage(type: UsageEventType, eventID: UUID, expectedUpdatedAt: Date?) -> Bool {
        do {
            guard let repository else { throw PersistenceError.storeUnavailable }
            _ = try repository.recordUsage(itemID: id, type: type, eventID: eventID, expectedUpdatedAt: expectedUpdatedAt)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func delete() -> Bool {
        do {
            guard let repository else { throw PersistenceError.storeUnavailable }
            try repository.delete(id: id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func dismissError() { errorMessage = nil }
}

import Foundation
import Observation
import Combine

/// Shared presentation state; repository snapshots contain only saved active inventory.
@MainActor
@Observable
final class PantryViewModel {
    private(set) var wasteRisk: [UUID: WasteRiskAssessment] = [:]
    private let riskService: any WasteRiskPredicting
    private var riskTask: Task<Void, Never>?
    private var riskRevision = UUID()
    private(set) var usageEvents: [UsageEvent] = []
    private(set) var items: [PantryItem]
    var searchText = ""
    var selectedCategory: FoodCategory?
    var sortOrder: PantrySortOrder = .expirySoonest
    private let now: () -> Date
    private let calendar: Calendar
    private var referenceDate: Date
    private let repository: (any PantryRepositoryProtocol)?
    private var subscription: AnyCancellable?
    private(set) var loadError: String?

    private var active = true
    func deactivate() {
        active = false
        subscription?.cancel()
        riskTask?.cancel()
        riskRevision = UUID()
        items = []; usageEvents = []; wasteRisk = [:]
    }
    func reload() {
        guard active else { return }
        referenceDate = now()
        guard let repository else { refreshWasteRisk(); return }
        do {
            let inventory = try repository.fetchActive(sort: .createdNewest)
            let history = try repository.fetchUsageEvents()
            items = inventory
            usageEvents = history
            loadError = nil
            refreshWasteRisk()
        } catch {
            loadError = error.localizedDescription
            riskTask?.cancel()
            riskRevision = UUID()
            wasteRisk = [:]
        }
    }

    func insights(period: InsightsPeriod) -> UsageInsights {
        UsageInsights(events: usageEvents, period: period, now: referenceDate, calendar: calendar)
    }

    func dismissError() { loadError = nil }

    func createFood(_ draft: FoodDraft) throws -> PantryItem {
        guard let repository else { throw PersistenceError.storeUnavailable }
        return try repository.create(draft)
    }

    func detailsModel(id: UUID) -> FoodDetailsViewModel {
        FoodDetailsViewModel(id: id, repository: repository, riskService: riskService)
    }

    func foodDraft(id: UUID) throws -> FoodDraft? {
        guard let repository else { throw PersistenceError.storeUnavailable }
        return try repository.fetch(id: id).map { try FoodDraft(item: $0) }
    }

    func updateFood(_ draft: FoodDraft) throws -> PantryItem {
        guard let repository else { throw PersistenceError.storeUnavailable }
        return try repository.update(draft)
    }

    init(items: [PantryItem] = [], repository: (any PantryRepositoryProtocol)? = nil, now: @escaping () -> Date = Date.init, calendar: Calendar = .autoupdatingCurrent, riskService: any WasteRiskPredicting = WasteRiskService()) {
        self.riskService = riskService
        self.items = items.filter { $0.status == .active }
        self.now = now
        self.referenceDate = now()
        self.calendar = calendar
        self.repository = repository
        subscription = repository?.changes.sink { [weak self] in self?.reload() }
        reload()
    }

    private func refreshWasteRisk() {
        riskTask?.cancel()
        let revision = UUID()
        riskRevision = revision
        wasteRisk = [:]
        let snapshot = items
        let history = usageEvents
        let date = referenceDate
        let calendar = calendar
        let service = riskService
        riskTask = Task { [weak self] in
            var results: [UUID: WasteRiskAssessment] = [:]
            for item in snapshot {
                guard !Task.isCancelled else { return }
                results[item.id] = await WasteRiskAssessment.evaluate(item: item, history: history,
                    on: date, calendar: calendar, service: service)
            }
            guard !Task.isCancelled, self?.riskRevision == revision else { return }
            self?.wasteRisk = results
        }
    }

    var itemCount: Int { items.count }
    var isEmpty: Bool { items.isEmpty }

    var food: [PantryFoodDisplay] {
        let reference = referenceDate
        return items.map { PantryFoodDisplay(item: $0, referenceDate: reference, calendar: calendar) }
    }

    var freshCount: Int { food.filter { $0.freshness == .fresh }.count }
    var expiringSoonCount: Int { food.filter { $0.freshness == .expiringSoon }.count }
    var expiredCount: Int { food.filter { $0.freshness == .expired }.count }
    var urgentCount: Int { food.filter { $0.freshness == .urgent }.count }
    var unknownExpiryCount: Int { food.filter { $0.freshness == .unknown }.count }

    private var priorityGroups: ExpiryPriorityGroups {
        ExpiryPrioritizer.group(items, on: referenceDate, calendar: calendar, risk: wasteRisk.compactMapValues(\.level))
    }
    private func displays(_ items: [PantryItem]) -> [PantryFoodDisplay] {
        items.map { PantryFoodDisplay(item: $0, referenceDate: referenceDate, calendar: calendar) }
    }
    var useFirst: [PantryFoodDisplay] { displays(priorityGroups.upcoming) }
    var unknownExpiry: [PantryFoodDisplay] { displays(priorityGroups.unknown) }
    var expiredFood: [PantryFoodDisplay] { displays(priorityGroups.expired) }

    var recentlyAdded: [PantryFoodDisplay] {
        food.filter { $0.item.addedAt != nil }.sorted { ($0.item.addedAt ?? .distantPast) > ($1.item.addedAt ?? .distantPast) }
    }

    func count(in category: FoodCategory?) -> Int {
        items.filter { category == nil || $0.category == category }.count
    }

    var visibleFood: [PantryFoodDisplay] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return food.filter {
            (selectedCategory == nil || $0.item.category == selectedCategory)
                && (query.isEmpty || $0.item.name.localizedStandardContains(query))
        }.sorted {
            switch sortOrder {
            case .expirySoonest:
                let lhs = $0.item.expiryDate ?? .distantFuture
                let rhs = $1.item.expiryDate ?? .distantFuture
                if lhs != rhs { return lhs < rhs }
            case .recentlyAdded:
                let lhs = $0.item.addedAt ?? .distantPast
                let rhs = $1.item.addedAt ?? .distantPast
                if lhs != rhs { return lhs > rhs }
            case .name, .nameDescending: break
            }
            let comparison = $0.item.name.localizedStandardCompare($1.item.name)
            if comparison != .orderedSame {
                return comparison == (sortOrder == .nameDescending ? .orderedDescending : .orderedAscending)
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func clearFilters() {
        searchText = ""
        selectedCategory = nil
    }
}

enum PantrySortOrder: String, CaseIterable, Identifiable {
    case expirySoonest = "Expiry (soonest)", recentlyAdded = "Recently added", name = "Name (A–Z)", nameDescending = "Name (Z–A)"
    var id: Self { self }
}

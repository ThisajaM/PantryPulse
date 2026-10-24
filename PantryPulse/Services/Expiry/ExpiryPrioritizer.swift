import Foundation

struct ExpiryPriorityGroups {
    let upcoming: [PantryItem]
    let unknown: [PantryItem]
    let expired: [PantryItem]
}

/// Calendar-day expiry remains primary. Model risk breaks same-day ties only.
enum ExpiryPrioritizer {
    static func group(_ items: [PantryItem], on date: Date, calendar: Calendar = .autoupdatingCurrent, risk: [UUID: WasteRiskLevel] = [:]) -> ExpiryPriorityGroups {
        let active = items.filter { $0.status == .active }
        let ordered = active.sorted {
            let left = $0.expiryDate.map { calendar.startOfDay(for: $0) } ?? .distantFuture
            let right = $1.expiryDate.map { calendar.startOfDay(for: $0) } ?? .distantFuture
            if left != right { return left < right }
            // Do not equate an unavailable prediction with Low risk.
            // A neutral middle ranking retains a total, transitive ordering.
            let leftRisk = risk[$0.id]?.priority ?? 1
            let rightRisk = risk[$1.id]?.priority ?? 1
            if leftRisk != rightRisk { return leftRisk > rightRisk }
            let names = $0.name.localizedStandardCompare($1.name)
            return names == .orderedSame ? $0.id.uuidString < $1.id.uuidString : names == .orderedAscending
        }
        func status(_ item: PantryItem) -> PantryFreshness {
            ExpiryService.assess(item.expiryDate, on: date, calendar: calendar).freshness
        }
        return ExpiryPriorityGroups(
            upcoming: ordered.filter { status($0) != .expired && status($0) != .unknown },
            unknown: ordered.filter { status($0) == .unknown },
            expired: ordered.filter { status($0) == .expired }
        )
    }
}

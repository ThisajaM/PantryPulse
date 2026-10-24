import Foundation

/// Calendar-day assessment only; this is not a food-safety or ML prediction.
enum ExpiryService {
    static func assess(_ expiry: Date?, on reference: Date, calendar: Calendar = .autoupdatingCurrent) -> ExpiryAssessment {
        ExpiryAssessment(daysRemaining: expiry.flatMap {
            calendar.dateComponents([.day], from: calendar.startOfDay(for: reference),
                                    to: calendar.startOfDay(for: $0)).day
        })
    }
}

struct ExpiryAssessment {
    let daysRemaining: Int?
    var freshness: PantryFreshness {
        guard let daysRemaining else { return .unknown }
        switch daysRemaining {
        case ..<0: return .expired
        case 0...1: return .urgent
        case 2...3: return .expiringSoon
        default: return .fresh
        }
    }
    var description: String {
        guard let daysRemaining else { return "No expiry date" }
        switch daysRemaining {
        case ..<0: return "Past expiry date"
        case 0: return "Expires today"
        case 1: return "1 day left"
        default: return "\(daysRemaining) days left"
        }
    }
}

enum PantryFreshness {
    case unknown, fresh, expiringSoon, urgent, expired
    var title: String {
        switch self {
        case .unknown: "Not assessed"
        case .fresh: "Fresh"
        case .expiringSoon: "Expiring soon"
        case .urgent: "Needs attention"
        case .expired: "Expired"
        }
    }
}

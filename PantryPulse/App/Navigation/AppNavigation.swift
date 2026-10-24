import Foundation
import Observation

enum AppTab: String, CaseIterable, Identifiable {
    case home, pantry, scan, insights, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .pantry: "Pantry"
        case .scan: "Scan"
        case .insights: "Insights"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .pantry: "cabinet"
        case .scan: "camera.circle.fill"
        case .insights: "chart.bar"
        case .settings: "person.crop.circle"
        }
    }
}

/// Value routes retain identity across view updates without retaining whole models.
enum AppRoute: Hashable {
    case addFood, notifications
    case useFirst, expiredItems
    case foodDetails(itemID: UUID)
    case editFood(itemID: UUID)
    case recognition, barcode, storagePreferences, about
}

@MainActor
@Observable
final class AppNavigation {
    var selectedTab: AppTab = .home
    // One independently owned path per tab. Switching tabs does not clear a path.
    var paths: [AppTab: [AppRoute]] = [:]

    init(selectedTab: AppTab = .home) {
        self.selectedTab = selectedTab
    }

    func show(_ route: AppRoute, in tab: AppTab) {
        paths[tab, default: []].append(route)
    }
}

import SwiftUI

/// Owns shared inventory and navigation for the lifetime of this app window.
/// Production injects a repository-backed view model; preview data is never a default.
struct AppRootView: View {
    @Environment(\.accountResources) private var resources
    @Environment(\.scenePhase) private var scenePhase
    @State private var navigation: AppNavigation
    private let reminders: NotificationService?
    @State private var pantry: PantryViewModel

    init(pantry: PantryViewModel? = nil, initialTab: AppTab = .home, reminders: NotificationService? = nil) {
        self.reminders = reminders
        _pantry = State(initialValue: pantry ?? PantryViewModel())
        _navigation = State(initialValue: AppNavigation(selectedTab: initialTab))
    }

    var body: some View {
        @Bindable var navigation = navigation

        TabView(selection: $navigation.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: Binding(
                    get: { navigation.paths[tab] ?? [] },
                    set: { navigation.paths[tab] = $0 }
                )) {
                    rootScreen(for: tab)
                        .navigationDestination(for: AppRoute.self) { route in
                            destination(for: route, in: tab)
                        }
                }
                .modifier(PPTabBarStyle())
                .tabItem { Label(tab.title, systemImage: tab.symbol) }
                .tag(tab)
            }
        }
        .tint(PPTabBarStyle.selectionTint)
        .task { reminders?.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in refresh() }
        .alert("Unable to load pantry", isPresented: Binding(
            get: { pantry.loadError != nil },
            set: { if !$0 { pantry.dismissError() } }
        )) {
            Button("Retry") { pantry.reload() }
            Button("Dismiss", role: .cancel) { pantry.dismissError() }
        } message: {
            Text(pantry.loadError ?? "Please try again.")
        }
    }

    private func refresh() {
        pantry.reload()
        reminders?.refresh()
    }

    @ViewBuilder
    private func rootScreen(for tab: AppTab) -> some View {
        switch tab {
        case .home:
            HomeView(
                pantry: pantry,
                onUseFirst: { navigation.show(.useFirst, in: .home) },
                onFoodSelection: { navigation.show(.foodDetails(itemID: $0), in: .home) },
                onAddFood: { navigation.show(.addFood, in: .home) },
                onPantry: { navigation.selectedTab = .pantry },
                onNotifications: { navigation.show(.notifications, in: .home) },
                onProfile: { navigation.selectedTab = .settings }
            )
        case .pantry:
            PantryView(
                viewModel: pantry,
                onFoodSelection: { navigation.show(.foodDetails(itemID: $0), in: .pantry) },
                onAddFood: { navigation.show(.addFood, in: .pantry) },
                onScan: { navigation.selectedTab = .scan },
                onSettings: { navigation.selectedTab = .settings }
            )
        case .scan:
            ScanView(onRecognition: { navigation.show(.recognition, in: .scan) },
                     onBarcode: { navigation.show(.barcode, in: .scan) },
                     onManualEntry: { navigation.show(.addFood, in: .scan) })
        case .insights:
            InsightsView(pantry: pantry, onPantry: { navigation.selectedTab = .pantry })
        case .settings:
            SettingsView(onStorage: { navigation.show(.storagePreferences, in: .settings) },
                         onNotifications: { navigation.show(.notifications, in: .settings) },
                         onRecognition: { navigation.show(.recognition, in: .settings) },
                         onAbout: { navigation.show(.about, in: .settings) })
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute, in tab: AppTab) -> some View {
        switch route {
        case .recognition:
            FoodRecognitionView(isSelected: navigation.selectedTab == tab,
                                service: recognitionService,
                                save: pantry.createFood) {
                navigation.paths[tab] = []
                navigation.selectedTab = .pantry
            }
        case .barcode:
            BarcodeFlowView(isSelected: navigation.selectedTab == .scan, service: ProductIdentificationService(catalogue: resources.catalogue), save: pantry.createFood) {
                navigation.paths[.scan] = []
                navigation.selectedTab = .pantry
            }
        case .storagePreferences:
            LaterPhaseView(title: "Default Storage", systemImage: "refrigerator",
                           message: "Storage preferences are coming in a later phase. No storage preference has been saved.")
                .navigationBarTitleDisplayMode(.inline)
        case .about:
            AboutView()
        case .useFirst:
            UseFirstView(pantry: pantry, onSelect: {
                navigation.show(.foodDetails(itemID: $0), in: navigation.selectedTab)
            }, onExpired: { navigation.show(.expiredItems, in: navigation.selectedTab) })
        case .expiredItems:
            ExpiredItemsView(pantry: pantry) {
                navigation.show(.foodDetails(itemID: $0), in: navigation.selectedTab)
            }
        case .foodDetails(let itemID):
            FoodDetailsView(model: pantry.detailsModel(id: itemID)) {
                navigation.show(.editFood(itemID: itemID), in: navigation.selectedTab)
            }
        case .editFood(let itemID):
            EditFoodView(itemID: itemID, pantry: pantry)
        case .addFood:
            AddFoodView(resources: resources, save: pantry.createFood)
        case .notifications:
            if let reminders {
                ReminderSettingsView(service: reminders)
            } else {
                ContentUnavailableView("Reminders unavailable", systemImage: "bell.slash",
                                       description: Text("Open the app with its saved pantry to configure reminders."))
            }
        }
    }

    private var recognitionService: any FoodRecognizing {
        #if DEBUG
        if let mock = RecognitionUITestSupport.configuredService { return mock }
        #endif
        return FoodRecognitionService()
    }
}

#Preview {
    AppRootView()
}

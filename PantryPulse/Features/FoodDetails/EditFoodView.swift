import SwiftUI

struct EditFoodView: View {
    @Environment(\.accountResources) private var resources
    let itemID: UUID
    let pantry: PantryViewModel
    @State private var draft: FoodDraft?
    @State private var errorMessage: String?
    @State private var loaded = false

    var body: some View {
        Group {
            if let draft {
                AddFoodView(draft: draft, resources: resources, save: pantry.updateFood)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Unable to load food", systemImage: "exclamationmark.triangle")
                } description: { Text(errorMessage) } actions: {
                    Button("Retry", action: load)
                }
            } else if loaded {
                ContentUnavailableView("Food unavailable", systemImage: "questionmark.folder",
                                       description: Text("This item no longer exists. Go back to your pantry."))
            } else {
                LoadingStateView(title: "Loading food")
            }
        }
        .navigationTitle("Edit Food")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !loaded { load() } }
    }

    private func load() {
        do {
            draft = try pantry.foodDraft(id: itemID)
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        loaded = true
    }
}

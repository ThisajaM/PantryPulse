import SwiftUI

struct FoodDetailsView: View {
    @State private var model: FoodDetailsViewModel
    let onEdit: () -> Void
    @State private var usageConfirmation: UsageConfirmation?
    @State private var confirmingDelete = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    init(model: FoodDetailsViewModel, onEdit: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onEdit = onEdit
    }

    var body: some View {
        Group {
            if let item = model.item {
                ScrollView {
                    VStack(alignment: .leading, spacing: PPSpacing.lg) {
                        StoredFoodImageView(path: item.imagePath)
                        StatusBadge(title: item.category.rawValue)
                        Text(item.name).font(PPTypography.screenTitle)
                            .accessibilityIdentifier("foodDetails.name")
                        VStack(alignment: .leading, spacing: PPSpacing.md) {
                            detail("Quantity", value: item.quantityDescription ?? "Not recorded")
                            detail("Storage location", value: item.storageLocation ?? "Not recorded")
                            detail("Purchased", value: date(item.purchaseDate))
                            detail("Expiry", value: item.expiryDate.map { date($0) } ?? "No expiry date")
                            Text(model.expiryDescription ?? "No expiry date")
                                .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                        }.ppCard()
                        WasteRiskCard(assessment: model.wasteRisk)
                        if let notes = item.notes {
                            VStack(alignment: .leading, spacing: PPSpacing.xs) {
                                Text("Notes").font(PPTypography.sectionTitle)
                                Text(notes).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading).ppCard()
                        }
                        VStack(alignment: .leading, spacing: PPSpacing.md) {
                            detail("Status", value: item.status.rawValue.capitalized)
                            if let barcode = item.barcode { detail("Barcode", value: barcode) }
                            detail("Added", value: timestamp(item.createdAt))
                            detail("Last updated", value: timestamp(item.updatedAt))
                            detail("Item ID", value: item.id.uuidString)
                        }.ppCard()
                        if item.status == .active {
                            SecondaryButton(title: "Edit Food", systemImage: "square.and.pencil", action: onEdit)
                            PrimaryButton(title: "Mark as Consumed", systemImage: "checkmark.circle") {
                                usageConfirmation = UsageConfirmation(type: .consumed, item: item)
                            }
                            .accessibilityIdentifier("foodDetails.consume")
                            SecondaryButton(title: "Mark as Wasted", systemImage: "trash") {
                                usageConfirmation = UsageConfirmation(type: .wasted, item: item)
                            }
                            .accessibilityIdentifier("foodDetails.waste")
                        } else {
                            Text("This item is no longer active. Recorded history remains available in Insights.")
                                .font(PPTypography.caption)
                        }
                        Button("Delete Food", role: .destructive) { confirmingDelete = true }
                            .frame(maxWidth: .infinity, minHeight: PPMetrics.minimumTapTarget)
                            .accessibilityIdentifier("foodDetails.delete")
                    }
                    .font(PPTypography.body)
                    .foregroundStyle(PPColors.text)
                    .padding(PPSpacing.lg)
                    .frame(maxWidth: PPMetrics.screenContentWidth)
                    .frame(maxWidth: .infinity)
                }
            } else {
                ContentUnavailableView("Food unavailable", systemImage: "questionmark.folder",
                                       description: Text("This food is no longer in your pantry. Go back to choose another item."))
            }
        }
        .background(PPColors.background)
        .navigationTitle("Food Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { model.reload() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.reload() } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in model.reload() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in model.reload() }
        .alert("Record full item usage?", isPresented: Binding(
            get: { usageConfirmation != nil }, set: { if !$0 { usageConfirmation = nil } }
        ), presenting: usageConfirmation) { confirmation in
            Button("Confirm \(confirmation.type.title)", role: confirmation.type == .wasted ? .destructive : nil) {
                _ = model.recordUsage(type: confirmation.type, eventID: confirmation.id,
                                      expectedUpdatedAt: confirmation.item.updatedAt)
                usageConfirmation = nil
            }
            Button("Cancel", role: .cancel) { usageConfirmation = nil }
        } message: { confirmation in
            Text("Record all \(confirmation.item.quantityDescription ?? "remaining food") of \(confirmation.item.name) as \(confirmation.type.rawValue)? Remaining quantity will become zero and future expiry reminders will be cancelled. This records what happened; it is not advice to eat the food.")
        }
        .alert("Delete this food?", isPresented: $confirmingDelete) {
            Button("Delete Food", role: .destructive) { if model.delete() { dismiss() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes \(model.item?.name ?? "this item") from your pantry.")
        }
        .alert("Unable to access food", isPresented: Binding(
            get: { model.errorMessage != nil }, set: { if !$0 { model.dismissError() } }
        )) {
            Button("Retry") { model.reload() }
            Button("OK", role: .cancel) { model.dismissError() }
        } message: { Text(model.errorMessage ?? "Please try again.") }
    }

    private func detail(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: PPSpacing.xxs) {
            Text(label).font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
            Text(value).textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func date(_ value: Date?) -> String {
        value?.formatted(date: .abbreviated, time: .omitted) ?? "Not recorded"
    }

    private func timestamp(_ value: Date?) -> String {
        value?.formatted(date: .abbreviated, time: .shortened) ?? "Not recorded"
    }
}

private struct UsageConfirmation: Identifiable {
    let id = UUID()
    let type: UsageEventType
    let item: PantryItem
}

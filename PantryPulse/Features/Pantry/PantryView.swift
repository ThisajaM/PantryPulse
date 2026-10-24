import SwiftUI

struct PantryView: View {
    @Bindable var viewModel: PantryViewModel
    let onFoodSelection: (UUID) -> Void
    let onAddFood: () -> Void
    let onScan: () -> Void
    let onSettings: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.md) {
                ScreenHeader(title: "My Pantry", badge: StatusBadge(title: "\(viewModel.itemCount) items"),
                              action: PPAction(title: "Settings", systemImage: "slider.horizontal.3", action: onSettings))
                searchField
                categoryFilters
                sortControls
                if viewModel.isEmpty {
                    EmptyPantryView(onAddFood: onAddFood, onScan: onScan)
                } else if viewModel.visibleFood.isEmpty {
                    EmptyStateView(title: "No matching food", message: "Try a different name or category.", systemImage: "magnifyingglass",
                                   primaryAction: PPAction(title: "Clear filters", action: viewModel.clearFilters))
                } else {
                    PantryFoodGrid(food: viewModel.visibleFood, onSelect: onFoodSelection,
                                   imageAspectRatio: PPMetrics.pantryFoodImageAspectRatio)
                }
                if !viewModel.isEmpty {
                    PrimaryButton(title: "Add Food", systemImage: "plus", action: onAddFood)
                    Text("Add food manually and save it on this device.")
                        .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                }
            }
            .padding(PPSpacing.lg)
            .frame(maxWidth: PPMetrics.screenContentWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(PPColors.background)
        .navigationTitle("My Pantry")
        .navigationBarTitleDisplayMode(.inline)
        .tint(PPColors.actionText)
    }

    private var searchField: some View {
        HStack(spacing: PPSpacing.xs) {
            Image(systemName: "magnifyingglass").foregroundStyle(PPColors.secondaryText).accessibilityHidden(true)
            TextField("Search fresh ingredients…", text: $viewModel.searchText)
                .font(PPTypography.body)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .accessibilityLabel("Search pantry")
                .accessibilityIdentifier("pantry.search")
            if !viewModel.searchText.isEmpty {
                Button { viewModel.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(minWidth: PPMetrics.minimumTapTarget, minHeight: PPMetrics.minimumTapTarget)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, PPSpacing.md)
        .padding(.vertical, PPSpacing.xxs)
        .frame(minHeight: PPMetrics.secondaryButtonHeight)
        .background(PPColors.surface, in: RoundedRectangle(cornerRadius: PPCornerRadius.card))
    }

    private var categoryFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: PPSpacing.xs) {
                categoryButton(nil)
                ForEach(FoodCategory.allCases) { category in categoryButton(category) }
            }
        }
        .accessibilityIdentifier("pantry.categories")
    }

    private func categoryButton(_ category: FoodCategory?) -> some View {
        let selected = viewModel.selectedCategory == category
        return Button { viewModel.selectedCategory = category } label: {
            HStack(spacing: PPSpacing.xs) {
                Text(category?.rawValue ?? "All Items")
                Text(viewModel.count(in: category).formatted())
                    .padding(.horizontal, PPSpacing.xxs)
                    .background(selected ? PPColors.primary : PPColors.mutedSurface, in: Capsule())
                    .foregroundStyle(selected ? PPColors.onPrimary : PPColors.text)
            }
            .font(PPTypography.caption)
            .padding(.horizontal, PPSpacing.sm)
            .padding(.vertical, PPSpacing.xxs)
            .frame(minHeight: PPMetrics.minimumTapTarget)
            .foregroundStyle(selected ? PPColors.surface : PPColors.secondaryText)
            .background(selected ? PPColors.text : PPColors.surface, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category?.rawValue ?? "All Items"), \(viewModel.count(in: category)) items")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("pantry.category.\(category?.rawValue ?? "All")")
    }

    private var sortControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack { sortMenu; Spacer(); attentionBadge }
            VStack(alignment: .leading, spacing: PPSpacing.xs) { sortMenu; attentionBadge }
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort food", selection: $viewModel.sortOrder) {
                ForEach(PantrySortOrder.allCases) { Text($0.rawValue).tag($0) }
            }
        } label: {
            Label("Sort: \(viewModel.sortOrder.rawValue)", systemImage: "arrow.up.arrow.down")
                .font(PPTypography.caption).frame(minHeight: PPMetrics.minimumTapTarget)
        }
        .accessibilityIdentifier("pantry.sort")
    }

    private var attentionBadge: some View {
        StatusBadge(title: "\(viewModel.urgentCount) urgent", tone: viewModel.urgentCount == 0 ? .neutral : .danger)
    }
}

import SwiftUI
import Charts

struct InsightsView: View {
    let pantry: PantryViewModel
    let onPantry: () -> Void
    @State private var period: InsightsPeriod = .all
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let summary = pantry.insights(period: period)
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.lg) {
                ScreenHeader(title: "Your Insights", subtitle: "Recorded consumption & waste")
                Picker("History period", selection: $period) {
                    ForEach(InsightsPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)
                if summary.events.isEmpty {
                    VStack(spacing: PPSpacing.md) {
                        Text("Your insights begin here").font(PPTypography.sectionTitle)
                            .accessibilityAddTraits(.isHeader)
                        Text("Track the food you use and waste to discover your habits over time.")
                            .font(PPTypography.body)
                        Text("Open a pantry item and record when food is consumed or discarded.")
                            .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                        PrimaryButton(title: "View My Pantry", systemImage: "cabinet", action: onPantry)
                    }
                    .multilineTextAlignment(.center)
                    .padding(.vertical, PPSpacing.lg)
                } else {
                    LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())], spacing: PPSpacing.md) {
                        ForEach(UsageEventType.allCases) { type in
                            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                                StatusBadge(title: type.title, tone: type == .consumed ? .success : .danger)
                                Text("\(summary.count(type)) events").font(PPTypography.sectionTitle)
                                Text("\(summary.itemCount(type)) distinct pantry items").font(PPTypography.caption)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).ppCard()
                            .accessibilityIdentifier("insights.\(type.rawValue)")
                        }
                    }
                    VStack(alignment: .leading, spacing: PPSpacing.md) {
                        SectionHeader(title: "Recorded outcomes")
                        Chart(UsageEventType.allCases) { type in
                            BarMark(x: .value("Outcome", type.title), y: .value("Events", summary.count(type)))
                                .foregroundStyle(type == .consumed ? PPColors.success : PPColors.danger)
                                .accessibilityLabel(type.title)
                                .accessibilityValue("\(summary.count(type)) recorded events")
                        }
                        .frame(height: 200)
                        .chartYScale(domain: 0...max(1, summary.events.count))
                        .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                        Text("Counts of recorded events, not combined weights or volumes.")
                            .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                    }.ppCard()
                    VStack(alignment: .leading, spacing: PPSpacing.md) {
                        SectionHeader(title: "Most wasted categories")
                        if summary.wastedCategories.isEmpty {
                            Text("No waste recorded for this period.")
                        }
                        ForEach(summary.wastedCategories) { category in
                            VStack(alignment: .leading, spacing: PPSpacing.xs) {
                                Text("\(category.category.rawValue): \(category.count) events")
                                ProgressView(value: Double(category.count), total: Double(max(1, summary.count(.wasted))))
                                    .tint(PPColors.danger)
                            }
                        }
                    }.ppCard()
                    SectionHeader(title: "Recent activity")
                    ForEach(summary.events.prefix(30)) { event in
                        VStack(alignment: .leading, spacing: PPSpacing.sm) {
                            StatusBadge(title: event.type.title, tone: event.type == .consumed ? .success : .danger)
                            Text(event.itemName).font(PPTypography.cardTitle)
                            Text("\(event.quantity.formatted()) \(event.unit.rawValue) • \(event.category.rawValue)")
                            Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).ppCard()
                    }
                    Text("Showing the latest \(min(30, summary.events.count)) events in this period. Summaries include every event in the period.")
                        .font(PPTypography.caption)
                }
                Text("Insights describe your recorded history. No savings, environmental impact or ML risk is estimated.")
                    .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
            }
            .padding(PPSpacing.lg)
            .frame(maxWidth: PPMetrics.screenContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(PPColors.background)
        .navigationTitle("Insights")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview { NavigationStack { InsightsView(pantry: PantryViewModel(), onPantry: {}) } }

import SwiftUI

struct PantrySummaryCard: View {
    let total: Int
    let fresh: Int
    let expiringSoon: Int
    let urgent: Int
    let expired: Int
    let unknownExpiry: Int
    let onAddFood: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: PPSpacing.md) {
            ViewThatFits(in: .horizontal) {
                HStack { summaryHeading; Spacer(); summaryBadge }
                VStack(alignment: .leading, spacing: PPSpacing.xs) { summaryHeading; summaryBadge }
            }
            Group {
                if typeSize.isAccessibilitySize {
                    totalLabels
                } else {
                    ZStack(alignment: .bottom) {
                        // Hard colour boundaries preserve exact proportions over the existing dashed path.
                        PantrySummaryArc()
                            .stroke(gaugeGradient, style: StrokeStyle(lineWidth: PPMetrics.summaryArcStroke, lineCap: .round, dash: [PPSpacing.md, PPSpacing.sm]))
                            .accessibilityHidden(true)
                        totalLabels
                    }
                    .frame(maxWidth: PPMetrics.summaryArcWidth)
                    .frame(height: PPMetrics.summaryArcHeight)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.total")

            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: PPSpacing.xs))
                : AnyLayout(HStackLayout(alignment: .top, spacing: PPSpacing.xs))
            layout {
                DashboardStatCard(title: "Fresh", value: fresh.formatted(), tone: .success, compact: true)
                DashboardStatCard(title: "Expiring soon", value: expiringSoon.formatted(), tone: .warning, compact: true)
                DashboardStatCard(title: "Urgent", value: urgent.formatted(), tone: .danger, compact: true)
            }
            if expired > 0 {
                Text("\(expired) items are past their expiry date.")
                    .font(PPTypography.caption).foregroundStyle(PPColors.danger)
            }
            if unknownExpiry > 0 {
                Text("\(unknownExpiry) items have no expiry date and are not assessed.")
                    .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
            }
            SecondaryButton(title: "Add Food", systemImage: "plus", action: onAddFood)
            Text("Add food manually and save it on this device.")
                .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
        }
        .ppCard(padding: PPSpacing.lg)
    }

    private var gaugeGradient: AngularGradient {
        let distribution = FreshnessPulseDistribution(
            fresh: fresh, expiringSoon: expiringSoon, urgent: urgent,
            expired: expired, unknown: unknownExpiry
        )
        let stops = distribution.bands.flatMap { band in
            let color: Color = switch band.category {
            case .fresh: PPColors.success
            case .expiringSoon: PPColors.warning
            case .attention: PPColors.danger
            case .unknown: PPColors.mutedSurface
            }
            return [Gradient.Stop(color: color, location: band.start),
                    Gradient.Stop(color: color, location: band.end)]
        }
        // The arc travels over the top from its left endpoint (180°) to right (360°).
        return AngularGradient(gradient: Gradient(stops: stops), center: .bottom,
                               startAngle: .degrees(180), endAngle: .degrees(360))
    }

    private var summaryHeading: some View {
        Text("Freshness Pulse").font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
            .accessibilityAddTraits(.isHeader)
    }

    private var summaryBadge: some View {
        StatusBadge(title: total == 0 ? "No food yet" : "By expiry date")
    }

    private var totalLabels: some View {
        VStack(spacing: PPSpacing.xxs) {
            Image(systemName: "leaf.fill").foregroundStyle(PPColors.primary).font(.title3).accessibilityHidden(true)
            Text(total.formatted()).font(PPTypography.heroStatistic).foregroundStyle(PPColors.text)
                .contentTransition(.numericText())
            Text("Items in pantry").font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
        }
    }
}

private struct PantrySummaryArc: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.maxY),
                    radius: min(rect.width / 2, rect.height) - PPMetrics.summaryArcStroke,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        return path
    }
}

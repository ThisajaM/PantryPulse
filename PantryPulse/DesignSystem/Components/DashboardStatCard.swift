import SwiftUI

struct DashboardStatCard: View {
    let title: String
    let value: String
    var unit: String? = nil
    var detail: String? = nil
    var systemImage: String? = nil
    var tone: PPStatusTone = .neutral
    var compact = false

    @ViewBuilder
    var body: some View {
        if compact {
            VStack(spacing: PPSpacing.xxs) {
                Text(value).font(PPTypography.cardTitle).foregroundStyle(tone.foreground)
                Text(title).font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(PPSpacing.xs)
            .background(tone.background, in: RoundedRectangle(cornerRadius: PPCornerRadius.small))
            .accessibilityElement(children: .combine)
        } else {
            standardCard
        }
    }

    private var standardCard: some View {
        VStack(alignment: .leading, spacing: PPSpacing.sm) {
            Text(title).font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: PPSpacing.xxs) {
                    valueLabel
                    unitLabel
                }
                VStack(alignment: .leading, spacing: PPSpacing.xxs) {
                    valueLabel
                    unitLabel
                }
            }
            if let detail {
                PPActionLabel(title: detail, systemImage: systemImage)
                    .font(PPTypography.caption)
                    .foregroundStyle(tone.foreground)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppCard()
        .accessibilityElement(children: .combine)
    }

    private var valueLabel: some View {
        Text(value).font(PPTypography.statistic).foregroundStyle(PPColors.text)
    }

    @ViewBuilder private var unitLabel: some View {
        if let unit { Text(unit).font(PPTypography.caption).foregroundStyle(PPColors.secondaryText) }
    }
}

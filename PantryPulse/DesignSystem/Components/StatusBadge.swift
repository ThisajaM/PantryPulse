import SwiftUI

/// Visual emphasis only: the caller determines expiry, risk, and the displayed text.
enum PPStatusTone: CaseIterable {
    case neutral, success, warning, danger

    var foreground: Color {
        switch self {
        case .neutral: PPColors.secondaryText
        case .success: PPColors.successText
        case .warning: PPColors.warningText
        case .danger: PPColors.dangerText
        }
    }

    var background: Color {
        switch self {
        case .neutral: PPColors.mutedSurface
        case .success: PPColors.successSurface
        case .warning: PPColors.warningSurface
        case .danger: PPColors.dangerSurface
        }
    }
}

struct StatusBadge: View {
    let title: String
    var tone: PPStatusTone = .neutral
    var systemImage: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: PPSpacing.xxs) {
            if let systemImage {
                Image(systemName: systemImage).accessibilityHidden(true)
            }
            Text(title).fixedSize(horizontal: false, vertical: true)
        }
        .font(PPTypography.badge)
        .foregroundStyle(tone.foreground)
        .padding(.horizontal, PPSpacing.xs)
        .padding(.vertical, PPSpacing.xxs)
        .background(tone.background, in: RoundedRectangle(cornerRadius: PPCornerRadius.small, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

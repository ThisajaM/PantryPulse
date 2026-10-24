import SwiftUI

struct WasteRiskCard: View {
    let assessment: WasteRiskAssessment?

    var body: some View {
        VStack(alignment: .leading, spacing: PPSpacing.md) {
            Text("Waste Risk").font(PPTypography.sectionTitle)
            if let assessment {
                if let level = assessment.level {
                    StatusBadge(title: "\(level.rawValue) • Core ML", tone: level.statusTone)
                        .accessibilityIdentifier("wasteRisk.prediction")
                    Text("Experimental model trained on synthetic scenarios. Not a food-safety assessment or a calibrated probability.")
                        .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                    Text("Recorded inputs").font(PPTypography.cardTitle)
                    ForEach(assessment.explanation, id: \.self) { Text($0).font(PPTypography.caption) }
                    Text("These are the inputs used, not measured causes of this prediction.")
                        .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                } else {
                    StatusBadge(title: "Risk unavailable")
                        .accessibilityIdentifier("wasteRisk.unavailable")
                    Text(assessment.unavailableReason ?? "Please try again.").font(PPTypography.caption)
                    Text("Expiry rules remain available; they are not a model prediction.")
                        .font(PPTypography.caption).foregroundStyle(PPColors.secondaryText)
                }
            } else {
                ProgressView("Assessing on device…")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ppCard()
        .accessibilityIdentifier("foodDetails.wasteRisk")
    }
}

extension WasteRiskLevel {
    var statusTone: PPStatusTone {
        switch self { case .low: .success; case .medium: .warning; case .high: .danger }
    }
}

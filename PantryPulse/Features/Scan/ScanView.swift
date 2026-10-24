import SwiftUI

struct ScanView: View {
    let onRecognition: () -> Void
    let onBarcode: () -> Void
    let onManualEntry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PPSpacing.xl) {
                ScreenHeader(title: "Add to your pantry", subtitle: "Choose how you'd like to add food.")
                choice(title: "Recognize Food", subtitle: "Photograph food for on-device suggestions you can correct.",
                       symbol: "camera.viewfinder", action: onRecognition)
                choice(title: "Scan a Barcode", subtitle: "Look up packaged food with Open Food Facts.",
                       symbol: "barcode.viewfinder", action: onBarcode)
                SecondaryButton(title: "Enter Manually", systemImage: "square.and.pencil", action: onManualEntry)
                Text("Scan a barcode or enter it manually to look up packaged food. Camera access is requested only when you open the scanner.")
                    .font(PPTypography.body).foregroundStyle(PPColors.secondaryText)
            }
            .padding(PPSpacing.lg)
            .frame(maxWidth: PPMetrics.screenContentWidth)
            .frame(maxWidth: .infinity)
        }
        .background(PPColors.background)
        .navigationTitle("Scan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func choice(title: String, subtitle: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: PPSpacing.sm) {
                Image(systemName: symbol).font(.largeTitle).foregroundStyle(PPColors.actionText)
                    .accessibilityHidden(true)
                NavigationRowLabel(title: title)
                    .font(PPTypography.sectionTitle)
                Text(subtitle).font(PPTypography.body).foregroundStyle(PPColors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ppCard(padding: PPSpacing.xl)
        }
        .buttonStyle(.plain)
        .foregroundStyle(PPColors.text)
        .accessibilityHint("Open this option")
    }
}

#Preview { NavigationStack { ScanView(onRecognition: {}, onBarcode: {}, onManualEntry: {}) } }

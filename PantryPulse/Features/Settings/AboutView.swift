import SwiftUI

struct AboutView: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    var body: some View {
        List {
            Section("PantryPulse") {
                LabeledContent("Version", value: version)
                Text("A coursework app for keeping track of food and reducing household waste.")
            }
            Section("This version") {
                Text("Inventory is stored locally. Barcode scanning and Open Food Facts lookup are available. Local expiry reminders and date-based Use First prioritisation are available. Food recognition offers editable on-device suggestions from the bundled 151-class model.")
            }
            Section("Product data") {
                Text("Product data: Open Food Facts contributors (ODbL). Product images: CC BY-SA. Imported images are resized for local storage.")
                if let url = URL(string: "https://world.openfoodfacts.org/terms-of-use") {
                    Link("Open Food Facts attribution and terms", destination: url)
                }
            }
            Section("Privacy") {
                Text("Pantry records and saved photos stay on this device. Barcode lookup sends the barcode to Open Food Facts and downloads available product information and photos. Camera access is requested when you open the barcode scanner or choose Take Photo. No camera frames are uploaded. Local notifications are scheduled only when you enable expiry reminders and grant notification access.")
            }
        }
        .font(PPTypography.body)
        .scrollContentBackground(.hidden)
        .background(PPColors.background)
        .navigationTitle("About PantryPulse")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PPActionLabel(title: title, systemImage: systemImage, stacksAtAccessibilitySizes: true)
        }
        .buttonStyle(PPButtonStyle(kind: .secondary))
    }
}

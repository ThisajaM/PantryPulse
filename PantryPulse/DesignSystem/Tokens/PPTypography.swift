import SwiftUI
import UIKit

enum PPTypography {
    static var onboardingTitle: Font { font(size: 30, relativeTo: .largeTitle, weight: .bold, face: "Bold") }
    static var heroStatistic: Font { font(size: 38, relativeTo: .largeTitle, weight: .bold, face: "Bold") }
    static var screenTitle: Font { font(size: 26, relativeTo: .title2, weight: .bold, face: "Bold") }
    static var sectionTitle: Font { font(size: 18, relativeTo: .headline, weight: .semibold, face: "SemiBold") }
    static var cardTitle: Font { font(size: 14, relativeTo: .subheadline, weight: .semibold, face: "SemiBold") }
    static var body: Font { font(size: 15, relativeTo: .body, weight: .regular, face: "Regular") }
    static var button: Font { font(size: 17, relativeTo: .headline, weight: .semibold, face: "SemiBold") }
    static var caption: Font { font(size: 12, relativeTo: .caption, weight: .medium, face: "Medium") }
    static var badge: Font { font(size: 12, relativeTo: .caption, weight: .semibold, face: "SemiBold") }
    static var statistic: Font { font(size: 28, relativeTo: .title, weight: .bold, face: "Bold") }

    private static func font(size: CGFloat, relativeTo style: Font.TextStyle, weight: Font.Weight, face: String) -> Font {
        // Custom fonts must be bundled and registered via UIAppFonts by the app.
        // Checking first avoids silently falling back to an incorrectly sized custom font.
        let candidates = ["PlusJakartaSans-\(face)", "PlusJakartaSansRoman-\(face)"]
        if let name = candidates.first(where: { UIFont(name: $0, size: size) != nil }) {
            return .custom(name, size: size, relativeTo: style)
        }
        return .system(style, design: .default).weight(weight)
    }
}

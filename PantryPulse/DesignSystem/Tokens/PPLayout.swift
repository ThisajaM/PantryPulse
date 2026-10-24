import SwiftUI

enum PPSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

enum PPCornerRadius {
    static let small: CGFloat = 12
    static let image: CGFloat = 18
    static let card: CGFloat = 22
    static let hero: CGFloat = 28
    // Pill controls use Capsule(), not a hardcoded approximation of infinity.
}

enum PPMetrics {
    static let onboardingContentWidth: CGFloat = 448
    static let onboardingIndicatorWidth: CGFloat = 20
    static let onboardingHeroHeightFraction: CGFloat = 0.55
    static let screenContentWidth: CGFloat = 760
    static let foodCardMinimumWidth: CGFloat = 150
    static let foodThumbnail: CGFloat = 56
    static let pantryFoodImageAspectRatio: CGFloat = 148.0 / 111.0
    static let emptyPantryArtwork: CGFloat = 256
    static let summaryArcWidth: CGFloat = 240
    static let summaryArcHeight: CGFloat = 140
    static let summaryArcStroke: CGFloat = 12
    static let minimumTapTarget: CGFloat = 44
    static let primaryButtonHeight: CGFloat = 56
    static let secondaryButtonHeight: CGFloat = 48
    static let statusDot: CGFloat = 6
    static let emptyStateSymbol: CGFloat = 48
    static let cardShadowRadius: CGFloat = 12
    static let cardShadowOffset: CGFloat = 4
    static let cardShadowOpacity: Double = 0.06
    static let disabledOpacity: Double = 0.45
    static let pressedOpacity: Double = 0.82
}

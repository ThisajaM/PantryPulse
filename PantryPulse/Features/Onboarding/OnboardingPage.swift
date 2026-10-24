import Foundation

enum OnboardingPage: Int, CaseIterable, Identifiable {
    case welcome, expiry, recognition

    var id: Self { self }
    var displayTitle: String {
        switch self {
        case .welcome: "Your Pantry,\nSmarter"
        case .expiry: title
        case .recognition: "Snap It.\nWe'll Identify It."
        }
    }
    var title: String {
        switch self {
        case .welcome: "Your Pantry, Smarter"
        case .expiry: "Never Miss an Expiry"
        case .recognition: "Snap It. We'll Identify It."
        }
    }
    var message: String {
        switch self {
        case .welcome: "Know what you have.\nKnow what to use first."
        case .expiry: "Keep expiry dates in view and plan what to use next. Enable gentle expiry reminders in Settings when you are ready."
        case .recognition: "Take or choose a food photo for on-device suggestions. Review and correct the result before adding it to your pantry."
        }
    }
    var artwork: String {
        switch self {
        case .welcome: "OnboardingWelcome"
        case .expiry: "OnboardingExpiry"
        case .recognition: "OnboardingRecognition"
        }
    }
    var next: Self? { Self(rawValue: rawValue + 1) }
}

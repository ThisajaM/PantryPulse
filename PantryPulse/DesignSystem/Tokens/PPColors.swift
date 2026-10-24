import SwiftUI

/// Asset-backed semantic colours. The default (light) values match the Figma palette.
enum PPColors {
    static let primary = Color("AccentColor") // #FF9A62
    static let background = Color("PPBackground") // #F6F2EB
    static let text = Color("PPText") // #202020
    static let success = Color("PPSuccess") // #78A96B
    static let danger = Color("PPDanger") // #C94F4F

    static let surface = Color("PPSurface")
    static let secondaryText = Color("PPSecondaryText")
    static let mutedSurface = Color("PPMutedSurface")
    static let warning = Color("PPWarning")
    static let coral = Color("PPCoral")
    static let actionText = Color("PPActionText")
    static let onPrimary = Color("PPOnPrimary")
    static let successText = Color("PPSuccessText")
    static let successSurface = Color("PPSuccessSurface")
    static let warningText = Color("PPWarningText")
    static let warningSurface = Color("PPWarningSurface")
    static let dangerText = Color("PPDangerText")
    static let dangerSurface = Color("PPDangerSurface")
    static let shadow = Color("PPShadow")
    static let tabBarBackground = Color("PPTabBarBackground") // Figma #242424 at 95%
}

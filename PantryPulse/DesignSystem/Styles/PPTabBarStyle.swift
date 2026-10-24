import SwiftUI

/// Preserve native tab geometry and contrast across system tab-bar appearances.
struct PPTabBarStyle: ViewModifier {
    static var selectionTint: Color {
        if #available(iOS 26.0, *) {
            PPColors.actionText
        } else {
            PPColors.primary
        }
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Liquid Glass adapts to its backdrop. Forcing a dark toolbar scheme
            // over the light glass surface made labels unreadable on iOS 26.3.
            content
        } else {
            content
                .toolbarBackground(PPColors.tabBarBackground, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .toolbarColorScheme(.dark, for: .tabBar)
        }
    }
}

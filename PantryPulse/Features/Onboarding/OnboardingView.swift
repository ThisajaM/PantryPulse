import SwiftUI

/// Presentation only: the app owns completion storage; Settings can replay without resetting it.
struct OnboardingView: View {
    let onComplete: () -> Void
    @State private var page: OnboardingPage = .welcome
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(OnboardingPage.allCases) { page in
                    OnboardingPageView(page: page).tag(page)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .top)
            .accessibilityIdentifier("onboarding.pages")

            VStack(spacing: PPSpacing.sm) {
                pageIndicators
                PrimaryButton(title: page.next == nil ? "Get Started" : "Continue",
                              systemImage: dynamicTypeSize.isAccessibilitySize ? nil : "arrow.right") {
                    if let next = page.next { select(next) } else { onComplete() }
                }
                .accessibilityIdentifier("onboarding.continue")
                Button("Skip", action: onComplete)
                    .font(PPTypography.body)
                    .foregroundStyle(PPColors.secondaryText)
                    .frame(minHeight: PPMetrics.minimumTapTarget)
                    .accessibilityHint("Finish the introduction and open your dashboard")
                    .accessibilityIdentifier("onboarding.skip")
            }
            .padding(.horizontal, PPSpacing.xl)
            .padding(.bottom, PPSpacing.xs)
            .frame(maxWidth: PPMetrics.onboardingContentWidth)
        }
        .background(PPColors.background.ignoresSafeArea())
    }

    private var pageIndicators: some View {
        HStack(spacing: 0) {
            ForEach(OnboardingPage.allCases) { candidate in
                Button { select(candidate) } label: {
                    Capsule()
                        .fill(page == candidate ? PPColors.primary : PPColors.secondaryText.opacity(0.35))
                        .frame(width: page == candidate ? PPMetrics.onboardingIndicatorWidth : PPMetrics.statusDot,
                               height: PPMetrics.statusDot)
                        .frame(width: PPMetrics.minimumTapTarget, height: PPMetrics.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Page \(candidate.rawValue + 1) of \(OnboardingPage.allCases.count): \(candidate.title)")
                .accessibilityAddTraits(page == candidate ? .isSelected : [])
                .accessibilityIdentifier("onboarding.page.\(candidate.rawValue)")
            }
        }
    }

    private func select(_ page: OnboardingPage) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { self.page = page }
    }
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: PPSpacing.xl) {
                    Rectangle()
                        .fill(PPColors.background)
                        .frame(height: min(geometry.size.width, geometry.size.height * PPMetrics.onboardingHeroHeightFraction))
                        .overlay {
                            Image(page.artwork).resizable().scaledToFill()
                        }
                        .clipped()
                        .overlay {
                            LinearGradient(stops: [.init(color: .clear, location: 0.55),
                                                   .init(color: PPColors.background, location: 1)],
                                           startPoint: .top, endPoint: .bottom)
                        }
                        .overlay(alignment: .top) {
                            LinearGradient(stops: [
                                .init(color: (colorScheme == .dark ? Color.black : Color.white).opacity(0.28), location: 0),
                                .init(color: .clear, location: 0.25)
                            ], startPoint: .top, endPoint: .bottom)
                        }
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: PPSpacing.sm) {
                        Text(page.displayTitle)
                            .font(PPTypography.onboardingTitle)
                            .foregroundStyle(PPColors.text)
                            .accessibilityLabel(page.title)
                            .accessibilityAddTraits(.isHeader)
                        Text(page.message)
                            .font(PPTypography.body)
                            .foregroundStyle(PPColors.secondaryText)
                            .accessibilityIdentifier("onboarding.message.\(page.rawValue)")
                        if page != .welcome {
                            StatusBadge(title: page == .expiry ? "Enable in Settings" : "Review every suggestion", tone: .neutral,
                                        systemImage: page == .expiry ? "bell" : "camera")
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, PPSpacing.xl)
                    .padding(.bottom, PPSpacing.md)
                }
                .frame(maxWidth: PPMetrics.onboardingContentWidth)
                .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea(.container, edges: .top)
        }
    }
}

#Preview("Introduction") { OnboardingView(onComplete: {}) }
#Preview("Large text") {
    OnboardingView(onComplete: {}).environment(\.dynamicTypeSize, .accessibility3)
}

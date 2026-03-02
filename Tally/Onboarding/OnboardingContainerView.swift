import SwiftUI

struct OnboardingContainerView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var currentPage = 0

    private let pages: [(title: String, subtitle: String)] = [
        ("Create your group", "Add friends and name your trip, household, or event"),
        ("Track every expense", "Snap a receipt or enter amounts — Tally does the math"),
        ("Split & settle instantly", "Expenses are divided fairly and you can pay right in the app"),
    ]

    private var isLastPage: Bool { currentPage == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Swipeable illustration area
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    illustrationForPage(index)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 340)

            // Title + subtitle (updates with swipe)
            Text(pages[currentPage].title)
                .font(TallyFont.title)
                .foregroundStyle(TallyColors.textPrimary)
                .multilineTextAlignment(.center)
                .animation(.none, value: currentPage)
                .padding(.bottom, TallySpacing.sm)

            Text(pages[currentPage].subtitle)
                .font(TallyFont.body)
                .foregroundStyle(TallyColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TallySpacing.xxl)
                .animation(.none, value: currentPage)
                .padding(.bottom, TallySpacing.xl)

            // Page indicator (shared, reacts to swipe)
            PageIndicatorView(pageCount: pages.count, currentPage: currentPage)

            Spacer()

            // Buttons (fixed at bottom)
            VStack(spacing: TallySpacing.lg) {
                Button(isLastPage ? "Get Started" : "Continue") {
                    advance()
                }
                .buttonStyle(TallyPrimaryButtonStyle())

                if !isLastPage {
                    Button("Skip") {
                        finish()
                    }
                    .buttonStyle(TallyGhostButtonStyle())
                }
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
    }

    @ViewBuilder
    private func illustrationForPage(_ index: Int) -> some View {
        switch index {
        case 0: OnboardingCreateGroupView()
        case 1: OnboardingTrackExpenseView()
        case 2: OnboardingSplitSettleView()
        default: EmptyView()
        }
    }

    private func advance() {
        if currentPage < pages.count - 1 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                currentPage += 1
            }
        } else {
            finish()
        }
    }

    private func finish() {
        authManager.completeOnboarding()
    }
}

#Preview {
    OnboardingContainerView()
        .environment(AuthManager())
}

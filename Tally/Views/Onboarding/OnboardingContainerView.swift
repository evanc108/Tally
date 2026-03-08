import SwiftUI

struct OnboardingContainerView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var currentPage = 0
    @State private var appeared = false

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Create your circle",
            subtitle: "Invite friends and family to split expenses together with one shared card.",
            illustration: .circle
        ),
        OnboardingPage(
            title: "Track every expense",
            subtitle: "See who owes what in real-time. Scan receipts for instant itemized splits.",
            illustration: .receipt
        ),
        OnboardingPage(
            title: "Settle instantly",
            subtitle: "Splits are settled automatically from linked bank accounts. Zero hassle.",
            illustration: .settle
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Back button
            HStack {
                Button {
                    if currentPage > 0 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage -= 1
                        }
                    } else {
                        authManager.backToWelcome()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(TallyIcon.md)
                        .foregroundStyle(TallyColors.textSecondary)
                        .frame(width: 44, height: 44)
                }
                Spacer()
            }
            .padding(.horizontal, TallySpacing.sm)

            // Pages
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    OnboardingPageView(page: page, isActive: index == currentPage)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Bottom controls
            VStack(spacing: TallySpacing.md) {
                PageIndicator(count: pages.count, current: currentPage)

                Button(isLastPage ? "Get Started" : "Next") {
                    if isLastPage {
                        authManager.beginAuth(mode: .signUp)
                    } else {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage += 1
                        }
                    }
                }
                .buttonStyle(OnboardingButtonStyle())
                .padding(.horizontal, TallySpacing.lg)
                .offset(y: appeared ? 0 : 40)
                .opacity(appeared ? 1 : 0)
            }
            .padding(.bottom, TallySpacing.xl)
        }
        .background(TallyColors.bgPrimary)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.1)) {
                appeared = true
            }
        }
    }

    private var isLastPage: Bool { currentPage == pages.count - 1 }
}

// MARK: - Data Model

struct OnboardingPage {
    let title: String
    let subtitle: String
    let illustration: IllustrationType

    enum IllustrationType {
        case circle, receipt, settle
    }
}

// MARK: - Page View

private struct OnboardingPageView: View {
    let page: OnboardingPage
    let isActive: Bool

    @State private var textVisible = false
    @State private var illustrationScale: CGFloat = 0.85

    var body: some View {
        VStack(spacing: TallySpacing.sm) {
            Spacer()

            illustrationView
                .frame(width: 300, height: 300)
                .scaleEffect(illustrationScale)

            Text(page.title)
                .font(TallyFont.title)
                .foregroundStyle(TallyColors.textPrimary)
                .tracking(-0.48)
                .padding(.top, TallySpacing.xl)
                .offset(y: textVisible ? 0 : 20)
                .opacity(textVisible ? 1 : 0)

            Text(page.subtitle)
                .font(TallyFont.body)
                .foregroundStyle(TallyColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TallySpacing.xxxl)
                .offset(y: textVisible ? 0 : 14)
                .opacity(textVisible ? 1 : 0)

            Spacer()
            Spacer()
        }
        .onChange(of: isActive) {
            if isActive {
                textVisible = false
                illustrationScale = 0.85
                withAnimation(.spring(duration: 0.55, bounce: 0.2).delay(0.05)) {
                    illustrationScale = 1
                }
                withAnimation(.spring(duration: 0.5, bounce: 0.15).delay(0.12)) {
                    textVisible = true
                }
            }
        }
        .onAppear {
            if isActive {
                withAnimation(.spring(duration: 0.55, bounce: 0.2).delay(0.2)) {
                    illustrationScale = 1
                }
                withAnimation(.spring(duration: 0.5, bounce: 0.15).delay(0.3)) {
                    textVisible = true
                }
            }
        }
    }

    @ViewBuilder
    private var illustrationView: some View {
        switch page.illustration {
        case .circle:
            CircleIllustration()
        case .receipt:
            ReceiptIllustration()
        case .settle:
            SettleIllustration()
        }
    }
}

// MARK: - Illustrations

private struct CircleIllustration: View {
    @State private var orbiting = false
    @State private var cardVisible = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0xEAFBEA))
                .frame(width: 260, height: 260)
                .scaleEffect(orbiting ? 1 : 0.9)
            Circle()
                .fill(Color(hex: 0xD4F7D4))
                .frame(width: 200, height: 200)
                .scaleEffect(orbiting ? 1 : 0.92)

            // Tally card
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [TallyColors.accent, TallyColors.accent.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 140, height: 90)
                .shadow(color: TallyColors.accent.opacity(0.25), radius: 12, y: 8)
                .overlay(alignment: .topLeading) {
                    Text("tally")
                        .font(TallyFont.brandTiny)
                        .foregroundStyle(.white)
                        .tracking(-0.3)
                        .padding(.leading, 14)
                        .padding(.top, 14)
                }
                .scaleEffect(cardVisible ? 1 : 0.6)
                .opacity(cardVisible ? 1 : 0)
                .rotation3DEffect(.degrees(cardVisible ? 0 : 15), axis: (x: 1, y: 0, z: 0))

            // User avatars with orbit
            avatarBubble(color: Color(hex: 0x8B7FDB), bg: Color(hex: 0xF0EEFF), angle: 225, distance: 115)
            avatarBubble(color: Color(hex: 0xF0A030), bg: Color(hex: 0xFFF5E6), angle: 315, distance: 115)
            avatarBubble(color: Color(hex: 0x4088F0), bg: Color(hex: 0xE6F0FF), angle: 160, distance: 125)
            avatarBubble(color: Color(hex: 0xF04060), bg: Color(hex: 0xFFE6EA), angle: 20, distance: 125)

            // Dollar badges
            dollarBadge(angle: 190, distance: 105)
            dollarBadge(angle: 350, distance: 105)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.7, bounce: 0.2).delay(0.1)) {
                orbiting = true
            }
            withAnimation(.spring(duration: 0.6, bounce: 0.25).delay(0.25)) {
                cardVisible = true
            }
        }
    }

    private func avatarBubble(color: Color, bg: Color, angle: Double, distance: CGFloat) -> some View {
        let rad = angle * .pi / 180
        let shift: CGFloat = orbiting ? 0 : 20
        let x = cos(rad) * distance + (orbiting ? 0 : shift)
        let y = sin(rad) * distance + (orbiting ? 0 : shift)

        return Circle()
            .fill(bg)
            .frame(width: 44, height: 44)
            .overlay(
                Circle()
                    .fill(color)
                    .frame(width: 22, height: 22)
            )
            .shadow(color: .black.opacity(0.1), radius: 6, y: 4)
            .offset(x: x, y: y)
            .opacity(orbiting ? 1 : 0)
    }

    private func dollarBadge(angle: Double, distance: CGFloat) -> some View {
        let rad = angle * .pi / 180
        return Text("$")
            .font(TallyFont.microBold)
            .foregroundStyle(TallyColors.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.white)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            .offset(x: cos(rad) * distance, y: sin(rad) * distance)
            .opacity(orbiting ? 1 : 0)
    }
}

private struct ReceiptIllustration: View {
    @State private var receiptVisible = false
    @State private var cameraVisible = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0xEAFBEA))
                .frame(width: 260, height: 260)
            Circle()
                .fill(Color(hex: 0xD4F7D4))
                .frame(width: 200, height: 200)

            // Receipt card
            RoundedRectangle(cornerRadius: 12)
                .fill(.white)
                .frame(width: 130, height: 155)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
                .overlay {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The Rustic Table")
                            .font(TallyFont.micro)
                            .foregroundStyle(TallyColors.textPrimary)
                        Text("Mar 1, 2026")
                            .font(TallyFont.decorativeTiny)
                            .foregroundStyle(TallyColors.textTertiary)

                        Spacer().frame(height: 4)

                        receiptLine("Margherita Pizza", "$18.00")
                        receiptLine("Caesar Salad", "$12.50")
                        receiptLine("Pasta Carbonara", "$22.00")

                        Divider()

                        HStack {
                            Text("Total")
                                .font(TallyFont.decorativeBold)
                            Spacer()
                            Text("$73.13")
                                .font(TallyFont.decorativeBold)
                        }
                        .foregroundStyle(TallyColors.textPrimary)
                    }
                    .padding(12)
                }
                .offset(x: 20, y: receiptVisible ? -15 : 10)
                .scaleEffect(receiptVisible ? 1 : 0.8)
                .opacity(receiptVisible ? 1 : 0)
                .rotation3DEffect(.degrees(receiptVisible ? 0 : -10), axis: (x: 0, y: 1, z: 0))

            // Camera icon
            Circle()
                .fill(Color(hex: 0xE8F8E8))
                .frame(width: 80, height: 80)
                .overlay(
                    Image(systemName: "camera.fill")
                        .font(TallyIcon.xxxl)
                        .foregroundStyle(TallyColors.accent)
                )
                .offset(x: -70, y: 30)
                .scaleEffect(cameraVisible ? 1 : 0.4)
                .opacity(cameraVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.65, bounce: 0.2).delay(0.15)) {
                receiptVisible = true
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.3).delay(0.35)) {
                cameraVisible = true
            }
        }
    }

    private func receiptLine(_ item: String, _ price: String) -> some View {
        HStack {
            Text(item)
                .font(TallyFont.decorative)
                .foregroundStyle(TallyColors.textSecondary)
            Spacer()
            Text(price)
                .font(TallyFont.decorative)
                .foregroundStyle(TallyColors.textSecondary)
        }
    }
}

private struct SettleIllustration: View {
    @State private var cardsVisible = false
    @State private var arrowVisible = false
    @State private var settledVisible = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0xEAFBEA))
                .frame(width: 260, height: 260)
            Circle()
                .fill(Color(hex: 0xD4F7D4))
                .frame(width: 200, height: 200)

            // Bank cards
            bankCard(name: "Chase", last4: "4821", amount: "$1,240")
                .offset(x: cardsVisible ? -70 : -20, y: -50)
                .opacity(cardsVisible ? 1 : 0)

            bankCard(name: "BofA", last4: "7392", amount: "$890")
                .offset(x: cardsVisible ? 70 : 20, y: -50)
                .opacity(cardsVisible ? 1 : 0)

            // Transfer arrow
            VStack(spacing: 4) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(TallyIcon.lg)
                    .foregroundStyle(TallyColors.accent)
                Text("$24.50")
                    .font(TallyFont.microBold)
                    .foregroundStyle(TallyColors.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(TallyColors.accent.opacity(0.15))
                    .clipShape(Capsule())
            }
            .offset(y: -30)
            .scaleEffect(arrowVisible ? 1 : 0.5)
            .opacity(arrowVisible ? 1 : 0)

            // User avatars
            Circle()
                .fill(Color(hex: 0xD4F7D4))
                .frame(width: 32, height: 32)
                .overlay(
                    Text("A")
                        .font(TallyFont.avatarTiny)
                        .foregroundStyle(TallyColors.accent.opacity(0.7))
                )
                .offset(x: -90, y: 70)
                .opacity(cardsVisible ? 1 : 0)

            Circle()
                .fill(Color(hex: 0xD4F7D4))
                .frame(width: 32, height: 32)
                .overlay(
                    Text("S")
                        .font(TallyFont.avatarTiny)
                        .foregroundStyle(TallyColors.accent.opacity(0.7))
                )
                .offset(x: 90, y: 70)
                .opacity(cardsVisible ? 1 : 0)

            // Settled badge
            Text("Settled \u{2713}")
                .font(TallyFont.smallLabelSemibold)
                .foregroundStyle(TallyColors.accent.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(TallyColors.accent.opacity(0.15))
                .clipShape(Capsule())
                .offset(y: 100)
                .scaleEffect(settledVisible ? 1 : 0.5)
                .opacity(settledVisible ? 1 : 0)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.15).delay(0.1)) {
                cardsVisible = true
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.25).delay(0.35)) {
                arrowVisible = true
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.3).delay(0.6)) {
                settledVisible = true
            }
        }
    }

    private func bankCard(name: String, last4: String, amount: String) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.white)
            .frame(width: 100, height: 60)
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            .overlay(alignment: .leading) {
                VStack(alignment: .leading, spacing: 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(TallyColors.accent.opacity(0.3))
                        .frame(width: 36, height: 6)
                    Text("\(name) \u{2022}\u{2022}\(last4)")
                        .font(TallyFont.decorative)
                        .foregroundStyle(TallyColors.textSecondary)
                    Text(amount)
                        .font(TallyFont.overline)
                        .foregroundStyle(TallyColors.textPrimary)
                }
                .padding(.leading, 10)
            }
    }
}

// MARK: - Page Indicator

private struct PageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? TallyColors.accent : TallyColors.divider)
                    .frame(width: index == current ? 24 : 8, height: 8)
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.2), value: current)
    }
}

// MARK: - Onboarding Button Style

private struct OnboardingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TallyFont.buttonBold)
            .tracking(-0.2)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(TallyColors.accent)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.buttonCornerRadius))
            .shadow(color: TallyColors.accent.opacity(configuration.isPressed ? 0 : 0.25), radius: 10, y: 5)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.3), value: configuration.isPressed)
    }
}

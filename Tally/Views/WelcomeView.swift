import SwiftUI

struct WelcomeView: View {
    @Environment(AuthManager.self) private var authManager

    @State private var iconVisible = false
    @State private var logoVisible = false
    @State private var taglineVisible = false
    @State private var featuresVisible = false
    @State private var buttonsVisible = false
    @State private var legalVisible = false
    @State private var iconFloat: Bool = false
    @State private var gradientShift: Bool = false

    var body: some View {
        ZStack {
            // Animated gradient background
            LinearGradient(
                colors: gradientShift
                    ? [Color(hex: 0x2D6A4F), TallyColors.hunterGreen, Color(hex: 0x1B4332)]
                    : [TallyColors.seaGreen, TallyColors.hunterGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .onAppear {
                withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
                    gradientShift = true
                }
            }

            // Lighter green corner circles
            CornerBlobs()
                .ignoresSafeArea()

            // Subtle floating particles
            FloatingParticles()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()
                    .frame(minHeight: 40, maxHeight: 80)

                // Icon with float animation
                RoundedRectangle(cornerRadius: 28)
                    .fill(.white.opacity(0.15))
                    .stroke(.white.opacity(0.25), lineWidth: 1)
                    .frame(width: 96, height: 96)
                    .overlay(
                        Image(systemName: "creditcard.fill")
                            .font(TallyIcon.heroLg)
                            .foregroundStyle(.white)
                    )
                    .offset(y: iconFloat ? -6 : 6)
                    .scaleEffect(iconVisible ? 1 : 0.5)
                    .opacity(iconVisible ? 1 : 0)

                // Logo
                Text("tally")
                    .font(TallyFont.brandHero)
                    .foregroundStyle(.white)
                    .tracking(-2.5)
                    .padding(.top, TallySpacing.lg)
                    .scaleEffect(logoVisible ? 1 : 0.8)
                    .opacity(logoVisible ? 1 : 0)
                    .blur(radius: logoVisible ? 0 : 6)

                // Tagline
                Text("Split expenses, share cards,\nand settle up instantly.")
                    .font(TallyFont.bodyLarge)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.top, TallySpacing.sm)
                    .offset(y: taglineVisible ? 0 : 16)
                    .opacity(taglineVisible ? 1 : 0)

                Spacer()
                    .frame(minHeight: 24, maxHeight: 48)

                // Feature highlights
                VStack(spacing: 12) {
                    FeatureRow(icon: "person.2.fill", text: "Create circles with friends")
                    FeatureRow(icon: "creditcard.fill", text: "Get virtual cards for group spending")
                    FeatureRow(icon: "arrow.triangle.2.circlepath", text: "Auto-split and settle instantly")
                }
                .padding(.horizontal, TallySpacing.xxxl)
                .offset(y: featuresVisible ? 0 : 20)
                .opacity(featuresVisible ? 1 : 0)

                Spacer()
                    .frame(minHeight: 32, maxHeight: 60)

                // Buttons
                VStack(spacing: TallySpacing.md) {
                    Button("Get Started") {
                        authManager.showOnboarding()
                    }
                    .buttonStyle(WelcomePrimaryButtonStyle())
                    .offset(y: buttonsVisible ? 0 : 30)
                    .opacity(buttonsVisible ? 1 : 0)

                    Button("I already have an account") {
                        authManager.beginAuth(mode: .login)
                    }
                    .buttonStyle(WelcomeSecondaryButtonStyle())
                    .offset(y: buttonsVisible ? 0 : 40)
                    .opacity(buttonsVisible ? 1 : 0)
                }
                .padding(.horizontal, TallySpacing.screenPadding)

                // Legal
                Text(legalText)
                    .font(TallyFont.smallLabelSemibold)
                    .multilineTextAlignment(.center)
                    .padding(.top, TallySpacing.lg)
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.bottom, TallySpacing.lg)
                    .opacity(legalVisible ? 1 : 0)
            }
        }
        .onAppear { runEntranceAnimations() }
    }

    // MARK: - Staggered Entrance

    private func runEntranceAnimations() {
        iconVisible = false; logoVisible = false; taglineVisible = false
        featuresVisible = false; buttonsVisible = false; legalVisible = false; iconFloat = false

        withAnimation(.spring(duration: 0.7, bounce: 0.35).delay(0.1)) {
            iconVisible = true
        }
        withAnimation(.spring(duration: 0.6, bounce: 0.2).delay(0.25)) {
            logoVisible = true
        }
        withAnimation(.spring(duration: 0.5, bounce: 0.15).delay(0.4)) {
            taglineVisible = true
        }
        withAnimation(.spring(duration: 0.5, bounce: 0.15).delay(0.55)) {
            featuresVisible = true
        }
        withAnimation(.spring(duration: 0.6, bounce: 0.2).delay(0.7)) {
            buttonsVisible = true
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.85)) {
            legalVisible = true
        }
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true).delay(0.8)) {
            iconFloat = true
        }
    }

    private var legalText: AttributedString {
        var text = AttributedString("By continuing, you agree to our Terms of Service and Privacy Policy")
        text.foregroundColor = .white.withAlphaComponent(0.45)

        if let range = text.range(of: "Terms of Service") {
            text[range].foregroundColor = .white.withAlphaComponent(0.65)
            text[range].underlineStyle = .single
        }
        if let range = text.range(of: "Privacy Policy") {
            text[range].foregroundColor = .white.withAlphaComponent(0.65)
            text[range].underlineStyle = .single
        }
        return text
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(TallyIcon.sm)
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 24)

            Text(text)
                .font(TallyFont.bodySemibold)
                .foregroundStyle(.white.opacity(0.75))

            Spacer()
        }
    }
}

// MARK: - Corner Blobs

private struct CornerBlobs: View {
    @State private var animate = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.10), .white.opacity(0)],
                        center: .center, startRadius: 0, endRadius: 180
                    )
                )
                .frame(width: 360, height: 360)
                .offset(x: -w * 0.35, y: -h * 0.08)
                .offset(x: animate ? 8 : -8, y: animate ? 6 : -6)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.07), .white.opacity(0)],
                        center: .center, startRadius: 0, endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: w * 0.55, y: -h * 0.05)
                .offset(x: animate ? -6 : 6, y: animate ? 8 : -8)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.06), .white.opacity(0)],
                        center: .center, startRadius: 0, endRadius: 140
                    )
                )
                .frame(width: 280, height: 280)
                .offset(x: -w * 0.25, y: h * 0.35)
                .offset(x: animate ? 10 : -10)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.08), .white.opacity(0)],
                        center: .center, startRadius: 0, endRadius: 160
                    )
                )
                .frame(width: 320, height: 320)
                .offset(x: w * 0.5, y: h * 0.65)
                .offset(x: animate ? -8 : 8, y: animate ? -6 : 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 5).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Floating Particles

private struct FloatingParticles: View {
    @State private var animate = false

    var body: some View {
        Canvas { context, size in
            let particles: [(CGFloat, CGFloat, CGFloat)] = [
                (0.15, 0.2, 4), (0.85, 0.15, 3), (0.3, 0.7, 5),
                (0.7, 0.8, 3.5), (0.5, 0.45, 2.5), (0.1, 0.55, 3),
                (0.9, 0.5, 4), (0.4, 0.1, 2), (0.6, 0.9, 3),
            ]

            for (xRatio, yRatio, radius) in particles {
                let shift: CGFloat = animate ? 12 : -12
                let x = xRatio * size.width + shift * (xRatio > 0.5 ? 1 : -1)
                let y = yRatio * size.height + shift * (yRatio > 0.5 ? -1 : 1)
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(.white.opacity(0.06))
                )
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

// MARK: - Welcome-Specific Button Styles

private struct WelcomePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TallyFont.buttonLarge)
            .tracking(-0.2)
            .foregroundStyle(TallyColors.hunterGreen)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: TallyRadius.xl))
            .shadow(color: .black.opacity(configuration.isPressed ? 0 : 0.12), radius: 12, y: 6)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.3), value: configuration.isPressed)
    }
}

private struct WelcomeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TallyFont.buttonLarge)
            .tracking(-0.2)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(.white.opacity(configuration.isPressed ? 0.2 : 0.1))
            .clipShape(RoundedRectangle(cornerRadius: TallyRadius.xl))
            .overlay(
                RoundedRectangle(cornerRadius: TallyRadius.xl)
                    .stroke(.white.opacity(0.25), lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.3, bounce: 0.3), value: configuration.isPressed)
    }
}

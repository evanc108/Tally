import SwiftUI

/// Unified premium card component used across Wallet, Home, and onboarding.
///
/// **Full mode** (default): no internal sizing — caller controls size.
///   - Wallet stack:   `.frame(maxWidth: .infinity).frame(height: h)`
///   - CardIssuedView: `.aspectRatio(1.586, contentMode: .fit)`
///
/// **Wallet layout** (`walletLayout: true`): name top-left, balance top-right,
///   VISA + expiry stacked bottom-right. Used exclusively in WalletTab.
///
/// **Compact mode**: fixed 170 × 110 for horizontal scroll cards on Home.
struct TallyCard: View {
    let circleName: String
    let last4: String
    var balance: Double = 0.0
    var colorIndex: Int = 0
    var photo: UIImage? = nil
    var expiry: String = "12/28"
    var compact: Bool = false
    var walletLayout: Bool = false

    // MARK: - Theme Gradient

    private var themeGradient: (dark: Color, mid: Color, light: Color) {
        let themeUI: UIColor = {
            if let p = photo, let dom = p.dominantColor { return dom }
            return UIColor(TallyColors.cardColor(for: colorIndex))
        }()
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        themeUI.getRed(&r, green: &g, blue: &b, alpha: nil)
        return (
            dark:  Color(red: Double(r * 0.35), green: Double(g * 0.35), blue: Double(b * 0.35)),
            mid:   Color(red: Double(r * 0.55), green: Double(g * 0.55), blue: Double(b * 0.55)),
            light: Color(red: Double(r * 0.72), green: Double(g * 0.72), blue: Double(b * 0.72))
        )
    }

    // MARK: - Body

    var body: some View {
        if compact {
            compactCard
        } else if walletLayout {
            walletFullCard
        } else {
            fullCard
        }
    }

    // MARK: - Wallet Full Card (name TL, balance TR, VISA above expiry BR)

    private var walletFullCard: some View {
        let g = themeGradient
        return ZStack {
            cardBackground(g)

            VStack(alignment: .leading, spacing: 0) {
                // Top: name left, balance right
                HStack(alignment: .top) {
                    Text(circleName)
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "$%.2f", balance))
                        .font(TallyFont.amountsSmall)
                        .foregroundStyle(.white)
                }

                Spacer()

                // NFC contactless icon
                Image(systemName: "wave.3.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                // Card number
                Text("•••• •••• •••• \(last4)")
                    .font(TallyFont.cardNumber)
                    .foregroundStyle(.white)
                    .tracking(1.5)

                Spacer().frame(height: 12)

                // Bottom: mntly left, VISA + expiry stacked right
                HStack(alignment: .bottom) {
                    Text("mntly")
                        .font(TallyFont.brandNav)
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        visaText(size: 14)
                        Text("VALID THRU  \(expiry)")
                            .font(TallyFont.decorativeBold)
                            .foregroundStyle(.white.opacity(0.55))
                            .tracking(0.4)
                    }
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: g.dark.opacity(0.45), radius: 24, y: 12)
    }

    // MARK: - Default Full Card (name + balance TL, VISA TR)

    private var fullCard: some View {
        let g = themeGradient
        return ZStack {
            cardBackground(g)

            VStack(alignment: .leading, spacing: 0) {
                // Top: name + balance left, VISA right
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(circleName)
                            .font(TallyFont.bodySemibold)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(String(format: "$%.2f", balance))
                            .font(TallyFont.amountsSmall)
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    visaText(size: 16)
                }

                Spacer()

                Image(systemName: "wave.3.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Spacer()

                Text("•••• •••• •••• \(last4)")
                    .font(TallyFont.cardNumber)
                    .foregroundStyle(.white)
                    .tracking(1.5)

                Spacer().frame(height: 12)

                HStack(alignment: .bottom) {
                    Text("mntly")
                        .font(TallyFont.brandNav)
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    Text("VALID THRU  \(expiry)")
                        .font(TallyFont.decorativeBold)
                        .foregroundStyle(.white.opacity(0.55))
                        .tracking(0.4)
                }
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: g.dark.opacity(0.45), radius: 24, y: 12)
    }

    // MARK: - Compact Card (Home horizontal scroll)

    private var compactCard: some View {
        let g = themeGradient
        return ZStack {
            cardBackground(g)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(circleName)
                        .font(TallyFont.smallSemibold)
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "$%.2f", balance))
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(.white)
                }

                Spacer()

                HStack(alignment: .bottom) {
                    HStack(spacing: 5) {
                        Image(systemName: "wave.3.right")
                            .font(TallyIcon.xxs)
                            .foregroundStyle(.white.opacity(0.65))
                        Text("•• \(last4)")
                            .font(TallyFont.cardNumberMini)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("mntly")
                            .font(TallyFont.buttonSmall)
                            .foregroundStyle(.white.opacity(0.75))
                        visaText(size: 10)
                    }
                }
            }
            .padding(TallySpacing.md)
        }
        .frame(width: 170, height: 110)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
        )
        .shadow(color: g.dark.opacity(0.3), radius: 8, y: 4)
    }

    // MARK: - Shared Background

    private func cardBackground(
        _ g: (dark: Color, mid: Color, light: Color)
    ) -> some View {
        ZStack {
            LinearGradient(
                colors: [g.dark, g.mid, g.light],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color.white.opacity(0.22), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 220
            )
            RadialGradient(
                colors: [Color.white.opacity(0.10), .clear],
                center: .bottomLeading,
                startRadius: 0,
                endRadius: 140
            )
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: Color.white.opacity(0.00), location: 0.35),
                    .init(color: Color.white.opacity(0.07), location: 0.50),
                    .init(color: Color.white.opacity(0.00), location: 0.65),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: UnitPoint(x: 0.0, y: 0.0),
                endPoint: UnitPoint(x: 1.0, y: 0.65)
            )
            .blendMode(.overlay)
        }
    }

    // MARK: - VISA Text

    private func visaText(size: CGFloat) -> some View {
        Text("VISA")
            .font(.system(size: size, weight: .black))
            .foregroundStyle(.white)
            .kerning(1.5)
    }
}

// MARK: - Preview

#Preview("Wallet Card") {
    TallyCard(
        circleName: "Ski Trip",
        last4: "4289",
        balance: 1234.56,
        colorIndex: 0,
        walletLayout: true
    )
    .frame(maxWidth: .infinity)
    .frame(height: 210)
    .padding(28)
    .background(Color(hex: 0xFCFCFD))
}

#Preview("Default Full Card") {
    TallyCard(
        circleName: "Housing Group",
        last4: "4289",
        balance: 1234.56,
        colorIndex: 1
    )
    .aspectRatio(1.586, contentMode: .fit)
    .padding(28)
    .background(Color(hex: 0xFCFCFD))
}

#Preview("Compact Card") {
    TallyCard(
        circleName: "Ski Trip",
        last4: "4289",
        balance: 87.50,
        colorIndex: 2,
        compact: true
    )
    .padding(28)
    .background(Color(hex: 0xFCFCFD))
}

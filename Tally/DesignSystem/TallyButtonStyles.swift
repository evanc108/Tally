import SwiftUI

// MARK: - Primary (mint green, 52px)

struct TallyPrimaryButtonStyle: ButtonStyle {
    var color: Color = TallyColors.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TallyFont.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: TallySpacing.buttonHeightPrimary)
            .background(configuration.isPressed ? TallyColors.accentDark : color)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.buttonCornerRadius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Dark (near-black) — for "Pay", "Send", "Confirm" actions

struct TallyDarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TallyFont.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: TallySpacing.buttonHeightPrimary)
            .background(TallyColors.ink)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.buttonCornerRadius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Secondary (bordered, 44px)

struct TallySecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TallyFont.button)
            .foregroundStyle(TallyColors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: TallySpacing.buttonHeightSecondary)
            .background(configuration.isPressed ? TallyColors.bgSecondary : TallyColors.white)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.buttonCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: TallySpacing.buttonCornerRadius)
                    .stroke(TallyColors.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Danger (red text on light red bg, 44px)

struct TallyDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TallyFont.button)
            .foregroundStyle(TallyColors.dangerText)
            .frame(maxWidth: .infinity)
            .frame(height: TallySpacing.buttonHeightSecondary)
            .background(configuration.isPressed ? TallyColors.dangerHoverBg : TallyColors.dangerBg)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.buttonCornerRadius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Ghost (text only, green accent)

struct TallyGhostButtonStyle: ButtonStyle {
    var color: Color = TallyColors.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TallyFont.button)
            .foregroundStyle(color)
            .frame(height: TallySpacing.buttonHeightSecondary)
            .background(configuration.isPressed ? TallyColors.accentLight : .clear)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.buttonCornerRadius))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Small Primary (36px)

struct TallySmallPrimaryButtonStyle: ButtonStyle {
    var color: Color = TallyColors.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TallyFont.buttonSmall)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: TallySpacing.buttonHeightSmall)
            .background(configuration.isPressed ? TallyColors.accentDark : color)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.buttonCornerRadius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Small Secondary (bordered, 36px)

struct TallySmallSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TallyFont.buttonSmall)
            .foregroundStyle(TallyColors.textPrimary)
            .padding(.horizontal, 17)
            .frame(height: TallySpacing.buttonHeightSmall)
            .background(TallyColors.white)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.buttonCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: TallySpacing.buttonCornerRadius)
                    .stroke(TallyColors.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

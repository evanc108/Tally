import SwiftUI

// MARK: - Primary Button (52px)

struct TallyPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: TallyRadius.md))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if !isEnabled { return Color(hex: 0xB8E6B9) }
        return isPressed ? TallyColors.accentDark : TallyColors.accent
    }
}

// MARK: - Secondary Button (44px)

struct TallySecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(TallyColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(configuration.isPressed ? TallyColors.bgPrimary : TallyColors.white)
            .clipShape(RoundedRectangle(cornerRadius: TallyRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: TallyRadius.md)
                    .stroke(
                        configuration.isPressed ? TallyColors.textHint : TallyColors.border,
                        lineWidth: 1
                    )
            )
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Danger Button (44px)

struct TallyDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(TallyColors.statusAlert)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(configuration.isPressed ? Color(hex: 0xFFE0DE) : TallyColors.statusAlertLight)
            .clipShape(RoundedRectangle(cornerRadius: TallyRadius.md))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Ghost Button (44px)

struct TallyGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(TallyColors.accent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(configuration.isPressed ? TallyColors.accentLight : .clear)
            .clipShape(RoundedRectangle(cornerRadius: TallyRadius.md))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Small Primary Button (36px)

struct TallySmallPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, TallySpacing.md)
            .frame(minHeight: 36)
            .background(configuration.isPressed ? TallyColors.accentDark : TallyColors.accent)
            .clipShape(RoundedRectangle(cornerRadius: TallyRadius.md))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Small Secondary Button (36px)

struct TallySmallSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(TallyColors.textPrimary)
            .padding(.horizontal, TallySpacing.md)
            .frame(minHeight: 36)
            .background(configuration.isPressed ? TallyColors.bgPrimary : TallyColors.white)
            .clipShape(RoundedRectangle(cornerRadius: TallyRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: TallyRadius.md)
                    .stroke(TallyColors.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Small Danger Button (36px)

struct TallySmallDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(TallyColors.statusAlert)
            .padding(.horizontal, TallySpacing.md)
            .frame(minHeight: 36)
            .background(configuration.isPressed ? Color(hex: 0xFFE0DE) : TallyColors.statusAlertLight)
            .clipShape(RoundedRectangle(cornerRadius: TallyRadius.md))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Small Ghost Button (36px)

struct TallySmallGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(TallyColors.accent)
            .padding(.horizontal, TallySpacing.md)
            .frame(minHeight: 36)
            .background(configuration.isPressed ? TallyColors.accentLight : .clear)
            .clipShape(RoundedRectangle(cornerRadius: TallyRadius.md))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

import SwiftUI

// MARK: - Primary (green)

struct TallyPrimaryButtonStyle: ButtonStyle {
    var color: Color = TallyColors.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: TallySpacing.buttonHeight)
            .background(color)
            .clipShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Dark (near-black) — for "Pay", "Send", "Confirm" actions

struct TallyDarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: TallySpacing.buttonHeight)
            .background(TallyColors.ink)
            .clipShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Secondary (outlined)

struct TallySecondaryButtonStyle: ButtonStyle {
    var color: Color = TallyColors.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: TallySpacing.buttonHeight)
            .background(
                Rectangle()
                    .stroke(color, lineWidth: 1.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Ghost (text only)

struct TallyGhostButtonStyle: ButtonStyle {
    var color: Color = TallyColors.textSecondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

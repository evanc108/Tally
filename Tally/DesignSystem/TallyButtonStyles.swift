import SwiftUI

struct TallyPrimaryButtonStyle: ButtonStyle {
    var color: Color = TallyColors.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: TallySpacing.buttonHeight)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.buttonCornerRadius))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct TallySecondaryButtonStyle: ButtonStyle {
    var color: Color = TallyColors.accent

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .frame(height: TallySpacing.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: TallySpacing.buttonCornerRadius)
                    .stroke(color, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

struct TallyGhostButtonStyle: ButtonStyle {
    var color: Color = TallyColors.textSecondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.6 : 1.0)
    }
}

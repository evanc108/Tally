import SwiftUI

// MARK: - Liquid Glass (iOS 26+)

extension View {
    /// Applies native Liquid Glass background in the given shape.
    func liquidGlass<S: Shape>(in shape: S) -> some View {
        self.glassEffect(.regular, in: shape)
    }

    /// Interactive Liquid Glass — press scaling, bounce, shimmer.
    func liquidGlassInteractive<S: Shape>(in shape: S) -> some View {
        self.glassEffect(.regular.interactive(), in: shape)
    }

    /// Shorthand: rounded-rect glass card.
    func glassCard(cornerRadius: CGFloat = TallySpacing.cardCornerRadius) -> some View {
        liquidGlass(in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Glass Nav Button

/// Reusable circular liquid-glass navigation button.
struct GlassNavButton: View {
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(TallyIcon.lg)
                .foregroundStyle(TallyColors.ink)
                .frame(width: 44, height: 44)
                .liquidGlass(in: Circle())
        }
    }
}

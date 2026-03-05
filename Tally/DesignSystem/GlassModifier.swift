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

import SwiftUI

/// Illustration for onboarding page 3: "Split & settle instantly"
/// Shows a central split amount connected to member avatars via dotted lines.
struct OnboardingSplitSettleView: View {
    var body: some View {
        ZStack {
            // Dotted connecting lines
            DottedLines()
                .stroke(
                    TallyColors.textSecondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                )
                .frame(width: 280, height: 240)

            // Center: split amount
            VStack(spacing: 2) {
                Text("SPLIT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .tracking(1)
                Text("$153")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 100, height: 100)
            .background(Circle().fill(TallyColors.accent))

            // Checkmark badge on center circle
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(TallyColors.accent)
                .background(Circle().fill(.white).frame(width: 18, height: 18))
                .offset(x: 42, y: -36)

            // Member S (top)
            memberBubble(initial: "S", color: .blue, amount: "$51.00", x: 0, y: -110)

            // Member A (bottom-left)
            memberBubble(initial: "A", color: .orange, amount: "$51.00", x: -100, y: 80)

            // Member M (bottom-right)
            memberBubble(initial: "M", color: .pink, amount: "$51.00", x: 100, y: 80)
        }
        .frame(height: 280)
    }

    private func memberBubble(initial: String, color: Color, amount: String, x: CGFloat, y: CGFloat) -> some View {
        VStack(spacing: 4) {
            AvatarCircleView(initial: initial, color: color, size: 40)
            Text(amount)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(TallyColors.textPrimary)
            Text("Paid")
                .font(.system(size: 10))
                .foregroundStyle(TallyColors.accent)
        }
        .offset(x: x, y: y)
    }
}

/// Custom shape drawing dotted lines from center to three radial positions.
private struct DottedLines: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let top = CGPoint(x: rect.midX, y: rect.midY - 90)
        let bottomLeft = CGPoint(x: rect.midX - 85, y: rect.midY + 65)
        let bottomRight = CGPoint(x: rect.midX + 85, y: rect.midY + 65)

        var path = Path()
        path.move(to: center)
        path.addLine(to: top)
        path.move(to: center)
        path.addLine(to: bottomLeft)
        path.move(to: center)
        path.addLine(to: bottomRight)
        return path
    }
}

#Preview {
    OnboardingSplitSettleView()
}

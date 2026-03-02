import SwiftUI

struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.25, y: rect.height * 0.52))
        path.addLine(to: CGPoint(x: rect.width * 0.43, y: rect.height * 0.70))
        path.addLine(to: CGPoint(x: rect.width * 0.75, y: rect.height * 0.32))
        return path
    }
}

struct AnimatedCheckmarkView: View {
    @State private var trimEnd: CGFloat = 0
    @State private var circleScale: CGFloat = 0.5
    @State private var circleOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(TallyColors.accent.opacity(0.12))
                .scaleEffect(circleScale)
                .opacity(circleOpacity)

            Circle()
                .stroke(TallyColors.accent, lineWidth: 3)
                .scaleEffect(circleScale)
                .opacity(circleOpacity)

            CheckmarkShape()
                .trim(from: 0, to: trimEnd)
                .stroke(
                    TallyColors.accent,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
                .padding(28)
        }
        .frame(width: 100, height: 100)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
                circleScale = 1.0
                circleOpacity = 1.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
                trimEnd = 1.0
            }
        }
    }
}

#Preview {
    AnimatedCheckmarkView()
}

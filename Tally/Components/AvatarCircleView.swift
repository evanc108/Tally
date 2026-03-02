import SwiftUI

struct AvatarCircleView: View {
    let initial: String
    let color: Color
    var size: CGFloat = 44

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.15))
            .clipShape(Circle())
            .overlay(Circle().stroke(color.opacity(0.3), lineWidth: 1))
    }
}

#Preview {
    HStack(spacing: 12) {
        AvatarCircleView(initial: "A", color: .blue)
        AvatarCircleView(initial: "S", color: .orange)
        AvatarCircleView(initial: "M", color: .pink)
    }
}

import SwiftUI

/// Illustration for onboarding page 1: "Create your group"
/// Shows a main user avatar with two member avatars and a "+" add button.
struct OnboardingCreateGroupView: View {
    var body: some View {
        ZStack {
            // Main user avatar (center)
            Circle()
                .fill(TallyColors.accent.opacity(0.12))
                .frame(width: 160, height: 160)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundStyle(TallyColors.accent)
                )

            // Member A (bottom-left)
            AvatarCircleView(initial: "A", color: .blue, size: 52)
                .offset(x: -70, y: 60)

            // Member M (right)
            AvatarCircleView(initial: "M", color: .orange, size: 52)
                .offset(x: 80, y: 20)

            // Add button (bottom-center-left)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(TallyColors.accent)
                .background(Circle().fill(Color.white).frame(width: 26, height: 26))
                .offset(x: -20, y: 90)
        }
        .frame(height: 240)
    }
}

#Preview {
    OnboardingCreateGroupView()
}

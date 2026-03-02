import SwiftUI

struct CircleReadyView: View {
    let state: CreateCircleState
    let onFinish: () -> Void

    @State private var photoScale: CGFloat = 0
    @State private var nameOpacity: CGFloat = 0
    @State private var avatarsOpacity: CGFloat = 0
    @State private var readyOpacity: CGFloat = 0
    @State private var buttonOpacity: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Circle photo or placeholder
                Group {
                    if let photo = state.photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 88, height: 88)
                            .clipShape(Circle())
                    } else {
                        Text(String(state.circleName.prefix(1)).uppercased())
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 88, height: 88)
                            .background(
                                LinearGradient(
                                    colors: [TallyColors.accent, TallyColors.accent.opacity(0.7)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(Circle())
                    }
                }
                .scaleEffect(photoScale)

                // Circle name
                Text(state.circleName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(TallyColors.textPrimary)
                    .opacity(nameOpacity)
                    .padding(.top, TallySpacing.lg)

                // Member avatars
                HStack(spacing: TallySpacing.sm) {
                    avatarBubble(initial: "Y", color: TallyColors.accent)
                    ForEach(state.members) { member in
                        avatarBubble(initial: member.initial, color: member.color)
                    }
                }
                .opacity(avatarsOpacity)
                .padding(.top, TallySpacing.xl)

                // Ready text
                Text("Your circle is ready.")
                    .font(.system(size: 17))
                    .foregroundStyle(TallyColors.textSecondary)
                    .opacity(readyOpacity)
                    .padding(.top, TallySpacing.xl)
            }

            Spacer()

            Button("Go to Circle", action: onFinish)
                .buttonStyle(TallyPrimaryButtonStyle())
                .opacity(buttonOpacity)
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
        .navigationBarBackButtonHidden()
        .onAppear { runAnimations() }
    }

    private func avatarBubble(initial: String, color: Color) -> some View {
        Text(initial)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(
                LinearGradient(
                    colors: [TallyColors.accent, TallyColors.statusSocial],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(Circle())
    }

    private func runAnimations() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
            photoScale = 1.0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
            nameOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
            avatarsOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.7)) {
            readyOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.9)) {
            buttonOpacity = 1.0
        }
    }
}

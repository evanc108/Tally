import SwiftUI

struct CircleReadyView: View {
    let state: CreateCircleState
    let viewModel: CirclesViewModel
    let onFinish: (TallyCircle) -> Void

    @State private var photoScale: CGFloat = 0
    @State private var nameOpacity: CGFloat = 0
    @State private var avatarsOpacity: CGFloat = 0
    @State private var readyOpacity: CGFloat = 0
    @State private var buttonOpacity: CGFloat = 0
    @State private var isCreating = false
    @State private var errorMessage: String?

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
                            .frame(width: 96, height: 96)
                            .clipShape(Circle())
                    } else {
                        Text(String(state.circleName.prefix(1)).uppercased())
                            .font(.system(size: 36, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 96, height: 96)
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

                Text(state.circleName)
                    .font(TallyFont.title)
                    .foregroundStyle(TallyColors.textPrimary)
                    .opacity(nameOpacity)
                    .padding(.top, TallySpacing.lg)

                // Member avatars using card palette
                HStack(spacing: TallySpacing.sm) {
                    avatarBubble(initial: "Y", index: 0)
                    ForEach(Array(state.members.enumerated()), id: \.element.id) { index, member in
                        avatarBubble(initial: member.initial, index: index + 1)
                    }
                }
                .opacity(avatarsOpacity)
                .padding(.top, TallySpacing.xl)

                Text("Your circle is ready.")
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textSecondary)
                    .opacity(readyOpacity)
                    .padding(.top, TallySpacing.lg)

                if let errorMessage {
                    Text(errorMessage)
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.statusAlert)
                        .multilineTextAlignment(.center)
                        .padding(.top, TallySpacing.md)
                        .padding(.horizontal, TallySpacing.screenPadding)
                }
            }

            Spacer()

            Button(isCreating ? "Creating..." : "Go to Circle") {
                handleCreate()
            }
            .buttonStyle(TallyPrimaryButtonStyle())
            .disabled(isCreating)
            .opacity(buttonOpacity)
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
        .navigationBarBackButtonHidden()
        .onAppear { runAnimations() }
    }

    private func avatarBubble(initial: String, index: Int) -> some View {
        Text(initial)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(TallyColors.ink)
            .frame(width: 44, height: 44)
            .background(TallyColors.cardColor(for: index))
            .clipShape(Circle())
    }

    private func runAnimations() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) { photoScale = 1.0 }
        withAnimation(.easeOut(duration: 0.4).delay(0.3)) { nameOpacity = 1.0 }
        withAnimation(.easeOut(duration: 0.4).delay(0.5)) { avatarsOpacity = 1.0 }
        withAnimation(.easeOut(duration: 0.4).delay(0.7)) { readyOpacity = 1.0 }
        withAnimation(.easeOut(duration: 0.3).delay(0.9)) { buttonOpacity = 1.0 }
    }

    private func handleCreate() {
        guard !isCreating else { return }
        isCreating = true
        errorMessage = nil
        Task(name: "create-circle") {
            do {
                let circle = try await viewModel.createCircle(state: state)
                onFinish(circle)
            } catch let e as TallyError {
                errorMessage = e.errorDescription
                isCreating = false
            } catch {
                errorMessage = error.localizedDescription
                isCreating = false
            }
        }
    }
}

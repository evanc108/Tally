import SwiftUI

struct SelfieVerificationView: View {
    let onCapture: () -> Void
    let onBack: () -> Void

    @State private var isCapturing = false
    @State private var ringProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            VerificationNavBar(title: nil, onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: TallySpacing.xxl)

                    Text("Take a selfie")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)

                    Text("Position your face in the circle. We'll match it to\nyour ID photo.")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, TallySpacing.sm)

                    Spacer().frame(height: TallySpacing.xxxxl)

                    // Selfie frame
                    ZStack {
                        // Outer ring
                        Circle()
                            .stroke(TallyColors.border, lineWidth: 3)
                            .frame(width: 200, height: 200)

                        // Progress ring
                        if isCapturing {
                            Circle()
                                .trim(from: 0, to: ringProgress)
                                .stroke(TallyColors.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 200, height: 200)
                                .rotationEffect(.degrees(-90))
                        }

                        // Placeholder face
                        VStack(spacing: TallySpacing.sm) {
                            Image(systemName: "person.crop.circle")
                                .font(TallyIcon.full)
                                .foregroundStyle(TallyColors.textPlaceholder)
                            Text("Look straight ahead")
                                .font(TallyFont.small)
                                .foregroundStyle(TallyColors.textTertiary)
                        }
                    }

                    Spacer().frame(height: TallySpacing.xxxxl)

                    // Capture button
                    Button {
                        simulateCapture()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(TallyColors.accent, lineWidth: 4)
                                .frame(width: 72, height: 72)
                            Circle()
                                .fill(TallyColors.accent)
                                .frame(width: 56, height: 56)
                            Image(systemName: "camera.fill")
                                .font(TallyIcon.xxl)
                                .foregroundStyle(.white)
                        }
                    }
                    .disabled(isCapturing)

                    Spacer().frame(height: TallySpacing.xxl)

                    // Tips
                    HStack(spacing: TallySpacing.sm) {
                        Image(systemName: "info.circle")
                            .font(TallyIcon.sm)
                            .foregroundStyle(TallyColors.textTertiary)
                        Text("Remove glasses, hats, or masks. Use good\nlighting and a plain background.")
                            .font(TallyFont.small)
                            .foregroundStyle(TallyColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, TallySpacing.screenPadding)
                }
            }
        }
        .background(TallyColors.white)
    }

    private func simulateCapture() {
        isCapturing = true
        ringProgress = 0

        withAnimation(.linear(duration: 1.2)) {
            ringProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            isCapturing = false
            onCapture()
        }
    }
}

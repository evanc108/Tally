import SwiftUI

struct VerificationProcessingView: View {
    let onComplete: (Bool) -> Void

    @State private var steps: [ProcessingStep] = [
        ProcessingStep(label: "Document uploaded", delay: 0.8),
        ProcessingStep(label: "Selfie uploaded", delay: 1.8),
        ProcessingStep(label: "Matching identity...", delay: 3.0),
        ProcessingStep(label: "Finalizing review", delay: 4.2),
    ]

    @State private var currentStepIndex = 0
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Spinner icon
            ZStack {
                Circle()
                    .stroke(TallyColors.border, lineWidth: 3)
                    .frame(width: 80, height: 80)

                if currentStepIndex < steps.count {
                    Circle()
                        .trim(from: 0, to: 0.7)
                        .stroke(TallyColors.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 80, height: 80)
                        .rotationEffect(.degrees(appeared ? 360 : 0))
                        .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: appeared)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(TallyColors.accent)
                }
            }

            Spacer().frame(height: TallySpacing.xxl)

            Text("Verifying your identity")
                .font(TallyFont.largeTitle)
                .foregroundStyle(TallyColors.textPrimary)

            Text("Stripe is securely processing your documents.\nThis usually takes less than a minute.")
                .font(TallyFont.body)
                .foregroundStyle(TallyColors.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, TallySpacing.sm)

            Spacer().frame(height: TallySpacing.xxxxl)

            // Steps checklist
            VStack(alignment: .leading, spacing: TallySpacing.lg) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(spacing: TallySpacing.md) {
                        ZStack {
                            if index < currentStepIndex {
                                // Completed
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 22))
                                    .foregroundStyle(TallyColors.accent)
                                    .transition(.scale.combined(with: .opacity))
                            } else if index == currentStepIndex {
                                // In progress
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(TallyColors.accent)
                            } else {
                                // Pending
                                Circle()
                                    .stroke(TallyColors.border, lineWidth: 1.5)
                                    .frame(width: 22, height: 22)
                            }
                        }
                        .frame(width: 22, height: 22)

                        Text(step.label)
                            .font(TallyFont.bodySemibold)
                            .foregroundStyle(
                                index <= currentStepIndex
                                    ? TallyColors.textPrimary
                                    : TallyColors.textTertiary
                            )
                    }
                }
            }
            .padding(.horizontal, TallySpacing.screenPadding)

            Spacer()

            PoweredByStripe()
                .padding(.bottom, TallySpacing.xxl)
        }
        .background(TallyColors.white)
        .onAppear {
            appeared = true
            runProcessingAnimation()
        }
    }

    private func runProcessingAnimation() {
        for (index, step) in steps.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) {
                withAnimation(.spring(duration: 0.4)) {
                    currentStepIndex = index + 1
                }
            }
        }

        // Complete after all steps
        let totalDelay = (steps.last?.delay ?? 4.0) + 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay) {
            onComplete(true)
        }
    }
}

private struct ProcessingStep {
    let label: String
    let delay: TimeInterval
}

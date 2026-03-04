import SwiftUI

struct PayCompleteView: View {
    @Bindable var viewModel: PayFlowViewModel
    var onDone: () -> Void

    @State private var checkScale: CGFloat = 0
    @State private var titleOpacity: CGFloat = 0
    @State private var amountOpacity: CGFloat = 0
    @State private var splitsOpacity: CGFloat = 0
    @State private var buttonOpacity: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // ── Checkmark circle ────────────────────────────────────
                ZStack {
                    Circle()
                        .fill(TallyColors.accent)
                        .frame(width: 80, height: 80)

                    Image(systemName: "checkmark")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(checkScale)

                // ── Title ───────────────────────────────────────────────
                Text("Payment Complete")
                    .font(TallyFont.title)
                    .foregroundStyle(TallyColors.textPrimary)
                    .opacity(titleOpacity)
                    .padding(.top, TallySpacing.xl)

                // ── Total amount ────────────────────────────────────────
                Text(CentsFormatter.format(viewModel.totalCents))
                    .font(TallyFont.display)
                    .foregroundStyle(TallyColors.statusSuccess)
                    .opacity(amountOpacity)
                    .padding(.top, TallySpacing.lg)

                // ── Per-member summary ──────────────────────────────────
                VStack(spacing: TallySpacing.sm) {
                    ForEach(viewModel.splits) { split in
                        HStack {
                            Text(split.memberName)
                                .font(TallyFont.body)
                                .foregroundStyle(TallyColors.textSecondary)

                            Spacer()

                            Text(CentsFormatter.format(split.amountCents + split.tipCents))
                                .font(TallyFont.amounts)
                                .foregroundStyle(TallyColors.textPrimary)
                        }
                    }
                }
                .opacity(splitsOpacity)
                .padding(.top, TallySpacing.xxl)
                .padding(.horizontal, TallySpacing.screenPadding)
            }
            .padding(.horizontal, TallySpacing.screenPadding)

            Spacer()

            // ── Done button ─────────────────────────────────────────────
            Button("Done", action: onDone)
                .buttonStyle(TallyPrimaryButtonStyle())
                .opacity(buttonOpacity)
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
        .navigationBarBackButtonHidden()
        .onAppear { runAnimations() }
    }

    // MARK: - Staggered Animations

    private func runAnimations() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
            checkScale = 1.0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
            titleOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.5)) {
            amountOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.4).delay(0.7)) {
            splitsOpacity = 1.0
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.9)) {
            buttonOpacity = 1.0
        }
    }
}

// MARK: - Preview

#Preview {
    PayCompleteView(
        viewModel: {
            let vm = PayFlowViewModel()
            vm.merchantName = "Sushi Ro"
            vm.receipt = PayReceipt.sample
            vm.splits = PaySplit.samples
            return vm
        }(),
        onDone: {}
    )
}

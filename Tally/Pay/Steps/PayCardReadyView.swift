import SwiftUI

struct PayCardReadyView: View {
    @Bindable var viewModel: PayFlowViewModel

    @State private var pulse = false

    private var circleName: String {
        viewModel.selectedCircle?.name ?? "Circle"
    }

    private var declineReason: String? {
        guard let result = viewModel.tapResult, result.decision != "APPROVE" else { return nil }
        return result.reason ?? "Transaction declined."
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // ── Card visual ─────────────────────────────────────────────
            VStack(spacing: TallySpacing.xl) {
                ZStack {
                    RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                        .fill(
                            LinearGradient(
                                colors: [TallyColors.ink, TallyColors.ink.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .aspectRatio(1.586, contentMode: .fit)
                        .shadow(
                            color: TallyColors.ink.opacity(pulse ? 0.4 : 0.15),
                            radius: pulse ? 30 : 20
                        )

                    VStack(alignment: .leading) {
                        HStack {
                            // Circle initial
                            Text(String(circleName.prefix(1)).uppercased())
                                .font(TallyFont.avatarSmall)
                                .foregroundStyle(.white)
                                .frame(width: 34, height: 34)
                                .background(.white.opacity(0.15))
                                .clipShape(Circle())

                            Spacer()

                            // READY badge
                            Text("READY")
                                .font(TallyFont.smallLabel)
                                .fontWeight(.bold)
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, TallySpacing.sm)
                                .padding(.vertical, TallySpacing.xs)
                                .background(.white.opacity(0.2))
                                .clipShape(Capsule())
                        }

                        Spacer()

                        // Total amount
                        Text(CentsFormatter.format(viewModel.totalCents))
                            .font(TallyFont.amountsXL)
                            .foregroundStyle(.white)

                        Spacer().frame(height: TallySpacing.md)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(circleName.uppercased())
                                    .font(TallyFont.smallLabel)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.white.opacity(0.7))
                                Text("Armed")
                                    .font(TallyFont.smallLabel)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                            Text("mntly")
                                .font(TallyFont.brandCard)
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(20)
                }
                .padding(.horizontal, TallySpacing.screenPadding)

                Text("Ready to pay")
                    .font(TallyFont.title)
                    .foregroundStyle(TallyColors.textPrimary)

                Text("Hold your phone near the terminal")
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textSecondary)
            }

            Spacer()

            // ── Decline reason ──────────────────────────────────────────
            if let reason = declineReason {
                Text(reason)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.statusAlert)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.bottom, TallySpacing.lg)
            }

            // ── Buttons ─────────────────────────────────────────────────
            VStack(spacing: TallySpacing.md) {
                Button {
                    Task {
                        await viewModel.simulateTap()
                    }
                } label: {
                    if viewModel.isLoading {
                        HStack(spacing: TallySpacing.sm) {
                            ProgressView().tint(.white)
                            Text("Processing...")
                        }
                    } else {
                        Text("Simulate Tap")
                    }
                }
                .buttonStyle(TallyDarkButtonStyle())
                .disabled(viewModel.isLoading)

                Button("Cancel") {
                    viewModel.reset()
                }
                .buttonStyle(TallyGhostButtonStyle())
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Preview

#Preview {
    PayCardReadyView(viewModel: {
        let vm = PayFlowViewModel()
        vm.merchantName = "Sushi Ro"
        vm.selectedCircle = TallyCircle.sample
        vm.receipt = PayReceipt.sample
        vm.splits = PaySplit.samples
        return vm
    }())
}

#Preview("Declined") {
    PayCardReadyView(viewModel: {
        let vm = PayFlowViewModel()
        vm.merchantName = "Sushi Ro"
        vm.selectedCircle = TallyCircle.sample
        vm.receipt = PayReceipt.sample
        vm.splits = PaySplit.samples
        vm.tapResult = SimulateTapResponseDTO(
            decision: "DECLINE",
            transactionId: nil,
            reason: "Insufficient funds in wallet."
        )
        return vm
    }())
}

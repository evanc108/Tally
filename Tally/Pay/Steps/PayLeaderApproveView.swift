import SwiftUI

struct PayLeaderApproveView: View {
    @Bindable var viewModel: PayFlowViewModel

    @State private var pulse = false
    @State private var isArmed = false

    private var circleName: String {
        viewModel.selectedCircle?.name ?? "Circle"
    }

    private var declineReason: String? {
        guard let result = viewModel.tapResult, result.decision != "APPROVE" else { return nil }
        return result.reason ?? "Transaction declined."
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Scrollable content ──────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Card visual ───────────────────────────────────────
                    cardVisual
                        .padding(.top, TallySpacing.sm)

                    // ── Section header ─────────────────────────────────────
                    Text("Split breakdown")
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                        .textCase(.uppercase)
                        .padding(.top, TallySpacing.xxl)
                        .padding(.bottom, TallySpacing.md)

                    // ── Per-member breakdown ───────────────────────────────
                    LazyVStack(spacing: 0) {
                        ForEach(Array(viewModel.splits.enumerated()), id: \.element.id) { index, split in
                            splitRow(split: split, index: index)

                            if index < viewModel.splits.count - 1 {
                                Rectangle()
                                    .fill(TallyColors.divider)
                                    .frame(height: 0.5)
                                    .padding(.leading, 36 + TallySpacing.lg)
                            }
                        }
                    }

                    // ── Tip summary ───────────────────────────────────────
                    if viewModel.receiptTipCents + viewModel.tipTotalCents > 0 {
                        HStack {
                            Text("Includes tip")
                                .font(TallyFont.body)
                                .foregroundStyle(TallyColors.textSecondary)
                            Spacer()
                            Text(CentsFormatter.format(viewModel.receiptTipCents + viewModel.tipTotalCents))
                                .font(TallyFont.amounts)
                                .foregroundStyle(TallyColors.textPrimary)
                        }
                        .padding(.top, TallySpacing.lg)
                    }

                    // ── Decline reason ─────────────────────────────────────
                    if let reason = declineReason {
                        Text(reason)
                            .font(TallyFont.bodySemibold)
                            .foregroundStyle(TallyColors.statusAlert)
                            .padding(.top, TallySpacing.lg)
                    }

                    // ── Error message ──────────────────────────────────────
                    if let error = viewModel.error {
                        Text(error.errorDescription ?? "Something went wrong.")
                            .font(TallyFont.caption)
                            .foregroundStyle(TallyColors.statusAlert)
                            .padding(.top, TallySpacing.lg)
                    }
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.lg)
            }

            // ── Pinned bottom buttons ─────────────────────────────────────
            VStack(spacing: TallySpacing.md) {
                Button {
                    Task { await handleAction() }
                } label: {
                    if viewModel.isLoading {
                        HStack(spacing: TallySpacing.sm) {
                            ProgressView().tint(.white)
                            Text(isArmed ? "Processing..." : "Approving...")
                        }
                    } else if isArmed {
                        Text("Simulate Tap")
                    } else {
                        Text("Approve & arm card")
                    }
                }
                .buttonStyle(TallyDarkButtonStyle())
                .disabled(viewModel.isLoading)

                if isArmed {
                    Button("Cancel") {
                        viewModel.reset()
                    }
                    .buttonStyle(TallyGhostButtonStyle())
                }
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

    // MARK: - Action

    private func handleAction() async {
        if isArmed {
            await viewModel.simulateTap()
        } else {
            viewModel.error = nil
            await viewModel.saveReceipt()
            await viewModel.createSession()
            guard viewModel.error == nil else { return }
            await viewModel.submitSplits()
            guard viewModel.error == nil else { return }
            await viewModel.approveSession()
            guard viewModel.error == nil else { return }
            withAnimation(.spring(response: 0.4)) {
                isArmed = true
            }
        }
    }

    // MARK: - Card Visual

    private var cardVisual: some View {
        VStack(spacing: TallySpacing.lg) {
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
                        color: TallyColors.ink.opacity(isArmed ? (pulse ? 0.4 : 0.15) : 0.08),
                        radius: isArmed ? (pulse ? 30 : 20) : 12
                    )

                VStack(alignment: .leading) {
                    HStack {
                        Text(String(circleName.prefix(1)).uppercased())
                            .font(TallyFont.avatarSmall)
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.15))
                            .clipShape(Circle())

                        Spacer()

                        if isArmed {
                            Text("READY")
                                .font(TallyFont.smallLabel)
                                .fontWeight(.bold)
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, TallySpacing.sm)
                                .padding(.vertical, TallySpacing.xs)
                                .background(.white.opacity(0.2))
                                .clipShape(Capsule())
                        }
                    }

                    Spacer()

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
                            Text(isArmed ? "Armed" : viewModel.merchantName)
                                .font(TallyFont.smallLabel)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        Spacer()
                        Text("tally")
                            .font(TallyFont.brandCard)
                            .foregroundStyle(.white)
                    }
                }
                .padding(20)
            }

            if isArmed {
                Text("Hold your phone near the terminal")
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textSecondary)
            }
        }
    }

    // MARK: - Split Row

    private func splitRow(split: PaySplit, index: Int) -> some View {
        HStack(spacing: TallySpacing.lg) {
            Text(String(split.memberName.prefix(1)).uppercased())
                .font(TallyFont.bodySemibold)
                .foregroundStyle(TallyColors.ink)
                .frame(width: 36, height: 36)
                .background(TallyColors.cardColor(for: index))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(split.memberName)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                    .lineLimit(1)

                Text(split.fundingSource.label)
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
            }

            Spacer()

            Text(CentsFormatter.format(split.amountCents + split.tipCents))
                .font(TallyFont.amounts)
                .foregroundStyle(TallyColors.textPrimary)
        }
        .frame(minHeight: TallySpacing.listItemMinHeight)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PayLeaderApproveView(viewModel: {
            let vm = PayFlowViewModel()
            vm.merchantName = "Sushi Ro"
            vm.selectedCircle = TallyCircle.sample
            vm.receipt = PayReceipt.sample
            vm.splits = PaySplit.samples
            return vm
        }())
    }
}

#Preview("Declined") {
    NavigationStack {
        PayLeaderApproveView(viewModel: {
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
}

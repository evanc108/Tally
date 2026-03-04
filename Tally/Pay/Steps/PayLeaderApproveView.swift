import SwiftUI

struct PayLeaderApproveView: View {
    @Bindable var viewModel: PayFlowViewModel

    var body: some View {
        VStack(spacing: 0) {
            // ── Scrollable content ──────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Merchant name ───────────────────────────────────────
                    Text(viewModel.merchantName)
                        .font(TallyFont.title)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.sm)

                    // ── Total amount (centered) ─────────────────────────────
                    VStack(spacing: TallySpacing.xs) {
                        Text(CentsFormatter.format(viewModel.totalCents))
                            .font(TallyFont.heroAmount)
                            .foregroundStyle(TallyColors.textPrimary)

                        Text(viewModel.receipt?.currency ?? "USD")
                            .font(TallyFont.caption)
                            .foregroundStyle(TallyColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, TallySpacing.xxl)
                    .padding(.bottom, TallySpacing.xxl)

                    // ── Section header ──────────────────────────────────────
                    Text("Split breakdown")
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                        .textCase(.uppercase)
                        .padding(.bottom, TallySpacing.md)

                    // ── Per-member breakdown ────────────────────────────────
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

                    // ── Error message ───────────────────────────────────────
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

            // ── Pinned bottom button ────────────────────────────────────────
            Button {
                Task {
                    viewModel.error = nil
                    await viewModel.createSession()
                    guard viewModel.error == nil else { return }
                    await viewModel.submitSplits()
                    guard viewModel.error == nil else { return }
                    await viewModel.approveSession()
                    guard viewModel.error == nil else { return }
                    viewModel.push(.cardReady)
                }
            } label: {
                if viewModel.isLoading {
                    HStack(spacing: TallySpacing.sm) {
                        ProgressView().tint(.white)
                        Text("Approving...")
                    }
                } else {
                    Text("Approve & arm card")
                }
            }
            .buttonStyle(TallyDarkButtonStyle())
            .disabled(viewModel.isLoading)
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
    }

    // MARK: - Split Row

    private func splitRow(split: PaySplit, index: Int) -> some View {
        HStack(spacing: TallySpacing.lg) {
            // Avatar circle
            Text(String(split.memberName.prefix(1)).uppercased())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(TallyColors.ink)
                .frame(width: 36, height: 36)
                .background(TallyColors.cardColor(for: index))
                .clipShape(Circle())

            // Name + funding source
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

            // Amount
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
            vm.receipt = PayReceipt.sample
            vm.splits = PaySplit.samples
            return vm
        }())
    }
}

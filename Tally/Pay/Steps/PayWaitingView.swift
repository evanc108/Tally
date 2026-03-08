import SwiftUI

struct PayWaitingView: View {
    @Bindable var viewModel: PayFlowViewModel

    private var allConfirmed: Bool {
        !viewModel.splits.isEmpty && viewModel.splits.allSatisfy(\.confirmed)
    }

    private var sessionReady: Bool {
        viewModel.session?.status == .ready
    }

    private var showContinue: Bool {
        allConfirmed || sessionReady
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // ── Header ──────────────────────────────────────────────
                if showContinue {
                    Image(systemName: "checkmark.circle.fill")
                        .font(TallyIcon.splash)
                        .foregroundStyle(TallyColors.ink)
                        .padding(.bottom, TallySpacing.lg)

                    Text("All confirmed!")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                } else {
                    Text("Waiting for everyone")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)

                    ProgressView()
                        .tint(TallyColors.ink)
                        .padding(.top, TallySpacing.lg)
                }

                // ── Member list ─────────────────────────────────────────
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.splits.enumerated()), id: \.element.id) { index, split in
                        memberRow(split: split, index: index)

                        if index < viewModel.splits.count - 1 {
                            Rectangle()
                                .fill(TallyColors.divider)
                                .frame(height: 0.5)
                                .padding(.leading, 32 + TallySpacing.lg) // align with text
                        }
                    }
                }
                .padding(.top, TallySpacing.xxl)
            }
            .padding(.horizontal, TallySpacing.screenPadding)

            Spacer()

            // ── Bottom button (only when all confirmed) ─────────────────
            if showContinue {
                Button("Continue") {
                    viewModel.applyTipToSplits()
                    viewModel.push(.leaderApprove)
                }
                .buttonStyle(TallyDarkButtonStyle())
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.xxxl)
            }
        }
        .background(TallyColors.bgPrimary)
    }

    // MARK: - Member Row

    private func memberRow(split: PaySplit, index: Int) -> some View {
        HStack(spacing: TallySpacing.lg) {
            // Avatar circle
            Text(String(split.memberName.prefix(1)).uppercased())
                .font(TallyFont.smallSemibold)
                .foregroundStyle(TallyColors.ink)
                .frame(width: 32, height: 32)
                .background(TallyColors.cardColor(for: index))
                .clipShape(Circle())

            // Name
            Text(split.memberName)
                .font(TallyFont.bodySemibold)
                .foregroundStyle(TallyColors.textPrimary)
                .lineLimit(1)

            Spacer()

            // Status icon
            if split.confirmed {
                Image(systemName: "checkmark.circle.fill")
                    .font(TallyIcon.xl)
                    .foregroundStyle(TallyColors.ink)
            } else {
                Image(systemName: "clock")
                    .font(TallyIcon.xl)
                    .foregroundStyle(TallyColors.textTertiary)
            }
        }
        .frame(minHeight: TallySpacing.listItemMinHeight)
    }
}

// MARK: - Preview

#Preview("Waiting") {
    PayWaitingView(viewModel: {
        let vm = PayFlowViewModel()
        vm.splits = [
            PaySplit(memberId: "m1", memberName: "Sarah Kim", amountCents: 2880, confirmed: true),
            PaySplit(memberId: "m2", memberName: "Alex Chen", amountCents: 2880, confirmed: false),
            PaySplit(memberId: "m3", memberName: "You", amountCents: 2880, confirmed: true),
        ]
        return vm
    }())
}

#Preview("All Confirmed") {
    PayWaitingView(viewModel: {
        let vm = PayFlowViewModel()
        vm.splits = [
            PaySplit(memberId: "m1", memberName: "Sarah Kim", amountCents: 2880, confirmed: true),
            PaySplit(memberId: "m2", memberName: "Alex Chen", amountCents: 2880, confirmed: true),
            PaySplit(memberId: "m3", memberName: "You", amountCents: 2880, confirmed: true),
        ]
        return vm
    }())
}

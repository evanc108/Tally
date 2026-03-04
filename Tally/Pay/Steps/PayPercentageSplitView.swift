import SwiftUI

struct PayPercentageSplitView: View {
    @Bindable var viewModel: PayFlowViewModel

    private var isValid: Bool {
        let total = viewModel.serverMembers.reduce(0.0) {
            $0 + (viewModel.memberPercentages[$1.memberID] ?? 0)
        }
        return abs(total - 100.0) < 0.01
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Scrollable content ──────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Set percentages")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.sm)

                    // Total display (pre-tip — tip is configured on the next screen)
                    Text(CentsFormatter.format(viewModel.preTipCents))
                        .font(TallyFont.amounts)
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(.top, TallySpacing.sm)

                    // Member percentage sliders (same component as circle creation)
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.serverMembers.enumerated()), id: \.element.memberID) { index, member in
                            PercentageRow(
                                name: member.displayName.components(separatedBy: " ").first ?? member.displayName,
                                color: TallyColors.cardColor(for: index),
                                percentage: viewModel.memberPercentages[member.memberID] ?? 0
                            ) { newValue in
                                viewModel.updateMemberPercentage(memberId: member.memberID, to: newValue)
                            }
                            .overlay(alignment: .bottom) {
                                if index < viewModel.serverMembers.count - 1 {
                                    Rectangle().fill(TallyColors.divider).frame(height: 0.5)
                                }
                            }
                        }
                    }
                    .background(TallyColors.bgPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
                    .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 3)
                    .padding(.top, TallySpacing.xl)

                    // Per-member amount preview
                    amountPreview
                        .padding(.top, TallySpacing.xl)
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.lg)
            }

            // ── Pinned bottom button ────────────────────────────────────────
            Button("Continue") {
                handleContinue()
            }
            .buttonStyle(TallyPrimaryButtonStyle())
            .disabled(!isValid)
            .opacity(isValid ? 1.0 : 0.5)
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
        .onAppear {
            if viewModel.memberPercentages.isEmpty {
                viewModel.initializeEqualPercentages()
            }
        }
    }

    // MARK: - Amount Preview

    private var amountPreview: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.serverMembers.enumerated()), id: \.element.memberID) { index, member in
                let pct = viewModel.memberPercentages[member.memberID] ?? 0
                let cents = Int64((Double(viewModel.preTipCents) * pct / 100.0).rounded())

                HStack(spacing: TallySpacing.md) {
                    Text(String(member.displayName.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(TallyColors.cardColor(for: index))
                        .clipShape(Circle())

                    Text(member.displayName)
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textPrimary)

                    Spacer()

                    Text(CentsFormatter.format(cents))
                        .font(TallyFont.amounts)
                        .foregroundStyle(TallyColors.textPrimary)
                }
                .padding(.vertical, TallySpacing.xs)

                if index < viewModel.serverMembers.count - 1 {
                    Rectangle()
                        .fill(TallyColors.divider)
                        .frame(height: 0.5)
                }
            }
        }
    }

    // MARK: - Continue

    private func handleContinue() {
        viewModel.computePercentageSplits()
        viewModel.applyTipToSplits()
        viewModel.push(.leaderApprove)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PayPercentageSplitView(viewModel: {
            let vm = PayFlowViewModel()
            vm.manualAmountCents = 8640
            return vm
        }())
    }
}

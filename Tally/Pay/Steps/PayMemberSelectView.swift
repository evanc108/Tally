import SwiftUI

struct PayMemberSelectView: View {
    @Bindable var viewModel: PayFlowViewModel

    /// Items the current user has claimed (local state for MVP).
    @State private var claimedItemIds: Set<UUID> = []

    /// Only items with a non-zero price are claimable.
    private var items: [PayReceiptItem] {
        (viewModel.receipt?.items ?? []).filter { $0.totalCents > 0 }
    }

    /// Total cents for items the user has claimed.
    private var claimedTotal: Int64 {
        items
            .filter { claimedItemIds.contains($0.id) }
            .reduce(0) { $0 + $1.totalCents }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Scrollable content ──────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Pick your items")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.sm)

                    Text("Tap the items you ordered.")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(.top, TallySpacing.sm)

                    // ── Receipt items ───────────────────────────────────────
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            itemRow(item: item)

                            if index < items.count - 1 {
                                Rectangle()
                                    .fill(TallyColors.divider)
                                    .frame(height: 0.5)
                            }
                        }
                    }
                    .padding(.top, TallySpacing.xl)
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.lg)
            }

            // ── Running total + button ──────────────────────────────────────
            VStack(spacing: TallySpacing.md) {
                if claimedTotal > 0 {
                    HStack {
                        Text("Your total")
                            .font(TallyFont.bodySemibold)
                            .foregroundStyle(TallyColors.textSecondary)

                        Spacer()

                        Text(CentsFormatter.format(claimedTotal))
                            .font(TallyFont.amounts)
                            .foregroundStyle(TallyColors.textPrimary)
                    }
                    .padding(.horizontal, TallySpacing.screenPadding)
                }

                Button("I'm done") {
                    viewModel.push(.waiting)
                }
                .buttonStyle(TallyPrimaryButtonStyle())
                .padding(.horizontal, TallySpacing.screenPadding)
            }
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
    }

    // MARK: - Item Row

    @ViewBuilder
    private func itemRow(item: PayReceiptItem) -> some View {
        let isClaimed = claimedItemIds.contains(item.id)
        let claimedByOther = !isClaimed && item.claimedByMemberId != nil
        let otherInitial: String? = claimedByOther
            ? viewModel.splits.first(where: { $0.memberId == item.claimedByMemberId })
                .map { String($0.memberName.prefix(1)).uppercased() }
            : nil

        Button {
            guard !claimedByOther else { return }
            withAnimation(.spring(response: 0.2)) {
                if isClaimed {
                    claimedItemIds.remove(item.id)
                } else {
                    claimedItemIds.insert(item.id)
                }
            }
        } label: {
            HStack(spacing: 0) {
                // Green left border for claimed items
                Rectangle()
                    .fill(isClaimed ? TallyColors.accent : Color.clear)
                    .frame(width: 3)

                HStack(spacing: TallySpacing.lg) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(TallyFont.bodySemibold)
                            .foregroundStyle(
                                claimedByOther ? TallyColors.textTertiary : TallyColors.textPrimary
                            )
                            .lineLimit(1)

                        if item.quantity > 1 {
                            Text("Qty \(item.quantity)")
                                .font(TallyFont.caption)
                                .foregroundStyle(TallyColors.textSecondary)
                        }
                    }

                    Spacer()

                    // Status indicator
                    if isClaimed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(TallyColors.accent)
                    } else if let initial = otherInitial {
                        Text(initial)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(TallyColors.textSecondary)
                            .frame(width: 24, height: 24)
                            .background(TallyColors.bgSecondary)
                            .clipShape(Circle())
                    }

                    Text(CentsFormatter.format(item.totalCents))
                        .font(TallyFont.amounts)
                        .foregroundStyle(
                            claimedByOther ? TallyColors.textTertiary : TallyColors.textPrimary
                        )
                }
                .padding(.leading, TallySpacing.md)
            }
            .frame(minHeight: TallySpacing.listItemMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(claimedByOther ? 0.5 : 1.0)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PayMemberSelectView(viewModel: {
            let vm = PayFlowViewModel()
            var receipt = PayReceipt.sample
            // Mark one item as claimed by another member
            receipt.items[2].claimedByMemberId = "m1"
            vm.receipt = receipt
            vm.splits = PaySplit.samples
            return vm
        }())
    }
}

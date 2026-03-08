import SwiftUI

struct PayLeaderAssignView: View {
    @Bindable var viewModel: PayFlowViewModel

    @State private var assignments: [UUID: String] = [:]   // itemId -> memberId

    /// Only items with a non-zero price are assignable.
    private var allocatableItems: [PayReceiptItem] {
        (viewModel.receipt?.items ?? []).filter { $0.totalCents > 0 }
    }

    private var members: [GroupMemberDTO] {
        viewModel.serverMembers
    }

    /// Running total per member (cents) based on current local assignments.
    private func memberTotal(for memberId: String) -> Int64 {
        assignments
            .filter { $0.value == memberId }
            .compactMap { kvp in allocatableItems.first(where: { $0.id == kvp.key })?.totalCents }
            .reduce(0, +)
    }

    /// Total cents not yet assigned to any member.
    private var unassignedTotal: Int64 {
        allocatableItems
            .filter { assignments[$0.id] == nil }
            .reduce(0) { $0 + $1.totalCents }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Scrollable content ──────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Assign items")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.sm)

                    Text("Tap a member on each item to assign it.")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(.top, TallySpacing.sm)

                    // ── Receipt items with inline member assignment ────────
                    LazyVStack(spacing: TallySpacing.md) {
                        ForEach(allocatableItems) { item in
                            itemCard(item: item)
                        }
                    }
                    .padding(.top, TallySpacing.xl)

                    // ── Per-member summary ─────────────────────────────────
                    memberSummary
                        .padding(.top, TallySpacing.xl)
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.lg)
            }

            // ── Pinned bottom button ────────────────────────────────────────
            Button("Continue") {
                handleContinue()
            }
            .buttonStyle(TallyDarkButtonStyle())
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
    }

    // MARK: - Continue

    private func handleContinue() {
        viewModel.computeItemizedSplits(assignments: assignments, items: allocatableItems)
        viewModel.applyTipToSplits()
        viewModel.push(.leaderApprove)
    }

    // MARK: - Item Card

    private func itemCard(item: PayReceiptItem) -> some View {
        let assignedMemberId = assignments[item.id]

        return VStack(alignment: .leading, spacing: TallySpacing.md) {
            // Item name + price
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(TallyColors.textPrimary)
                        .lineLimit(1)

                    if item.quantity > 1 {
                        Text("Qty \(item.quantity)")
                            .font(TallyFont.caption)
                            .foregroundStyle(TallyColors.textSecondary)
                    }
                }

                Spacer()

                Text(CentsFormatter.format(item.totalCents))
                    .font(TallyFont.amounts)
                    .foregroundStyle(TallyColors.textPrimary)
            }

            // Inline member avatars
            HStack(spacing: TallySpacing.sm) {
                ForEach(Array(members.enumerated()), id: \.element.memberID) { index, member in
                    Button {
                        withAnimation(.spring(response: 0.2)) {
                            if assignments[item.id] == member.memberID {
                                assignments.removeValue(forKey: item.id)
                            } else {
                                assignments[item.id] = member.memberID
                            }
                        }
                    } label: {
                        let isAssigned = assignedMemberId == member.memberID
                        HStack(spacing: TallySpacing.xs) {
                            Text(String(member.displayName.prefix(1)).uppercased())
                                .font(TallyFont.smallLabel)
                                .foregroundStyle(isAssigned ? .white : TallyColors.textSecondary)
                                .frame(width: 24, height: 24)
                                .background(isAssigned ? TallyColors.cardColor(for: index) : TallyColors.bgSecondary)
                                .clipShape(Circle())

                            Text(member.displayName.components(separatedBy: " ").first ?? member.displayName)
                                .font(TallyFont.caption)
                                .foregroundStyle(isAssigned ? TallyColors.textPrimary : TallyColors.textTertiary)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, TallySpacing.sm)
                        .padding(.vertical, TallySpacing.xs)
                        .background(isAssigned ? TallyColors.cardColor(for: index).opacity(0.1) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.chipCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: TallySpacing.chipCornerRadius)
                                .stroke(isAssigned ? TallyColors.cardColor(for: index).opacity(0.3) : TallyColors.divider, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(TallySpacing.cardPadding)
        .background(TallyColors.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    // MARK: - Member Summary

    private var memberSummary: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(TallyColors.divider)
                .frame(height: 0.5)
                .padding(.bottom, TallySpacing.lg)

            ForEach(Array(members.enumerated()), id: \.element.memberID) { index, member in
                let total = memberTotal(for: member.memberID)
                HStack(spacing: TallySpacing.md) {
                    Text(String(member.displayName.prefix(1)).uppercased())
                        .font(TallyFont.smallLabel)
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(TallyColors.cardColor(for: index))
                        .clipShape(Circle())

                    Text(member.displayName)
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textPrimary)

                    Spacer()

                    Text(CentsFormatter.format(total))
                        .font(TallyFont.amounts)
                        .foregroundStyle(total > 0 ? TallyColors.textPrimary : TallyColors.textTertiary)
                }
                .padding(.vertical, TallySpacing.xs)
            }

            if unassignedTotal > 0 {
                HStack {
                    Text("Unassigned")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                    Spacer()
                    Text(CentsFormatter.format(unassignedTotal))
                        .font(TallyFont.amounts)
                        .foregroundStyle(TallyColors.statusAlert)
                }
                .padding(.vertical, TallySpacing.xs)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PayLeaderAssignView(viewModel: {
            let vm = PayFlowViewModel()
            vm.receipt = PayReceipt.sample
            vm.serverMembers = [
                GroupMemberDTO(memberID: "m1", displayName: "Sarah Kim", splitWeight: 1.0, tallyBalanceCents: 0, isLeader: false, hasCard: false, kycStatus: "approved"),
                GroupMemberDTO(memberID: "m2", displayName: "Alex Chen", splitWeight: 1.0, tallyBalanceCents: 0, isLeader: false, hasCard: false, kycStatus: "approved"),
                GroupMemberDTO(memberID: "m3", displayName: "You", splitWeight: 1.0, tallyBalanceCents: 0, isLeader: true, hasCard: true, kycStatus: "approved"),
            ]
            return vm
        }())
    }
}

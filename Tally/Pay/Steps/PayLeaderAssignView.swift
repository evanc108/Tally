import SwiftUI

struct PayLeaderAssignView: View {
    @Bindable var viewModel: PayFlowViewModel

    @State private var selectedItemId: UUID?
    @State private var assignments: [UUID: String] = [:]   // itemId -> memberId

    private var items: [PayReceiptItem] {
        viewModel.receipt?.items ?? []
    }

    private var members: [PaySplit] {
        viewModel.splits
    }

    /// Running total per member (cents) based on current local assignments.
    private func memberTotal(for memberId: String) -> Int64 {
        assignments
            .filter { $0.value == memberId }
            .compactMap { kvp in items.first(where: { $0.id == kvp.key })?.totalCents }
            .reduce(0, +)
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

                    Text("Tap an item, then tap a member to assign it.")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(.top, TallySpacing.sm)

                    // ── Member chips (horizontal scroll) ────────────────────
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: TallySpacing.md) {
                            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                                memberChip(member: member, index: index)
                            }
                        }
                        .padding(.vertical, TallySpacing.sm)
                    }
                    .padding(.top, TallySpacing.lg)

                    // ── Receipt items ───────────────────────────────────────
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            itemRow(item: item, index: index)

                            if index < items.count - 1 {
                                Rectangle()
                                    .fill(TallyColors.divider)
                                    .frame(height: 0.5)
                            }
                        }
                    }
                    .padding(.top, TallySpacing.lg)
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.lg)
            }

            // ── Pinned bottom button ────────────────────────────────────────
            Button("Continue") {
                viewModel.push(.leaderApprove)
            }
            .buttonStyle(TallyPrimaryButtonStyle())
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
    }

    // MARK: - Member Chip

    private func memberChip(member: PaySplit, index: Int) -> some View {
        let isTarget = selectedItemId != nil
        let total = memberTotal(for: member.memberId)

        return Button {
            guard let itemId = selectedItemId else { return }
            // Toggle: if already assigned to this member, unassign
            if assignments[itemId] == member.memberId {
                assignments.removeValue(forKey: itemId)
            } else {
                assignments[itemId] = member.memberId
            }
            selectedItemId = nil
        } label: {
            VStack(spacing: TallySpacing.xs) {
                Text(String(member.memberName.prefix(1)).uppercased())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TallyColors.ink)
                    .frame(width: 36, height: 36)
                    .background(TallyColors.cardColor(for: index))
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(TallyColors.accent, lineWidth: isTarget ? 2 : 0)
                    )

                Text(member.memberName.components(separatedBy: " ").first ?? member.memberName)
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
                    .lineLimit(1)

                if total > 0 {
                    Text(CentsFormatter.format(total))
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.accent)
                }
            }
            .frame(minWidth: 64)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Item Row

    private func itemRow(item: PayReceiptItem, index: Int) -> some View {
        let isSelected = selectedItemId == item.id
        let assignedMemberId = assignments[item.id]
        let assignedMember = assignedMemberId.flatMap { mid in members.first(where: { $0.memberId == mid }) }
        let assignedIndex = assignedMemberId.flatMap { mid in members.firstIndex(where: { $0.memberId == mid }) }

        return Button {
            withAnimation(.spring(response: 0.2)) {
                selectedItemId = isSelected ? nil : item.id
            }
        } label: {
            HStack(spacing: TallySpacing.lg) {
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

                // Assigned member badge
                if let member = assignedMember, let idx = assignedIndex {
                    Text(String(member.memberName.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(TallyColors.ink)
                        .frame(width: 24, height: 24)
                        .background(TallyColors.cardColor(for: idx))
                        .clipShape(Circle())
                }

                Text(CentsFormatter.format(item.totalCents))
                    .font(TallyFont.amounts)
                    .foregroundStyle(TallyColors.textPrimary)
            }
            .frame(minHeight: TallySpacing.listItemMinHeight)
            .padding(.vertical, TallySpacing.xs)
            .background(isSelected ? TallyColors.bgSecondary : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PayLeaderAssignView(viewModel: {
            let vm = PayFlowViewModel()
            vm.receipt = PayReceipt.sample
            vm.splits = PaySplit.samples
            return vm
        }())
    }
}

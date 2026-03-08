import SwiftUI

struct PaySplitConfigView: View {
    @Bindable var viewModel: PayFlowViewModel

    private var availableMethods: [PaySplitMethod] {
        PaySplitMethod.allCases.filter { method in
            if method == .itemized { return viewModel.receipt != nil }
            return true
        }
    }

    private var isPercentageValid: Bool {
        let total = viewModel.serverMembers.reduce(0.0) {
            $0 + (viewModel.memberPercentages[$1.memberID] ?? 0)
        }
        return abs(total - 100.0) < 0.01
    }

    private var isContinueDisabled: Bool {
        if viewModel.isFetchingMembers { return true }
        if viewModel.splitMethod == .percentage && !isPercentageValid { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Scrollable content ──────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Split the bill")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.sm)

                    // Total display
                    Text(CentsFormatter.format(viewModel.totalCents))
                        .font(TallyFont.amounts)
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(.top, TallySpacing.sm)

                    // Split method cards (hide "By Items" when no receipt)
                    VStack(spacing: TallySpacing.md) {
                        ForEach(availableMethods) { method in
                            SplitMethodCard(
                                method: method,
                                isSelected: viewModel.splitMethod == method
                            ) {
                                withAnimation(.spring(response: 0.3)) {
                                    viewModel.splitMethod = method
                                    if method == .percentage && viewModel.memberPercentages.isEmpty {
                                        viewModel.initializeEqualPercentages()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, TallySpacing.xl)

                    // ── Equal split preview ───────────────────────────────
                    if viewModel.splitMethod == .equal {
                        memberAmountPreview
                            .padding(.top, TallySpacing.xl)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // ── Percentage sliders (inline) ───────────────────────
                    if viewModel.splitMethod == .percentage {
                        percentageSection
                            .padding(.top, TallySpacing.xl)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // ── Itemized assignment mode ──────────────────────────
                    if viewModel.splitMethod == .itemized {
                        assignmentModeSection
                            .padding(.top, TallySpacing.xl)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.lg)
            }

            // ── Pinned bottom button ────────────────────────────────────────
            Button("Continue") {
                handleContinue()
            }
            .buttonStyle(TallyDarkButtonStyle())
            .disabled(isContinueDisabled)
            .opacity(isContinueDisabled ? 0.5 : 1.0)
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
        .onAppear {
            // Reset to .equal if itemized was selected but no receipt exists
            if viewModel.splitMethod == .itemized && viewModel.receipt == nil {
                viewModel.splitMethod = .equal
            }
            // Recompute splits now that totalCents is known
            if viewModel.splitMethod == .equal {
                viewModel.computeEqualSplits()
                viewModel.applyTipToSplits()
            }
            if viewModel.splitMethod == .percentage && viewModel.memberPercentages.isEmpty {
                viewModel.initializeEqualPercentages()
            }
        }
    }

    // MARK: - Member Amount Preview (Equal)

    private var memberAmountPreview: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.splits.enumerated()), id: \.element.id) { index, split in
                HStack(spacing: TallySpacing.md) {
                    Text(String(split.memberName.prefix(1)).uppercased())
                        .font(TallyFont.overline)
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(TallyColors.cardColor(for: index))
                        .clipShape(Circle())

                    Text(split.memberName)
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(CentsFormatter.format(split.amountCents + split.tipCents))
                        .font(TallyFont.amounts)
                        .foregroundStyle(TallyColors.textPrimary)
                }
                .frame(minHeight: TallySpacing.listItemMinHeight)

                if index < viewModel.splits.count - 1 {
                    Rectangle()
                        .fill(TallyColors.divider)
                        .frame(height: 0.5)
                }
            }
        }
    }

    // MARK: - Percentage Section (Inline)

    private var percentageSection: some View {
        VStack(spacing: 0) {
            // Sliders
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
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)

            // Per-member amount preview
            VStack(spacing: 0) {
                ForEach(Array(viewModel.serverMembers.enumerated()), id: \.element.memberID) { index, member in
                    let pct = viewModel.memberPercentages[member.memberID] ?? 0
                    let cents = Int64((Double(viewModel.totalCents) * pct / 100.0).rounded())

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
            .padding(.top, TallySpacing.xl)
        }
    }

    // MARK: - Assignment Mode Section (Itemized)

    private var assignmentModeSection: some View {
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            Text("Who assigns items?")
                .font(TallyFont.bodySemibold)
                .foregroundStyle(TallyColors.textPrimary)

            AssignmentModeCard(
                label: "Leader assigns",
                description: "You pick who gets each item",
                icon: "person.badge.shield.checkmark",
                isSelected: viewModel.assignmentMode == .leader
            ) {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.assignmentMode = .leader
                }
            }

            AssignmentModeCard(
                label: "Everyone picks",
                description: "Members claim their own items",
                icon: "person.3",
                isSelected: viewModel.assignmentMode == .everyone
            ) {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.assignmentMode = .everyone
                }
            }
        }
    }

    // MARK: - Continue Action

    private func handleContinue() {
        switch viewModel.splitMethod {
        case .equal:
            viewModel.computeEqualSplits()
            viewModel.applyTipToSplits()
            viewModel.push(.leaderApprove)

        case .percentage:
            viewModel.computePercentageSplits()
            viewModel.applyTipToSplits()
            viewModel.push(.leaderApprove)

        case .itemized:
            switch viewModel.assignmentMode {
            case .leader:
                viewModel.push(.leaderAssign)
            case .everyone:
                viewModel.push(.memberSelect)
            }
        }
    }
}

// MARK: - Split Method Card

private struct SplitMethodCard: View {
    let method: PaySplitMethod
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TallySpacing.lg) {
                // Left accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? TallyColors.ink : Color.clear)
                    .frame(width: 3, height: 44)

                // Icon
                Image(systemName: method.icon)
                    .font(TallyIcon.xl)
                    .foregroundStyle(isSelected ? TallyColors.ink : TallyColors.textSecondary)
                    .frame(width: 28)

                // Label + description
                VStack(alignment: .leading, spacing: 4) {
                    Text(method.label)
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(TallyColors.textPrimary)
                    Text(method.description)
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(TallyIcon.sm)
                        .foregroundStyle(TallyColors.ink)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, TallySpacing.cardPadding)
            .padding(.vertical, TallySpacing.lg)
            .background(TallyColors.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
            .shadow(color: .black.opacity(isSelected ? 0.10 : 0.06), radius: 12, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Assignment Mode Card

private struct AssignmentModeCard: View {
    let label: String
    let description: String
    let icon: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TallySpacing.lg) {
                // Left accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? TallyColors.ink : Color.clear)
                    .frame(width: 3, height: 44)

                // Icon
                Image(systemName: icon)
                    .font(TallyIcon.xl)
                    .foregroundStyle(isSelected ? TallyColors.ink : TallyColors.textSecondary)
                    .frame(width: 28)

                // Label + description
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(TallyColors.textPrimary)
                    Text(description)
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                }

                Spacer()

                // Checkmark
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(TallyIcon.sm)
                        .foregroundStyle(TallyColors.ink)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, TallySpacing.cardPadding)
            .padding(.vertical, TallySpacing.lg)
            .background(TallyColors.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
            .shadow(color: .black.opacity(isSelected ? 0.10 : 0.06), radius: 12, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PaySplitConfigView(viewModel: {
            let vm = PayFlowViewModel()
            vm.selectedCircle = TallyCircle.sample
            vm.manualAmountCents = 8640
            vm.splitMethod = .equal
            vm.computeEqualSplits()
            return vm
        }())
    }
}

#Preview("Itemized") {
    NavigationStack {
        PaySplitConfigView(viewModel: {
            let vm = PayFlowViewModel()
            vm.selectedCircle = TallyCircle.sample
            vm.manualAmountCents = 8640
            vm.splitMethod = .itemized
            return vm
        }())
    }
}

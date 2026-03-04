import SwiftUI

struct PaySplitConfigView: View {
    @Bindable var viewModel: PayFlowViewModel

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

                    // Split method cards
                    VStack(spacing: TallySpacing.md) {
                        ForEach(PaySplitMethod.allCases) { method in
                            SplitMethodCard(
                                method: method,
                                isSelected: viewModel.splitMethod == method
                            ) {
                                withAnimation(.spring(response: 0.3)) {
                                    viewModel.splitMethod = method
                                }
                            }
                        }
                    }
                    .padding(.top, TallySpacing.xl)

                    // Equal split preview
                    if viewModel.splitMethod == .equal, let circle = viewModel.selectedCircle {
                        equalSplitPreview(circle: circle)
                            .padding(.top, TallySpacing.xl)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Itemized assignment mode
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
            .buttonStyle(TallyPrimaryButtonStyle())
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
        .onAppear {
            // Recompute splits now that totalCents is known.
            if viewModel.splitMethod == .equal {
                viewModel.computeEqualSplits()
            }
        }
    }

    // MARK: - Equal Split Preview

    private func equalSplitPreview(circle: TallyCircle) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.splits.enumerated()), id: \.element.id) { index, split in
                HStack(spacing: TallySpacing.md) {
                    // Avatar initial circle
                    Text(String(split.memberName.prefix(1)).uppercased())
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(memberColor(for: index))
                        .clipShape(Circle())

                    Text(split.memberName)
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Text(CentsFormatter.format(split.amountCents))
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

    private func memberColor(for index: Int) -> Color {
        TallyColors.cardColor(for: index)
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
        case .equal, .percentage:
            viewModel.computeEqualSplits()
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
                    .fill(isSelected ? TallyColors.accent : Color.clear)
                    .frame(width: 3, height: 44)

                // Icon
                Image(systemName: method.icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? TallyColors.accent : TallyColors.textSecondary)
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TallyColors.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, TallySpacing.cardPadding)
            .padding(.vertical, TallySpacing.lg)
            .background(isSelected ? TallyColors.accent.opacity(0.05) : TallyColors.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                    .stroke(isSelected ? TallyColors.accent.opacity(0.3) : TallyColors.divider, lineWidth: 1)
            )
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
                    .fill(isSelected ? TallyColors.accent : Color.clear)
                    .frame(width: 3, height: 44)

                // Icon
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? TallyColors.accent : TallyColors.textSecondary)
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
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TallyColors.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, TallySpacing.cardPadding)
            .padding(.vertical, TallySpacing.lg)
            .background(isSelected ? TallyColors.accent.opacity(0.05) : TallyColors.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                    .stroke(isSelected ? TallyColors.accent.opacity(0.3) : TallyColors.divider, lineWidth: 1)
            )
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

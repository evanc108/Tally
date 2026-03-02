import SwiftUI

struct SplitMethodView: View {
    @Bindable var state: CreateCircleState
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Title
                    Text("How do you split?")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.sm)

                    // Method cards
                    VStack(spacing: TallySpacing.md) {
                        ForEach(SplitMethod.allCases) { method in
                            SplitMethodCard(
                                method: method,
                                isSelected: state.splitMethod == method
                            ) {
                                withAnimation(.spring(response: 0.3)) {
                                    state.splitMethod = method
                                    if method == .percentage {
                                        state.initializeEqualPercentages()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, TallySpacing.xl)

                    // Percentage sliders
                    if state.splitMethod == .percentage {
                        percentageSliders
                            .padding(.top, TallySpacing.xl)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }

                    // Split bar
                    splitBar
                        .padding(.top, TallySpacing.xl)
                }
                .padding(.horizontal, TallySpacing.screenPadding)
            }

            // Continue button
            Button("Continue", action: onContinue)
                .buttonStyle(TallyPrimaryButtonStyle())
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
    }

    // MARK: - Percentage Sliders

    private var percentageSliders: some View {
        VStack(spacing: 0) {
            // "You" row
            PercentageRow(
                name: "You",
                color: TallyColors.accent,
                percentage: state.youPercentage
            ) { val in
                state.updateYouPercentage(to: val)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(TallyColors.divider).frame(height: 0.5)
            }

            // Member rows
            ForEach(Array(state.members.enumerated()), id: \.element.id) { index, member in
                PercentageRow(
                    name: member.name.split(separator: " ").first.map(String.init) ?? member.name,
                    color: member.color,
                    percentage: member.splitPercentage
                ) { val in
                    state.updatePercentage(forMemberAt: index, to: val)
                }
                .overlay(alignment: .bottom) {
                    if index < state.members.count - 1 {
                        Rectangle().fill(TallyColors.divider).frame(height: 0.5)
                    }
                }
            }

            // Total row
            HStack {
                Text("Total")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TallyColors.textPrimary)
                Spacer()
                let total = state.youPercentage + state.members.reduce(0.0) { $0 + $1.splitPercentage }
                Text("\(Int(total.rounded()))%")
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(abs(total - 100) < 1 ? TallyColors.accent : TallyColors.statusAlert)
            }
            .padding(.vertical, TallySpacing.md)
            .padding(.top, TallySpacing.xs)
        }
    }

    // MARK: - Split Bar

    private var splitBar: some View {
        VStack(spacing: TallySpacing.sm) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    let count = state.members.count + 1
                    if state.splitMethod == .percentage {
                        let total = state.youPercentage + state.members.reduce(0.0) { $0 + $1.splitPercentage }
                        let available = geo.size.width - CGFloat(count - 1) * 2

                        RoundedRectangle(cornerRadius: 4)
                            .fill(TallyColors.accent)
                            .frame(width: total > 0 ? max(available * state.youPercentage / total, 4) : 4)

                        ForEach(state.members) { member in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(member.color)
                                .frame(width: total > 0 ? max(available * member.splitPercentage / total, 4) : 4)
                        }
                    } else {
                        let segWidth = max((geo.size.width - CGFloat(count - 1) * 2) / CGFloat(count), 0)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(TallyColors.accent)
                            .frame(width: segWidth)
                        ForEach(state.members) { member in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(member.color)
                                .frame(width: segWidth)
                        }
                    }
                }
            }
            .frame(height: 8)

            // Legend
            HStack(spacing: TallySpacing.lg) {
                legendDot(color: TallyColors.accent, name: "You")
                ForEach(state.members) { member in
                    legendDot(color: member.color, name: member.name.split(separator: " ").first.map(String.init) ?? member.name)
                }
            }
            .font(TallyFont.caption)
            .foregroundStyle(TallyColors.textSecondary)
        }
    }

    private func legendDot(color: Color, name: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name)
        }
    }
}

// MARK: - Percentage Row

private struct PercentageRow: View {
    let name: String
    let color: Color
    let percentage: Double
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: TallySpacing.md) {
            Text(name)
                .font(.system(size: 16))
                .foregroundStyle(TallyColors.textPrimary)
                .frame(width: 72, alignment: .leading)

            Slider(
                value: Binding(
                    get: { percentage },
                    set: { onChange($0) }
                ),
                in: 0...100,
                step: 1
            )
            .tint(color)

            Text("\(Int(percentage.rounded()))%")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(TallyColors.textPrimary)
                .frame(width: 48, alignment: .trailing)
        }
        .padding(.vertical, TallySpacing.md)
    }
}

// MARK: - Method Card

private struct SplitMethodCard: View {
    let method: SplitMethod
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TallySpacing.lg) {
                // Left accent bar
                RoundedRectangle(cornerRadius: 2)
                    .fill(isSelected ? TallyColors.accent : Color.clear)
                    .frame(width: 3, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(method.rawValue)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TallyColors.textPrimary)
                    Text(method.description)
                        .font(.system(size: 13))
                        .foregroundStyle(TallyColors.textSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TallyColors.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(TallySpacing.lg)
            .background(TallyColors.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

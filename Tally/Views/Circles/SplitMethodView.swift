import SwiftUI

struct SplitMethodView: View {
    @Bindable var state: CreateCircleState
    var onContinue: () -> Void

    private let methods: [SplitMethod] = [.equal, .percentage]

    var body: some View {
        VStack(spacing: 0) {
            // ── Scrollable content ────────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("How do you split?")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.sm)

                    VStack(spacing: TallySpacing.md) {
                        ForEach(methods) { method in
                            SplitMethodCard(method: method, isSelected: state.splitMethod == method) {
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

                    if state.splitMethod == .percentage {
                        percentageSliders
                            .padding(.top, TallySpacing.xl)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.lg)
            }

            // ── Pinned bottom — always visible ────────────────────────────────
            VStack(spacing: 0) {
                splitBar
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.bottom, TallySpacing.xl)

                Button("Continue", action: onContinue)
                    .buttonStyle(TallyPrimaryButtonStyle())
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.bottom, TallySpacing.xxxl)
            }
            .padding(.top, TallySpacing.lg)
            .background(TallyColors.bgPrimary)
        }
        .background(TallyColors.bgPrimary)
    }

    // MARK: - Percentage Sliders

    private var percentageSliders: some View {
        VStack(spacing: 0) {
            PercentageRow(name: "You", color: TallyColors.accent, percentage: state.youPercentage) { val in
                state.updateYouPercentage(to: val)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(TallyColors.divider).frame(height: 0.5)
            }

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
        }
        .background(TallyColors.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 3)
    }

    // MARK: - Split Bar

    private var splitBar: some View {
        VStack(spacing: TallySpacing.sm) {
            // Faint % labels above each segment — equal mode only
            if state.splitMethod == .equal {
                Color.clear
                    .frame(height: 14)
                    .background(
                        GeometryReader { geo in
                            equalLabels(width: geo.size.width)
                        }
                    )
            }

            // Bar — use background GeometryReader for reliable width
            Color.clear
                .frame(height: 10)
                .background(
                    GeometryReader { geo in
                        barSegments(width: geo.size.width)
                            .animation(.spring(response: 0.3), value: state.youPercentage)
                            .animation(.spring(response: 0.3), value: state.members.map { $0.splitPercentage })
                    }
                )

            // Legend
            HStack(spacing: TallySpacing.lg) {
                legendDot(color: TallyColors.accent, name: "You")
                ForEach(state.members) { member in
                    legendDot(
                        color: member.color,
                        name: member.name.split(separator: " ").first.map(String.init) ?? member.name
                    )
                }
            }
            .font(TallyFont.caption)
            .foregroundStyle(TallyColors.textSecondary)
        }
    }

    @ViewBuilder
    private func barSegments(width: CGFloat) -> some View {
        let count = state.members.count + 1
        let totalSpacing = 3.0 * CGFloat(max(count - 1, 0))
        let usable = max(width - totalSpacing, 0)

        if state.splitMethod == .percentage {
            let total = max(
                state.youPercentage + state.members.reduce(0.0) { $0 + $1.splitPercentage },
                1
            )
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 5).fill(TallyColors.accent)
                    .frame(width: max(usable * state.youPercentage / total, 4), height: 10)
                ForEach(state.members) { member in
                    RoundedRectangle(cornerRadius: 5).fill(member.color)
                        .frame(width: max(usable * member.splitPercentage / total, 4), height: 10)
                }
            }
            .frame(width: width, height: 10, alignment: .leading)
        } else {
            let segW = count > 0 ? usable / CGFloat(count) : usable
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 5).fill(TallyColors.accent)
                    .frame(width: segW, height: 10)
                ForEach(state.members) { member in
                    RoundedRectangle(cornerRadius: 5).fill(member.color)
                        .frame(width: segW, height: 10)
                }
            }
            .frame(width: width, height: 10, alignment: .leading)
        }
    }

    private func equalLabels(width: CGFloat) -> some View {
        let count = state.members.count + 1
        let pct = count > 0 ? Int((100.0 / Double(count)).rounded()) : 100
        let totalSpacing = 3.0 * CGFloat(max(count - 1, 0))
        let segW = count > 0 ? max((width - totalSpacing) / CGFloat(count), 0) : width

        return HStack(spacing: 3) {
            Text("\(pct)%")
                .font(TallyFont.micro)
                .foregroundStyle(TallyColors.textSecondary.opacity(0.45))
                .frame(width: segW)
            ForEach(state.members) { member in
                Text("\(pct)%")
                    .font(TallyFont.micro)
                    .foregroundStyle(TallyColors.textSecondary.opacity(0.45))
                    .frame(width: segW)
            }
        }
        .frame(width: width, height: 14, alignment: .center)
    }

    private func legendDot(color: Color, name: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(name)
        }
    }
}

// MARK: - Percentage Row

struct PercentageRow: View {
    let name: String
    let color: Color
    let percentage: Double
    let onChange: (Double) -> Void

    @FocusState private var isFocused: Bool
    @State private var textValue: String = ""

    var body: some View {
        HStack(spacing: TallySpacing.md) {
            // Color dot + name
            HStack(spacing: TallySpacing.sm) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(name)
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textPrimary)
            }
            .frame(width: 80, alignment: .leading)

            // Slider
            Slider(
                value: Binding(get: { percentage }, set: { onChange($0.rounded()) }),
                in: 0...100,
                step: 1
            )
            .tint(color)

            // Editable percentage field — wide enough for "100"
            HStack(spacing: 1) {
                TextField("0", text: $textValue)
                    .font(TallyFont.amounts)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($isFocused)
                    .frame(width: 44)
                    .onChange(of: textValue) { _, val in
                        let digits = val.filter(\.isNumber)
                        if digits != val { textValue = digits }
                        if let d = Double(digits) {
                            let clamped = min(max(d, 0), 100)
                            // Guard prevents re-entrant updates when percentage syncs back
                            if abs(clamped - percentage) >= 0.5 {
                                onChange(clamped)
                            }
                        }
                    }
                Text("%")
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
            }
            .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, TallySpacing.md)
        .padding(.horizontal, TallySpacing.lg)
        .onAppear { textValue = "\(Int(percentage.rounded()))" }
        .onChange(of: percentage) { _, val in
            if !isFocused {
                let newText = "\(Int(val.rounded()))"
                if newText != textValue { textValue = newText }
            }
        }
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

                VStack(alignment: .leading, spacing: 4) {
                    Text(method.rawValue)
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(TallyColors.textPrimary)
                    Text(method.description)
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(TallyIcon.sm)
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

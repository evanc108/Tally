import SwiftUI

struct PayTipConfigView: View {
    @Bindable var viewModel: PayFlowViewModel

    @State private var selectedPreset: TipPreset = .none
    @State private var customDollars: String = ""
    @State private var isCustomActive = false

    private enum TipPreset: String, CaseIterable, Identifiable {
        case none, fifteen, eighteen, twenty, custom
        var id: String { rawValue }

        var label: String {
            switch self {
            case .none:     "None"
            case .fifteen:  "15%"
            case .eighteen: "18%"
            case .twenty:   "20%"
            case .custom:   "Custom"
            }
        }

        var percent: Int? {
            switch self {
            case .none:     0
            case .fifteen:  15
            case .eighteen: 18
            case .twenty:   20
            case .custom:   nil
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Scrollable content ──────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Add a tip")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.sm)

                    // Bill amount
                    Text("Bill: \(CentsFormatter.format(viewModel.preTipCents))")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(.top, TallySpacing.sm)

                    // Auto-gratuity (locked, unchangeable)
                    if viewModel.receiptTipCents > 0 {
                        HStack(spacing: TallySpacing.sm) {
                            Image(systemName: "lock.fill")
                                .font(TallyIcon.xs)
                            Text("Included gratuity")
                                .font(TallyFont.body)
                            Spacer()
                            Text(CentsFormatter.format(viewModel.receiptTipCents))
                                .font(TallyFont.amounts)
                        }
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(TallySpacing.cardPadding)
                        .background(TallyColors.bgPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                        .padding(.top, TallySpacing.lg)
                    }

                    // Hero additional tip amount
                    Text(CentsFormatter.format(viewModel.tipTotalCents))
                        .font(TallyFont.heroAmount)
                        .foregroundStyle(TallyColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, TallySpacing.xxl)
                        .padding(.bottom, TallySpacing.xl)

                    // Quick tip chips
                    HStack(spacing: TallySpacing.xs) {
                        ForEach(TipPreset.allCases) { preset in
                            Button {
                                withAnimation(.spring(response: 0.2)) {
                                    selectedPreset = preset
                                    isCustomActive = preset == .custom
                                    if let pct = preset.percent {
                                        viewModel.setTipPercentage(pct)
                                    }
                                }
                            } label: {
                                Text(preset.label)
                                    .font(TallyFont.caption)
                                    .foregroundStyle(selectedPreset == preset ? .white : TallyColors.textPrimary)
                                    .padding(.horizontal, TallySpacing.sm)
                                    .padding(.vertical, TallySpacing.sm)
                                    .frame(maxWidth: .infinity)
                                    .background(selectedPreset == preset ? TallyColors.ink : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: TallySpacing.chipCornerRadius))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: TallySpacing.chipCornerRadius)
                                            .stroke(selectedPreset == preset ? Color.clear : TallyColors.divider, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Custom input
                    if isCustomActive {
                        HStack(spacing: TallySpacing.sm) {
                            Text("$")
                                .font(TallyFont.bodySemibold)
                                .foregroundStyle(TallyColors.textSecondary)

                            TextField("0.00", text: $customDollars)
                                .font(TallyFont.body)
                                .keyboardType(.decimalPad)
                                .onChange(of: customDollars) { _, newValue in
                                    if let dollars = Double(newValue) {
                                        viewModel.tipTotalCents = Int64((dollars * 100).rounded())
                                    } else if newValue.isEmpty {
                                        viewModel.tipTotalCents = 0
                                    }
                                }
                        }
                        .padding(TallySpacing.md)
                        .background(TallyColors.bgPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
                        .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                        .padding(.top, TallySpacing.md)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Total line
                    HStack {
                        Text("Total")
                            .font(TallyFont.bodySemibold)
                            .foregroundStyle(TallyColors.textPrimary)
                        Spacer()
                        Text(CentsFormatter.format(viewModel.totalCents))
                            .font(TallyFont.amounts)
                            .foregroundStyle(TallyColors.textPrimary)
                    }
                    .padding(.top, TallySpacing.xl)
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.lg)
            }

            // ── Pinned bottom button ────────────────────────────────────────
            Button("Continue") {
                if viewModel.selectedPaymentMethod?.kind == .wallet {
                    viewModel.push(.walletConfirm)
                } else {
                    viewModel.push(.splitConfig)
                }
            }
            .buttonStyle(TallyDarkButtonStyle())
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
        .onAppear {
            syncPresetFromTip()
        }
    }

    // MARK: - Helpers

    private func syncPresetFromTip() {
        let tip = viewModel.tipTotalCents
        if tip == 0 {
            selectedPreset = .none
        } else {
            for preset in [TipPreset.fifteen, .eighteen, .twenty] {
                if let pct = preset.percent {
                    let expected = Int64((Double(viewModel.preTipCents) * Double(pct) / 100.0).rounded())
                    if tip == expected {
                        selectedPreset = preset
                        return
                    }
                }
            }
            selectedPreset = .custom
            isCustomActive = true
            customDollars = String(format: "%.2f", Double(tip) / 100.0)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PayTipConfigView(viewModel: {
            let vm = PayFlowViewModel()
            vm.receipt = PayReceipt.sample
            return vm
        }())
    }
}

#Preview("No Receipt") {
    NavigationStack {
        PayTipConfigView(viewModel: {
            let vm = PayFlowViewModel()
            vm.manualAmountCents = 5000
            return vm
        }())
    }
}

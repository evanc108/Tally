import SwiftUI

struct PayReceiptReviewView: View {
    @Bindable var viewModel: PayFlowViewModel

    private var receipt: PayReceipt? { viewModel.receipt }
    private var currency: String { receipt?.currency ?? "USD" }

    var body: some View {
        VStack(spacing: 0) {
            // ── Scrollable content ──────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Review receipt")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.sm)

                    if let receipt {
                        // Merchant name
                        if !receipt.merchantName.isEmpty {
                            Text(receipt.merchantName)
                                .font(TallyFont.bodySemibold)
                                .foregroundStyle(TallyColors.textSecondary)
                                .padding(.top, TallySpacing.sm)
                        }

                        // Receipt date
                        if let formatted = receipt.formattedDate {
                            Text(formatted)
                                .font(TallyFont.caption)
                                .foregroundStyle(TallyColors.textTertiary)
                                .padding(.top, TallySpacing.xs)
                        }

                        // Item list
                        itemList(receipt.items)
                            .padding(.top, TallySpacing.xl)

                        // Summary
                        summarySection(receipt)
                            .padding(.top, TallySpacing.xl)
                    } else {
                        noReceiptState
                    }
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.lg)
            }

            // ── Pinned bottom button ────────────────────────────────────────
            Button("Continue") {
                viewModel.push(.tipConfig)
            }
            .buttonStyle(TallyPrimaryButtonStyle())
            .disabled(receipt == nil)
            .opacity(receipt == nil ? 0.5 : 1.0)
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
    }

    // MARK: - Item List

    private func itemList(_ items: [PayReceiptItem]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(TallyFont.body)
                            .foregroundStyle(TallyColors.textPrimary)
                            .lineLimit(2)

                        Text("\(item.quantity)x \(CentsFormatter.format(item.unitCents, currency: currency))")
                            .font(TallyFont.caption)
                            .foregroundStyle(TallyColors.textSecondary)
                    }

                    Spacer()

                    Text(CentsFormatter.format(item.totalCents, currency: currency))
                        .font(TallyFont.amounts)
                        .foregroundStyle(TallyColors.textPrimary)
                }
                .padding(.vertical, TallySpacing.md)

                if index < items.count - 1 {
                    Rectangle()
                        .fill(TallyColors.divider)
                        .frame(height: 0.5)
                }
            }
        }
    }

    // MARK: - Summary Section

    private func summarySection(_ receipt: PayReceipt) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(TallyColors.divider)
                .frame(height: 0.5)
                .padding(.bottom, TallySpacing.lg)

            summaryRow(label: "Subtotal", cents: receipt.subtotalCents)
            summaryRow(label: "Tax", cents: receipt.taxCents)
            summaryRow(label: "Gratuity", cents: receipt.tipCents)

            Rectangle()
                .fill(TallyColors.divider)
                .frame(height: 0.5)
                .padding(.vertical, TallySpacing.md)

            // Total row — bold
            HStack {
                Text("Total")
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                Spacer()
                Text(CentsFormatter.format(receipt.totalCents, currency: currency))
                    .font(TallyFont.amounts)
                    .foregroundStyle(TallyColors.textPrimary)
            }
            .padding(.vertical, TallySpacing.sm)
        }
    }

    private func summaryRow(label: String, cents: Int64) -> some View {
        HStack {
            Text(label)
                .font(TallyFont.body)
                .foregroundStyle(TallyColors.textSecondary)
            Spacer()
            Text(CentsFormatter.format(cents, currency: currency))
                .font(TallyFont.body)
                .foregroundStyle(TallyColors.textSecondary)
        }
        .padding(.vertical, TallySpacing.xs)
    }

    // MARK: - No Receipt State

    private var noReceiptState: some View {
        VStack(spacing: TallySpacing.md) {
            Spacer().frame(height: TallySpacing.xxxl)

            Image(systemName: "doc.text")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(TallyColors.textTertiary)

            Text("No receipt to review")
                .font(TallyFont.bodySemibold)
                .foregroundStyle(TallyColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TallySpacing.xxxl)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PayReceiptReviewView(viewModel: {
            let vm = PayFlowViewModel()
            vm.receipt = PayReceipt.sample
            return vm
        }())
    }
}

#Preview("No Receipt") {
    NavigationStack {
        PayReceiptReviewView(viewModel: PayFlowViewModel())
    }
}

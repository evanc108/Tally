import SwiftUI
import PhotosUI
import VisionKit

struct PayReceiptEntryView: View {
    @Bindable var viewModel: PayFlowViewModel

    @State private var inputMode: InputMode = .manual
    @State private var amountString: String = ""
    @State private var showScanner = false
    @State private var showPaymentPicker = false
    @State private var selectedPhoto: PhotosPickerItem?

    enum InputMode: String {
        case manual, camera
    }

    private var canContinue: Bool {
        viewModel.totalCents > 0 && viewModel.selectedPaymentMethod != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Scrollable content ──────────────────────────────────────────
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Enter your bill")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.sm)

                    // Mode toggle
                    modeToggle
                        .padding(.top, TallySpacing.xl)

                    // Payment method
                    paymentMethodRow
                        .padding(.top, TallySpacing.xl)

                    Rectangle()
                        .fill(TallyColors.divider)
                        .frame(height: 1)

                    if inputMode == .manual {
                        manualEntry
                            .padding(.top, TallySpacing.xxl)
                    } else {
                        scanSection
                            .padding(.top, TallySpacing.xxl)
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
            .disabled(!canContinue)
            .opacity(canContinue ? 1.0 : 0.5)
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxxl)
        }
        .background(TallyColors.bgPrimary)
        .sheet(isPresented: $showScanner) {
            DocumentScannerView(
                onScan: { images in
                    showScanner = false
                    if let first = images.first {
                        Task { await viewModel.processReceiptImage(first) }
                    }
                },
                onCancel: {
                    showScanner = false
                }
            )
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let item = newValue else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await viewModel.processReceiptImage(image)
                }
                selectedPhoto = nil
            }
        }
    }

    // MARK: - Continue Action

    private func handleContinue() {
        if viewModel.receipt != nil {
            viewModel.push(.receiptReview)
        } else {
            viewModel.push(.splitConfig)
        }
    }

    // MARK: - Mode Toggle

    private var modeToggle: some View {
        HStack(spacing: 0) {
            toggleButton("Enter Amount", mode: .manual)
            toggleButton("Scan Receipt", mode: .camera)
        }
        .frame(height: 40)
        .padding(3)
        .background(TallyColors.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.chipCornerRadius))
    }

    private func toggleButton(_ label: String, mode: InputMode) -> some View {
        Button {
            withAnimation(.spring(response: 0.2)) { inputMode = mode }
        } label: {
            Text(label)
                .font(TallyFont.smallLabel)
                .fontWeight(.semibold)
                .foregroundStyle(inputMode == mode ? TallyColors.textPrimary : TallyColors.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(inputMode == mode ? TallyColors.bgPrimary : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: TallySpacing.chipCornerRadius - 2))
                .shadow(color: inputMode == mode ? .black.opacity(0.06) : .clear, radius: 4, y: 1)
        }
    }

    // MARK: - Payment Method Row (flat, no container)

    private var paymentMethodRow: some View {
        Button {
            showPaymentPicker = true
        } label: {
            HStack(spacing: TallySpacing.md) {
                if let selected = viewModel.selectedPaymentMethod {
                    Image(systemName: selected.icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TallyColors.accent)

                    Text(selected.displayLabel)
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(TallyColors.textPrimary)
                        .lineLimit(1)
                } else {
                    Image(systemName: "creditcard")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(TallyColors.textSecondary)

                    Text("Select payment method")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(TallyColors.textTertiary)
            }
            .padding(.vertical, TallySpacing.lg)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showPaymentPicker) {
            PaymentMethodPickerSheet(
                methods: viewModel.paymentMethods,
                selected: viewModel.selectedPaymentMethod
            ) { method in
                viewModel.selectPaymentMethod(method)
                showPaymentPicker = false
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Manual Entry

    private var manualEntry: some View {
        VStack(spacing: TallySpacing.xl) {
            // Hero amount display
            Text(formattedAmount)
                .font(TallyFont.heroAmount)
                .foregroundStyle(TallyColors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, TallySpacing.lg)

            // Number pad
            numberPad
        }
    }

    // MARK: - Scan Section

    private var scanSection: some View {
        VStack(spacing: TallySpacing.lg) {
            if viewModel.isScanning {
                VStack(spacing: TallySpacing.md) {
                    Spacer().frame(height: TallySpacing.xxxl)
                    ProgressView()
                        .tint(TallyColors.textSecondary)
                    Text("Processing receipt...")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                    Spacer().frame(height: TallySpacing.xxxl)
                }
                .frame(maxWidth: .infinity)
            } else if let receipt = viewModel.receipt {
                VStack(spacing: TallySpacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(TallyColors.statusSuccess)

                    Text("Receipt scanned")
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(TallyColors.textPrimary)

                    Text("\(receipt.items.count) items \u{2022} \(CentsFormatter.format(receipt.totalCents))")
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)

                    Button("Scan again") {
                        viewModel.receipt = nil
                        viewModel.scanError = nil
                    }
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.accent)
                    .padding(.top, TallySpacing.sm)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, TallySpacing.xl)
            } else {
                VStack(spacing: TallySpacing.lg) {
                    if let scanErr = viewModel.scanError {
                        Text(scanErr)
                            .font(TallyFont.caption)
                            .foregroundStyle(TallyColors.statusAlert)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        showScanner = true
                    } label: {
                        HStack(spacing: TallySpacing.md) {
                            Image(systemName: "camera")
                                .font(.system(size: 20, weight: .medium))
                            Text("Scan with camera")
                                .font(TallyFont.bodySemibold)
                        }
                        .foregroundStyle(TallyColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(TallyColors.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
                    }
                    .buttonStyle(.plain)

                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack(spacing: TallySpacing.md) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 20, weight: .medium))
                            Text("Upload from Photos")
                                .font(TallyFont.bodySemibold)
                        }
                        .foregroundStyle(TallyColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(TallyColors.bgSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Number Pad

    private var numberPad: some View {
        let keys: [[NumPadKey]] = [
            [.digit("1"), .digit("2"), .digit("3")],
            [.digit("4"), .digit("5"), .digit("6")],
            [.digit("7"), .digit("8"), .digit("9")],
            [.dot, .digit("0"), .backspace],
        ]

        return VStack(spacing: TallySpacing.md) {
            ForEach(0..<keys.count, id: \.self) { row in
                HStack(spacing: TallySpacing.md) {
                    ForEach(keys[row]) { key in
                        NumPadButton(key: key) {
                            handleKey(key)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Amount Formatting

    private var formattedAmount: String {
        CentsFormatter.format(viewModel.manualAmountCents)
    }

    // MARK: - Key Handling

    private func handleKey(_ key: NumPadKey) {
        switch key {
        case .digit(let d):
            guard amountString.count < 10 else { return }
            amountString.append(d)
            syncCents()

        case .dot:
            guard !amountString.contains(".") else { return }
            if amountString.isEmpty { amountString = "0" }
            amountString.append(".")

        case .backspace:
            guard !amountString.isEmpty else { return }
            amountString.removeLast()
            syncCents()
        }
    }

    private func syncCents() {
        let cleaned = amountString.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if let value = Double(cleaned.isEmpty ? "0" : amountString) {
            viewModel.manualAmountCents = Int64((value * 100).rounded())
        } else {
            viewModel.manualAmountCents = 0
        }
    }
}

// MARK: - NumPad Key Model

private enum NumPadKey: Identifiable {
    case digit(String)
    case dot
    case backspace

    var id: String {
        switch self {
        case .digit(let d): "digit_\(d)"
        case .dot:          "dot"
        case .backspace:    "backspace"
        }
    }
}

// MARK: - NumPad Button

private struct NumPadButton: View {
    let key: NumPadKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                switch key {
                case .digit(let d):
                    Text(d)
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textPrimary)

                case .dot:
                    Text(".")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textPrimary)

                case .backspace:
                    Image(systemName: "delete.left")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(TallyColors.textPrimary)
                }
            }
            .frame(width: 72, height: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Payment Method Picker Sheet

private struct PaymentMethodPickerSheet: View {
    let methods: [PaymentMethod]
    let selected: PaymentMethod?
    let onSelect: (PaymentMethod) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Payment method")
                .font(TallyFont.title)
                .foregroundStyle(TallyColors.textPrimary)
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.top, TallySpacing.xl)
                .padding(.bottom, TallySpacing.lg)

            ForEach(methods) { method in
                Button {
                    onSelect(method)
                } label: {
                    HStack(spacing: TallySpacing.md) {
                        Image(systemName: method.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(TallyColors.textPrimary)
                            .frame(width: 28)

                        Text(method.displayLabel)
                            .font(TallyFont.body)
                            .foregroundStyle(TallyColors.textPrimary)

                        Spacer()

                        if method == selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(TallyColors.accent)
                        }
                    }
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .frame(minHeight: TallySpacing.listItemMinHeight)
                }
                .buttonStyle(.plain)

                Rectangle()
                    .fill(TallyColors.divider)
                    .frame(height: 1)
                    .padding(.leading, TallySpacing.screenPadding + 28 + TallySpacing.md)
            }

            Spacer()
        }
        .background(TallyColors.bgPrimary)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        PayReceiptEntryView(viewModel: {
            let vm = PayFlowViewModel()
            vm.manualAmountCents = 4250
            return vm
        }())
    }
}

#Preview("Empty") {
    NavigationStack {
        PayReceiptEntryView(viewModel: PayFlowViewModel())
    }
}

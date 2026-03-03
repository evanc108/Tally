import SwiftUI

enum IDSide {
    case front, back

    var title: String {
        switch self {
        case .front: return "Scan the front of your ID"
        case .back: return "Now flip to the back"
        }
    }

    var subtitle: String {
        switch self {
        case .front: return "Position your driver's license within the frame.\nKeep it flat and well-lit."
        case .back: return "Turn your ID over and position the back within\nthe frame."
        }
    }

    var placeholderText: String {
        switch self {
        case .front: return "Position ID here"
        case .back: return "Position back of ID here"
        }
    }

    var placeholderSubtext: String {
        switch self {
        case .front: return "Auto-capture when aligned"
        case .back: return "Include the barcode"
        }
    }

    var tipText: String {
        switch self {
        case .front: return "Make sure all text is readable and edges are visible. Avoid glare and shadows."
        case .back: return "Ensure the barcode and magnetic stripe are clearly visible for accurate scanning."
        }
    }
}

struct ScanIDView: View {
    let side: IDSide
    let idType: IDType
    let onCapture: () -> Void
    let onBack: () -> Void

    @State private var isCapturing = false
    @State private var captureProgress: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            VerificationNavBar(title: nil, onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: TallySpacing.lg)

                    // Side indicator pills
                    HStack(spacing: TallySpacing.sm) {
                        SidePill(label: "Front side", isActive: side == .front)
                        if idType.requiresBack {
                            SidePill(label: "Back side", isActive: side == .back)
                        }
                    }

                    Spacer().frame(height: TallySpacing.xxl)

                    Text(side.title)
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(side.subtitle)
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.top, TallySpacing.sm)

                    Spacer().frame(height: TallySpacing.xxxl)

                    // Camera frame placeholder
                    IDFramePlaceholder(side: side)
                        .padding(.horizontal, TallySpacing.screenPadding)

                    Spacer().frame(height: TallySpacing.xxxl)

                    // Capture button
                    Button {
                        simulateCapture()
                    } label: {
                        ZStack {
                            Circle()
                                .stroke(TallyColors.accent, lineWidth: 4)
                                .frame(width: 72, height: 72)

                            if isCapturing {
                                Circle()
                                    .trim(from: 0, to: captureProgress)
                                    .stroke(TallyColors.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .frame(width: 72, height: 72)
                                    .rotationEffect(.degrees(-90))
                            }

                            Circle()
                                .fill(TallyColors.accent)
                                .frame(width: 56, height: 56)
                        }
                    }
                    .disabled(isCapturing)

                    Spacer().frame(height: TallySpacing.xxl)

                    // Tip
                    HStack(spacing: TallySpacing.sm) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(TallyColors.textTertiary)
                        Text(side.tipText)
                            .font(TallyFont.small)
                            .foregroundStyle(TallyColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, TallySpacing.screenPadding)
                }
            }
        }
        .background(TallyColors.white)
    }

    private func simulateCapture() {
        isCapturing = true
        captureProgress = 0

        withAnimation(.linear(duration: 1.5)) {
            captureProgress = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isCapturing = false
            onCapture()
        }
    }
}

// MARK: - Side Pill

private struct SidePill: View {
    let label: String
    let isActive: Bool

    var body: some View {
        Text(label)
            .font(TallyFont.caption)
            .foregroundStyle(isActive ? .white : TallyColors.textTertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(isActive ? TallyColors.accent : TallyColors.bgSecondary)
            .clipShape(Capsule())
    }
}

// MARK: - ID Frame Placeholder

private struct IDFramePlaceholder: View {
    let side: IDSide

    var body: some View {
        VStack(spacing: TallySpacing.md) {
            Image(systemName: side == .front ? "rectangle.portrait" : "barcode.viewfinder")
                .font(.system(size: 36))
                .foregroundStyle(TallyColors.textPlaceholder)

            VStack(spacing: 4) {
                Text(side.placeholderText)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textSecondary)
                Text(side.placeholderSubtext)
                    .font(TallyFont.small)
                    .foregroundStyle(TallyColors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
        .background(TallyColors.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: TallyRadius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: TallyRadius.lg)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .foregroundStyle(TallyColors.border)
        )
    }
}

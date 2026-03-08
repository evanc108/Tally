import SwiftUI

struct SelectIDTypeView: View {
    @Binding var selectedType: IDType
    let onContinue: () -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VerificationNavBar(title: nil, onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: TallySpacing.xxl)

                    Text("Choose your ID type")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.horizontal, TallySpacing.screenPadding)

                    Text("Select the government-issued document you'd\nlike to use for verification.")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.textSecondary)
                        .lineSpacing(3)
                        .padding(.top, TallySpacing.sm)
                        .padding(.horizontal, TallySpacing.screenPadding)

                    Spacer().frame(height: TallySpacing.xxl)

                    VStack(spacing: TallySpacing.md) {
                        ForEach(IDType.allCases) { type in
                            IDTypeRow(
                                type: type,
                                isSelected: selectedType == type
                            ) {
                                withAnimation(.spring(duration: 0.25)) {
                                    selectedType = type
                                }
                            }
                        }
                    }
                    .padding(.horizontal, TallySpacing.screenPadding)
                }
            }

            VStack(spacing: TallySpacing.md) {
                Button("Continue") {
                    onContinue()
                }
                .buttonStyle(TallyPrimaryButtonStyle())

                PoweredByStripe()
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.bottom, TallySpacing.xxl)
        }
        .background(TallyColors.white)
    }
}

// MARK: - ID Type Row

private struct IDTypeRow: View {
    let type: IDType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TallySpacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: TallyRadius.md)
                        .fill(isSelected ? TallyColors.accentLight : TallyColors.bgSecondary)
                        .frame(width: 44, height: 44)
                    Image(systemName: type.icon)
                        .font(TallyIcon.lg)
                        .foregroundStyle(isSelected ? TallyColors.accent : TallyColors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(type.rawValue)
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(TallyColors.textPrimary)
                    Text(type.subtitle)
                        .font(TallyFont.small)
                        .foregroundStyle(TallyColors.textSecondary)
                }

                Spacer()

                // Radio indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? TallyColors.accent : TallyColors.border, lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(TallyColors.accent)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(TallySpacing.lg)
            .background(TallyColors.white)
            .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                    .stroke(isSelected ? TallyColors.accent : TallyColors.border, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

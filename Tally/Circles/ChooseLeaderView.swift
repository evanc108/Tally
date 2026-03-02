import SwiftUI

struct ChooseLeaderView: View {
    @Bindable var state: CreateCircleState
    var onContinue: () -> Void

    @State private var showInfoSheet = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Title
                    Text("Who's the backup?")
                        .font(TallyFont.largeTitle)
                        .foregroundStyle(TallyColors.textPrimary)
                        .padding(.top, TallySpacing.sm)

                    // Description
                    Text("If someone's short at the register, the backup covers the gap. They get paid back through the app.")
                        .font(.system(size: 15))
                        .foregroundStyle(TallyColors.textSecondary)
                        .lineSpacing(4)
                        .padding(.top, TallySpacing.sm)

                    // Learn more
                    Button {
                        showInfoSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                            Text("Learn more")
                                .font(.system(size: 15))
                        }
                        .foregroundStyle(TallyColors.accent)
                    }
                    .padding(.top, TallySpacing.sm)

                    // Member cards
                    VStack(spacing: TallySpacing.sm) {
                        LeaderCard(
                            name: "You",
                            initial: "Y",
                            color: TallyColors.accent,
                            isCreator: true,
                            isSelected: state.leaderId == nil
                        ) {
                            withAnimation(.spring(response: 0.3)) { state.leaderId = nil }
                        }

                        ForEach(state.members) { member in
                            LeaderCard(
                                name: member.name,
                                initial: member.initial,
                                color: member.color,
                                isCreator: false,
                                isSelected: state.leaderId == member.id
                            ) {
                                withAnimation(.spring(response: 0.3)) { state.leaderId = member.id }
                            }
                        }
                    }
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
        .sheet(isPresented: $showInfoSheet) {
            LeaderInfoSheet()
                .presentationDetents([.medium])
        }
    }
}

// MARK: - Leader Card

private struct LeaderCard: View {
    let name: String
    let initial: String
    let color: Color
    let isCreator: Bool
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: TallySpacing.lg) {
                // Avatar with shield badge
                ZStack(alignment: .bottomTrailing) {
                    Text(initial)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(
                            LinearGradient(
                                colors: [TallyColors.accent, TallyColors.statusSocial],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .clipShape(Circle())

                    if isCreator {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(TallyColors.accent)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(TallyColors.bgSecondary, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: TallySpacing.xs) {
                        Text(name)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(TallyColors.textPrimary)
                        if isCreator {
                            Text("Creator")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(TallyColors.textSecondary)
                        }
                    }
                }

                Spacer()

                // Radio
                ZStack {
                    Circle()
                        .stroke(isSelected ? TallyColors.accent : TallyColors.divider, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    if isSelected {
                        Circle()
                            .fill(TallyColors.accent)
                            .frame(width: 24, height: 24)
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(TallySpacing.lg)
            .background(isSelected ? TallyColors.accent.opacity(0.06) : TallyColors.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? TallyColors.accent.opacity(0.3) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Leader Info Sheet

private struct LeaderInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: TallySpacing.lg) {
                Text("Leader Cover")
                    .font(TallyFont.title)
                    .foregroundStyle(TallyColors.textPrimary)

                Text("When a Tally card is swiped, every member's balance is checked instantly. If one member can't cover their share, the **backup leader's** account automatically covers the gap.")
                    .font(.system(size: 15))
                    .foregroundStyle(TallyColors.textPrimary)
                    .lineSpacing(4)

                HStack(spacing: 0) {
                    Text("This creates a ")
                        .font(.system(size: 15))
                        .foregroundStyle(TallyColors.textPrimary)
                    Text("social debt")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(TallyColors.statusSocial)
                    Text(" — not a real charge. The member owes the leader and can settle it through the app whenever they're ready.")
                        .font(.system(size: 15))
                        .foregroundStyle(TallyColors.textPrimary)
                }
                .lineSpacing(4)

                Text("The card never declines because of one person. The group always completes the purchase.")
                    .font(.system(size: 15))
                    .foregroundStyle(TallyColors.textSecondary)
                    .lineSpacing(4)

                Spacer()
            }
            .padding(TallySpacing.xl)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Got it") { dismiss() }
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(TallyColors.accent)
                }
            }
        }
    }
}

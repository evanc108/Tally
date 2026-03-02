import SwiftUI

/// Illustration for onboarding page 2: "Track every expense"
/// Shows a card with recent expenses.
struct OnboardingTrackExpenseView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENT EXPENSES")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TallyColors.textSecondary)
                .tracking(0.5)
                .padding(.bottom, TallySpacing.lg)

            ExpenseRowView(
                icon: "A",
                iconColor: .purple,
                name: "Dinner",
                paidBy: "Sarah paid",
                amount: "$86.40"
            )

            Divider()
                .padding(.vertical, TallySpacing.md)

            ExpenseRowView(
                icon: "B",
                iconColor: TallyColors.accent,
                name: "Groceries",
                paidBy: "You paid",
                amount: "$42.15"
            )

            Divider()
                .padding(.vertical, TallySpacing.md)

            ExpenseRowView(
                icon: "C",
                iconColor: .blue,
                name: "Uber",
                paidBy: "Alex paid",
                amount: "$24.80"
            )
        }
        .padding(TallySpacing.cardPadding + 4)
        .background(
            RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                .fill(.white)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
        .padding(.horizontal, TallySpacing.xxl)
    }
}

#Preview {
    OnboardingTrackExpenseView()
        .padding()
        .background(Color(hex: 0xF2F2F7))
}

import SwiftUI

struct ExpenseRowView: View {
    let icon: String
    let iconColor: Color
    let name: String
    let paidBy: String
    let amount: String

    var body: some View {
        HStack(spacing: TallySpacing.md) {
            // Icon
            Text(icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(iconColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Name + paid by
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textPrimary)
                Text(paidBy)
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
            }

            Spacer()

            // Amount
            Text(amount)
                .font(TallyFont.amounts)
                .foregroundStyle(TallyColors.textPrimary)
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ExpenseRowView(icon: "A", iconColor: .purple, name: "Dinner", paidBy: "Sarah paid", amount: "$86.40")
        ExpenseRowView(icon: "B", iconColor: .green, name: "Groceries", paidBy: "You paid", amount: "$42.15")
    }
    .padding()
}

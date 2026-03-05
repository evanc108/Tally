import SwiftUI


struct CircleFeedView: View {
    let circleID: UUID
    var viewModel: CirclesViewModel
    private let fallback: TallyCircle

    private var circle: TallyCircle {
        viewModel.circles.first(where: { $0.id == circleID }) ?? fallback
    }

    init(circle: TallyCircle, viewModel: CirclesViewModel) {
        self.circleID = circle.id
        self.viewModel = viewModel
        self.fallback = circle
    }

    @Environment(\.dismiss) private var navDismiss
    @State private var showSettings = false
    @State private var showAddMoney = false
    @State private var showSettleUp = false
    @State private var shouldCloseCircle = false
    @State private var isClosing = false
    @State private var closeError: String?
    @State private var showPayFlow = false

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            heroCard
            ScrollView {
                VStack(spacing: 0) {
                    membersSection
                    rule
                    activitySection
                }
                .padding(.bottom, 100)
            }
            .background(TallyColors.bgPrimary)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .background(NavBarConfigurator(color: UIColor(TallyColors.accent)))
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(circle.name)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(.white)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
        .sheet(isPresented: $showSettings, onDismiss: {
            if shouldCloseCircle {
                shouldCloseCircle = false
                Task {
                    isClosing = true
                    await viewModel.closeCircle(circle)
                    navDismiss()
                }
            }
        }) {
            CircleSettingsSheet(circle: circle, viewModel: viewModel) {
                shouldCloseCircle = true
            }
        }
        .sheet(isPresented: $showAddMoney) { AddMoneySheet() }
        .sheet(isPresented: $showSettleUp) { SettleUpSheet(circle: circle) }
        .fullScreenCover(isPresented: $showPayFlow, onDismiss: {
            Task { await viewModel.fetchCircleDetail(for: circle) }
        }) {
            PayFlowView(preselectedCircle: circle, availableCircles: viewModel.circles)
        }
        .task {
            await viewModel.fetchCircleDetail(for: circle)
        }
        .overlay {
            if isClosing {
                ZStack {
                    Color.black.opacity(0.3)
                    ProgressView("Closing circle...")
                        .padding(TallySpacing.xl)
                        .background(TallyColors.bgPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius))
                }
                .ignoresSafeArea()
            }
        }
        .alert("Error", isPresented: .init(
            get: { closeError != nil },
            set: { if !$0 { closeError = nil } }
        )) {
            Button("OK") { closeError = nil }
        } message: {
            Text(closeError ?? "Failed to close circle.")
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        ZStack {
            LinearGradient(
                colors: [TallyColors.accent, TallyColors.accentDark],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 0) {
                // ── Tally brand ───────────────────────────────────────────
                HStack {
                    Spacer()
                    Text("tally")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.top, TallySpacing.md)

                Spacer()

                // ── Balance block (centered) ──────────────────────────────
                VStack(spacing: 4) {
                    Text("AVAILABLE BALANCE")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .kerning(1.5)

                    Text(String(format: "$%.0f", circle.walletBalance))
                        .font(.system(size: 52, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)

                    if todaysDelta > 0 {
                        Text(String(format: "+$%.0f today", todaysDelta))
                            .font(TallyFont.caption)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer()

                // ── Action buttons inside card ────────────────────────────
                actionButtonRow

                // ── Card number ───────────────────────────────────────────
                HStack {
                    Text("•••• \(circle.myCardLastFour ?? "0000")")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.bottom, TallySpacing.lg)
            }
        }
        .containerRelativeFrame(.vertical, count: 3, span: 1, spacing: 0)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 24,
            bottomTrailingRadius: 24,
            topTrailingRadius: 0
        ))
    }

    // MARK: - Action Buttons

    private var actionButtonRow: some View {
        HStack(spacing: 0) {
            Spacer()
            circleActionButton(icon: "dollarsign", label: "Pay", color: .white.opacity(0.25)) {
                showPayFlow = true
            }
            Spacer()
            circleActionButton(icon: "plus", label: "Add\nMoney", color: .white.opacity(0.25)) {
                showAddMoney = true
            }
            Spacer()
            circleActionButton(icon: "arrow.left.arrow.right", label: "Settle\nUp", color: .white.opacity(0.25)) {
                showSettleUp = true
            }
            Spacer()
            circleActionButton(icon: "list.bullet.rectangle", label: "Ledger", color: .white.opacity(0.25)) {}
            Spacer()
        }
        .padding(.vertical, TallySpacing.sm)
    }

    private func circleActionButton(icon: String, label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(color, in: Circle())
                Text(label)
                    .font(TallyFont.smallLabel)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private var todaysDelta: Double {
        circle.transactions
            .filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    private var rule: some View {
        Rectangle()
            .fill(TallyColors.divider)
            .frame(height: 1)
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            HStack {
                Text("Members")
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                Text("· \(circle.memberCount)")
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textSecondary)
                Spacer()
                Button("Invite +") { showSettings = true }
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.accent)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TallySpacing.lg) {
                    MemberPill(initial: "Y", name: "You",
                               color: TallyColors.accent, isLeader: circle.leaderId == nil)
                    ForEach(circle.members) { member in
                        MemberPill(
                            initial: member.initial,
                            name: member.name.split(separator: " ").first.map(String.init) ?? member.name,
                            color: member.color,
                            isLeader: circle.leaderId == member.id
                        )
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.vertical, TallySpacing.lg)
    }

    // MARK: - Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Activity")
                .font(TallyFont.bodySemibold)
                .foregroundStyle(TallyColors.textPrimary)
                .padding(.horizontal, TallySpacing.screenPadding)
                .padding(.top, TallySpacing.lg)
                .padding(.bottom, TallySpacing.md)

            if circle.transactions.isEmpty {
                VStack(spacing: TallySpacing.md) {
                    Text("🧾")
                        .font(.system(size: 44))
                    Text("No transactions yet")
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(TallyColors.textPrimary)
                    Text("Tap Add Money to fund your circle,\nor record your first shared expense.")
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, TallySpacing.xxl)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, TallySpacing.xxxl)
            } else {
                ForEach(groupedTransactions, id: \.label) { group in
                    Text(group.label.uppercased())
                        .font(TallyFont.smallLabel)
                        .foregroundStyle(TallyColors.textSecondary)
                        .kerning(0.5)
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.top, TallySpacing.lg)
                        .padding(.bottom, TallySpacing.xs)

                    ForEach(Array(group.transactions.enumerated()), id: \.element.id) { idx, tx in
                        FeedTransactionRow(tx: tx, colorIndex: idx)
                        if idx < group.transactions.count - 1 {
                            Divider()
                                .padding(.leading, TallySpacing.lg + 48 + TallySpacing.md)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Grouping

    private struct DateGroup { let label: String; let transactions: [CircleTransaction] }

    private var groupedTransactions: [DateGroup] {
        let cal = Calendar.current
        var buckets: [(key: Date, txs: [CircleTransaction])] = []
        for tx in circle.transactions.sorted(by: { $0.date > $1.date }) {
            let day = cal.startOfDay(for: tx.date)
            if let i = buckets.firstIndex(where: { cal.isDate($0.key, inSameDayAs: day) }) {
                buckets[i].txs.append(tx)
            } else { buckets.append((day, [tx])) }
        }
        return buckets.map { b in
            let label: String
            if cal.isDateInToday(b.key) { label = "Today" }
            else if cal.isDateInYesterday(b.key) { label = "Yesterday" }
            else { let f = DateFormatter(); f.dateFormat = "MMMM d"; label = f.string(from: b.key) }
            return DateGroup(label: label, transactions: b.txs)
        }
    }
}

// MARK: - Member Pill

private struct MemberPill: View {
    let initial: String
    let name: String
    let color: Color
    let isLeader: Bool

    var body: some View {
        VStack(spacing: TallySpacing.xs) {
            ZStack(alignment: .bottomTrailing) {
                Text(initial)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(color)
                    .clipShape(Circle())

                if isLeader {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(TallyColors.accent)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(TallyColors.bgPrimary, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }
            }
            Text(name)
                .font(TallyFont.smallLabel)
                .foregroundStyle(TallyColors.textSecondary)
                .lineLimit(1)
                .frame(width: 56)
        }
    }
}

// MARK: - Flat Transaction Row

private struct FeedTransactionRow: View {
    let tx: CircleTransaction
    let colorIndex: Int

    var body: some View {
        HStack(spacing: TallySpacing.md) {
            Text(tx.emoji)
                .font(.system(size: 22))
                .frame(width: 48, height: 48)
                .background(TallyColors.cardColor(for: colorIndex))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(tx.title)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                Text("paid by \(tx.paidBy)")
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 3) {
                Text(String(format: "$%.2f", tx.amount))
                    .font(TallyFont.amounts)
                    .foregroundStyle(TallyColors.textPrimary)
                Text(tx.status.label)
                    .font(TallyFont.smallLabel)
                    .foregroundStyle(tx.status.color)
            }
        }
        .padding(.horizontal, TallySpacing.lg)
        .padding(.vertical, TallySpacing.md)
        .background(TallyColors.bgPrimary)
    }
}

// MARK: - Circle Settings Sheet

struct CircleSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var circle: TallyCircle
    var viewModel: CirclesViewModel
    var onCloseCircle: () -> Void = {}

    @State private var circleName: String
    @State private var selectedSplit: SplitMethod
    @State private var autoSettle = true
    @State private var transactionNotifications = true
    @State private var showCloseConfirm = false

    init(circle: TallyCircle, viewModel: CirclesViewModel, onCloseCircle: @escaping () -> Void = {}) {
        self.circle = circle
        self.viewModel = viewModel
        self._circleName = State(initialValue: circle.name)
        self._selectedSplit = State(initialValue: circle.splitMethod)
        self.onCloseCircle = onCloseCircle
    }

    private var hasChanges: Bool {
        circleName.trimmingCharacters(in: .whitespaces) != circle.name ||
        selectedSplit != circle.splitMethod
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // ── Circle name ─────────────────────────────────────────
                    HStack {
                        TextField("Circle name", text: $circleName)
                            .font(TallyFont.titleSemibold)
                            .foregroundStyle(TallyColors.textPrimary)
                        Spacer()
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(TallyColors.textSecondary)
                    }
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.top, TallySpacing.lg)
                    .padding(.bottom, TallySpacing.xl)

                    Divider()

                    // ── Split Mode ───────────────────────────────────────────
                    Text("SPLIT MODE")
                        .font(TallyFont.smallLabel)
                        .foregroundStyle(TallyColors.textSecondary)
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.top, TallySpacing.xl)
                        .padding(.bottom, TallySpacing.sm)

                    VStack(spacing: TallySpacing.sm) {
                        splitModeCard(
                            method: .equal,
                            icon: "equal.circle.fill",
                            title: "Equal",
                            subtitle: "Split evenly among all members"
                        )
                        splitModeCard(
                            method: .custom,
                            icon: "slider.horizontal.3",
                            title: "Custom",
                            subtitle: "Set specific amounts per member"
                        )
                        splitModeCard(
                            method: .percentage,
                            icon: "percent",
                            title: "Percentage",
                            subtitle: "Split by percentage"
                        )
                    }
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.bottom, TallySpacing.xl)

                    Divider()

                    // ── Toggles ──────────────────────────────────────────────
                    toggleRow(
                        title: "Auto-settle",
                        subtitle: "Automatically split after grace period",
                        isOn: $autoSettle
                    )

                    Divider()

                    toggleRow(
                        title: "Transaction notifications",
                        subtitle: "Get notified for every transaction",
                        isOn: $transactionNotifications
                    )

                    Divider()

                    // ── Grace period ─────────────────────────────────────────
                    Button {} label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Grace period")
                                    .font(TallyFont.bodySemibold)
                                    .foregroundStyle(TallyColors.textPrimary)
                                Text("Time for members to review charges")
                                    .font(TallyFont.caption)
                                    .foregroundStyle(TallyColors.textSecondary)
                            }
                            Spacer()
                            HStack(spacing: TallySpacing.xs) {
                                Text("24 hours")
                                    .font(TallyFont.body)
                                    .foregroundStyle(TallyColors.textSecondary)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(TallyColors.textTertiary)
                            }
                        }
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.vertical, TallySpacing.lg)
                    }
                    .buttonStyle(.plain)

                    Divider()

                    // ── Actions ──────────────────────────────────────────────
                    settingsActionRow(icon: "person.badge.plus", label: "Invite member") {}
                    Divider().padding(.leading, TallySpacing.screenPadding + 32 + TallySpacing.md)
                    settingsActionRow(icon: "shield.lefthalf.filled", label: "Reassign backup leader") {}
                    Divider().padding(.leading, TallySpacing.screenPadding + 32 + TallySpacing.md)
                    settingsActionRow(icon: "snowflake", label: "Freeze card") {}

                    Divider()
                        .padding(.top, TallySpacing.sm)

                    // ── Close Circle ─────────────────────────────────────────
                    Button { showCloseConfirm = true } label: {
                        HStack(spacing: TallySpacing.md) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 22))
                                .foregroundStyle(TallyColors.statusAlert)
                            Text("Close Circle")
                                .font(TallyFont.bodySemibold)
                                .foregroundStyle(TallyColors.statusAlert)
                            Spacer()
                        }
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.vertical, TallySpacing.lg)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, TallySpacing.xxxl)
            }
            .background(TallyColors.bgPrimary)
            .navigationTitle("Circle Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        if hasChanges {
                            let newName = circleName.trimmingCharacters(in: .whitespaces)
                            let nameChange = newName != circle.name ? newName : nil
                            let splitChange = selectedSplit != circle.splitMethod ? selectedSplit : nil
                            Task {
                                await viewModel.updateCircle(circle, name: nameChange, splitMethod: splitChange)
                            }
                        }
                        dismiss()
                    }
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.accent)
                }
            }
            .confirmationDialog("Close \(circle.name)?", isPresented: $showCloseConfirm,
                                titleVisibility: .visible) {
                Button("Close Circle", role: .destructive) {
                    onCloseCircle()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will settle all remaining balances and permanently close the circle.")
            }
        }
    }

    // MARK: - Split Mode Card

    private func splitModeCard(method: SplitMethod, icon: String, title: String, subtitle: String) -> some View {
        let isSelected = selectedSplit == method
        return Button {
            withAnimation(.spring(response: 0.25)) {
                selectedSplit = method
            }
        } label: {
            HStack(spacing: TallySpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isSelected ? TallyColors.accent : TallyColors.textSecondary)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(TallyColors.textPrimary)
                    Text(subtitle)
                        .font(TallyFont.caption)
                        .foregroundStyle(TallyColors.textSecondary)
                }

                Spacer()
            }
            .padding(.horizontal, TallySpacing.lg)
            .padding(.vertical, TallySpacing.md)
            .background(
                RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                    .fill(isSelected ? TallyColors.accent.opacity(0.08) : TallyColors.bgPrimary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: TallySpacing.cardCornerRadius)
                    .stroke(isSelected ? TallyColors.accent : TallyColors.divider, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Toggle Row

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                Text(subtitle)
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .tint(TallyColors.accent)
                .labelsHidden()
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.vertical, TallySpacing.lg)
    }

    // MARK: - Action Row

    private func settingsActionRow(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: TallySpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(TallyColors.textSecondary)
                    .frame(width: 32, height: 32)
                Text(label)
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(TallyColors.textTertiary)
            }
            .padding(.horizontal, TallySpacing.screenPadding)
            .padding(.vertical, TallySpacing.lg)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Money Sheet

private struct AddMoneySheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(spacing: TallySpacing.xl) {
                Spacer()
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 64)).foregroundStyle(TallyColors.accent)
                VStack(spacing: TallySpacing.sm) {
                    Text("Add Money").font(TallyFont.title).foregroundStyle(TallyColors.textPrimary)
                    Text("Connect your bank to fund\nthe circle wallet.")
                        .font(TallyFont.body).foregroundStyle(TallyColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Button("Connect Bank") {}
                    .buttonStyle(TallyPrimaryButtonStyle())
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.bottom, TallySpacing.xxxl)
            }
            .navigationTitle("Add Money").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Cancel") { dismiss() }.foregroundStyle(TallyColors.accent)
            }}
        }
    }
}

// MARK: - Settle Up Sheet

private struct SettleUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    var circle: TallyCircle
    var body: some View {
        NavigationStack {
            VStack(spacing: TallySpacing.xl) {
                Spacer()
                Image(systemName: "arrow.left.arrow.right.circle.fill")
                    .font(.system(size: 64)).foregroundStyle(TallyColors.statusSocial)
                VStack(spacing: TallySpacing.sm) {
                    Text("Settle Up").font(TallyFont.title).foregroundStyle(TallyColors.textPrimary)
                    Text("Clear pending balances with\nyour group members.")
                        .font(TallyFont.body).foregroundStyle(TallyColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Spacer()
                Button("Settle All Balances") {}
                    .buttonStyle(TallyPrimaryButtonStyle())
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.bottom, TallySpacing.xxxl)
            }
            .navigationTitle("Settle Up").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) {
                Button("Cancel") { dismiss() }.foregroundStyle(TallyColors.accent)
            }}
        }
    }
}

// MARK: - Navigation Bar Color (UIKit bridge)

/// Accesses the actual UINavigationController to set the bar appearance directly.
/// Unlike UINavigationBar.appearance() (a proxy that only affects new instances),
/// this targets the live navigation bar — so the color always applies.
private struct NavBarConfigurator: UIViewControllerRepresentable {
    let color: UIColor

    func makeUIViewController(context: Context) -> UIViewController {
        let vc = NavBarConfiguratorVC(color: color)
        return vc
    }

    func updateUIViewController(_ vc: UIViewController, context: Context) {}
}

private class NavBarConfiguratorVC: UIViewController {
    let color: UIColor

    init(color: UIColor) {
        self.color = color
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyAppearance()
    }

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        applyAppearance()
    }

    private func applyAppearance() {
        guard let nav = navigationController else { return }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = color
        appearance.shadowColor = .clear
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let nav = navigationController else { return }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        nav.navigationBar.standardAppearance = appearance
        nav.navigationBar.scrollEdgeAppearance = appearance
        nav.navigationBar.compactAppearance = appearance
    }
}

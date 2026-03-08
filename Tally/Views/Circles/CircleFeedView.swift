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
    @State private var showScanModal = false
    @State private var payFlowVM: PayFlowViewModel? = nil
    @State private var scrollOffset: CGFloat = 0

    /// Header opacity: fades as user scrolls
    private var headerOpacity: Double {
        let fadeStart: CGFloat = 40
        let fadeEnd: CGFloat = 120
        if scrollOffset <= fadeStart { return 1 }
        if scrollOffset >= fadeEnd { return 0 }
        return Double(1 - (scrollOffset - fadeStart) / (fadeEnd - fadeStart))
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 56) // space for floating header

                    heroCard
                    actionButtonRow
                    membersSection
                    transactionsHeader
                    transactionsList
                }
            }
            .contentMargins(.bottom, 100, for: .scrollContent)
            .onScrollGeometryChange(for: CGFloat.self) { geo in
                geo.contentOffset.y
            } action: { _, newValue in
                scrollOffset = newValue
            }

            // Floating header
            floatingHeader
                .allowsHitTesting(headerOpacity > 0.1)
        }
        .background(Color.white.ignoresSafeArea())
        .navigationBarHidden(true)
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
            if let vm = payFlowVM {
                PayFlowView(preloadedViewModel: vm)
            }
        }
        .task {
            await viewModel.fetchCircleDetail(for: circle)
        }
        .overlay {
            ZStack(alignment: .bottom) {
                if showScanModal {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                showScanModal = false
                            }
                        }
                        .transition(.opacity)
                }

                if showScanModal, let vm = payFlowVM {
                    BillScanPopover(
                        viewModel: vm,
                        onDismiss: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                showScanModal = false
                            }
                        },
                        onScanComplete: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                                showScanModal = false
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                showPayFlow = true
                            }
                        }
                    )
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.bottom, 110)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.45, anchor: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.45, anchor: .bottom).combined(with: .opacity)
                    ))
                }

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

    // MARK: - Floating Header

    private var floatingHeader: some View {
        ZStack {
            Text(circle.name)
                .font(TallyFont.title)
                .foregroundStyle(TallyColors.textPrimary)
                .lineLimit(1)

            HStack {
                GlassNavButton(icon: "chevron.left") { navDismiss() }

                Spacer()

                GlassNavButton(icon: "gearshape") { showSettings = true }
            }
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.top, TallySpacing.sm)
        .padding(.bottom, TallySpacing.sm)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.9), location: 0),
                    .init(color: Color.white.opacity(0.6), location: 0.35),
                    .init(color: Color.white.opacity(0.2), location: 0.7),
                    .init(color: Color.white.opacity(0), location: 1.0),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .opacity(headerOpacity)
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        ZStack {
            LinearGradient(
                colors: [TallyColors.accent, TallyColors.mintLeaf, TallyColors.hunterGreen],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Subtle radial highlight
            RadialGradient(
                colors: [Color.white.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 200
            )

            VStack(spacing: 0) {
                // Tally brand
                HStack {
                    Spacer()
                    Text("tally")
                        .font(TallyFont.brandCardSmall)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.bottom, TallySpacing.md)

                // Balance
                VStack(spacing: 4) {
                    Text("AVAILABLE BALANCE")
                        .font(TallyFont.captionBold)
                        .foregroundStyle(.white.opacity(0.7))
                        .kerning(1.5)

                    Text(String(format: "$%.0f", circle.walletBalance))
                        .font(TallyFont.heroAmount)
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)

                Spacer()

                // Card number
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "wave.3.right")
                            .font(TallyIcon.xxs)
                            .foregroundStyle(.white.opacity(0.6))
                        Text("•••• \(circle.myCardLastFour ?? "0000")")
                            .font(TallyFont.cardNumberSmall)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    Spacer()
                }
            }
            .padding(TallySpacing.lg)
        }
        .frame(height: 200)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        )
        .shadow(color: TallyColors.hunterGreen.opacity(0.15), radius: 6, y: 3)
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.bottom, TallySpacing.lg)
    }

    // MARK: - Action Buttons

    private var actionButtonRow: some View {
        HStack(spacing: TallySpacing.xl) {
            actionCircle(icon: "dollarsign", label: "Pay") {
                let vm = PayFlowViewModel()
                vm.preselectedCircle = circle
                vm.loadCircles(viewModel.circles)
                payFlowVM = vm
                withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
                    showScanModal = true
                }
            }
            actionCircle(icon: "plus", label: "Add") { showAddMoney = true }
            actionCircle(icon: "arrow.left.arrow.right", label: "Settle") { showSettleUp = true }
            actionCircle(icon: "list.bullet.rectangle", label: "Ledger") {}
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.bottom, TallySpacing.xl)
    }

    private func actionCircle(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(TallyIcon.md)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black)
                    .clipShape(Circle())
                    .glassEffect(.regular.interactive(), in: Circle())
                Text(label)
                    .font(TallyFont.smallLabelSemibold)
                    .foregroundStyle(TallyColors.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Members

    private var membersSection: some View {
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            HStack {
                Text("MEMBERS")
                    .font(TallyFont.overline)
                    .foregroundStyle(TallyColors.textSecondary)
                    .tracking(0.5)
                Text("· \(circle.memberCount)")
                    .font(TallyFont.overline)
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
        .padding(.bottom, TallySpacing.xl)
    }

    // MARK: - Transactions Header

    private var transactionsHeader: some View {
        HStack {
            Text("TRANSACTIONS")
                .font(TallyFont.overline)
                .foregroundStyle(TallyColors.textSecondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.bottom, TallySpacing.md)
    }

    // MARK: - Transactions List (HomeTab style)

    private var transactionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if circle.transactions.isEmpty {
                VStack(spacing: TallySpacing.md) {
                    Image(systemName: "tray")
                        .font(TallyIcon.heroLg)
                        .foregroundStyle(TallyColors.textTertiary)
                    Text("No transactions yet")
                        .font(TallyFont.bodySemibold)
                        .foregroundStyle(TallyColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, TallySpacing.xxxl)
            } else {
                ForEach(groupedTransactions, id: \.label) { group in
                    Text(group.label)
                        .font(TallyFont.overline)
                        .foregroundStyle(TallyColors.textSecondary)
                        .tracking(0.3)
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.top, TallySpacing.lg)
                        .padding(.bottom, TallySpacing.sm)

                    // Elevated card container
                    VStack(spacing: 0) {
                        ForEach(Array(group.transactions.enumerated()), id: \.element.id) { idx, tx in
                            FeedTransactionRow(tx: tx, colorIndex: idx)
                            if idx < group.transactions.count - 1 {
                                Divider()
                                    .foregroundStyle(TallyColors.borderLight)
                                    .padding(.leading, 72)
                            }
                        }
                    }
                    .background(TallyColors.bgPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
                    .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                    .padding(.horizontal, TallySpacing.screenPadding)
                }
            }
        }
    }

    // MARK: - Helpers

    private var todaysDelta: Double {
        circle.transactions
            .filter { Calendar.current.isDateInToday($0.date) }
            .reduce(0) { $0 + $1.amount }
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
                    .font(TallyFont.memberInitial)
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(color)
                    .clipShape(Circle())

                if isLeader {
                    Image(systemName: "shield.fill")
                        .font(TallyIcon.xxxs)
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

// MARK: - Transaction Row

private struct FeedTransactionRow: View {
    let tx: CircleTransaction
    let colorIndex: Int

    var body: some View {
        HStack(spacing: TallySpacing.md) {
            Text(tx.emoji)
                .font(TallyIcon.xl)
                .frame(width: 44, height: 44)
                .background(TallyColors.cardColor(for: colorIndex).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 12))

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
                    .font(TallyFont.amountsSmall)
                    .foregroundStyle(TallyColors.textPrimary)
                Text(tx.status.label)
                    .font(TallyFont.smallLabel)
                    .foregroundStyle(tx.status.color)
            }
        }
        .padding(.horizontal, TallySpacing.lg)
        .padding(.vertical, TallySpacing.md)
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
                            .font(TallyIcon.sm)
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
                                    .font(TallyIcon.xs)
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
                                .font(TallyIcon.xxl)
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
                    .font(TallyIcon.xl)
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
                    .font(TallyIcon.md)
                    .foregroundStyle(TallyColors.textSecondary)
                    .frame(width: 32, height: 32)
                Text(label)
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(TallyIcon.xs)
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
                    .font(TallyIcon.mega).foregroundStyle(TallyColors.accent)
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
                    .font(TallyIcon.mega).foregroundStyle(TallyColors.statusSocial)
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

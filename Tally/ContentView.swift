//
//  ContentView.swift
//  Tally
//
//  Created by Evan Chang on 3/1/26.
//

import SwiftUI
import ClerkKit

// MARK: - Scroll Offset Preference

private struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Tab Definition

enum TallyTab: Int, CaseIterable {
    case home, circles, pay, wallet, profile

    var title: String {
        switch self {
        case .home: "Home"
        case .circles: "Circles"
        case .pay: "Pay"
        case .wallet: "Wallet"
        case .profile: "Profile"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .circles: "person.3"
        case .pay: "dollarsign"
        case .wallet: "wallet.bifold"
        case .profile: "person"
        }
    }

    var activeIcon: String {
        switch self {
        case .home: "house.fill"
        case .circles: "person.3.fill"
        case .pay: "dollarsign"
        case .wallet: "wallet.bifold.fill"
        case .profile: "person.fill"
        }
    }
}

// MARK: - Root View

struct ContentView: View {
    @Environment(Clerk.self) private var clerk
    @State private var selectedTab: TallyTab = .home
    @State private var circlesViewModel = CirclesViewModel()
    @State private var showPayFlow = false
    @State private var showScanModal = false
    @State private var payFlowVM: PayFlowViewModel? = nil

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch selectedTab {
                case .home:
                    NavigationStack {
                        HomeTab(circles: circlesViewModel.circles, onCirclesTap: {
                            withAnimation(.snappy(duration: 0.25)) { selectedTab = .circles }
                        })
                            .toolbar(.hidden, for: .navigationBar)
                    }
                case .circles:
                    CirclesTab(viewModel: circlesViewModel)
                case .pay:
                    EmptyView()
                case .wallet:
                    WalletTab(circles: circlesViewModel.circles)
                case .profile:
                    ProfileTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom liquid glass tab bar — pinned to bottom, no gap
            GeometryReader { geo in
                TallyTabBar(selectedTab: $selectedTab, onPayTap: {
                    let vm = PayFlowViewModel()
                    vm.loadCircles(circlesViewModel.circles)
                    payFlowVM = vm
                    showScanModal = true
                })
                .padding(.bottom, geo.safeAreaInsets.bottom)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .opacity(showScanModal ? 0 : 1)
            }
            .frame(height: 120)
            .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
        .ignoresSafeArea(.keyboard)
        .task {
            await circlesViewModel.fetchCircles()
        }
        .fullScreenCover(isPresented: $showPayFlow, onDismiss: {
            Task { await circlesViewModel.fetchCircles(force: true) }
        }) {
            if let vm = payFlowVM {
                PayFlowView(preloadedViewModel: vm)
            }
        }
        .overlay(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                if showScanModal {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showScanModal = false
                        }
                }

                if showScanModal, let vm = payFlowVM {
                    BillScanPopover(
                        viewModel: vm,
                        onDismiss: {
                            showScanModal = false
                        },
                        onScanComplete: {
                            showScanModal = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                showPayFlow = true
                            }
                        }
                    )
                    .padding(.bottom, TallySpacing.sm)
                    .transition(.asymmetric(
                        insertion: .modifier(active: HScaleModifier(scale: 0.05), identity: HScaleModifier(scale: 1)).combined(with: .opacity),
                        removal: .modifier(active: HScaleModifier(scale: 0.05), identity: HScaleModifier(scale: 1)).combined(with: .opacity)
                    ))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

}

// MARK: - Horizontal Scale Transition

private struct HScaleModifier: ViewModifier {
    let scale: CGFloat
    func body(content: Content) -> some View {
        content.scaleEffect(x: scale, y: 1, anchor: .bottom)
    }
}

// MARK: - Custom Liquid Glass Tab Bar

private struct TallyTabBar: View {
    @Binding var selectedTab: TallyTab
    @Environment(Clerk.self) private var clerk
    var onPayTap: () -> Void

    private var userInitials: String {
        let first = clerk.user?.firstName?.prefix(1) ?? ""
        let last = clerk.user?.lastName?.prefix(1) ?? ""
        let result = "\(first)\(last)"
        return result.isEmpty ? "T" : result.uppercased()
    }

    var body: some View {
        HStack(spacing: 0) {
            // Home
            tabButton(for: .home)
            // Circles
            tabButton(for: .circles)
            // Pay — green circle, no label
            Button {
                onPayTap()
            } label: {
                Image(systemName: "dollarsign")
                    .font(TallyIcon.md)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(TallyColors.ink)
                    .clipShape(Circle())
            }
            .frame(maxWidth: .infinity)
            // Wallet
            tabButton(for: .wallet)
            // Profile — user initials or image
            Button {
                selectedTab = .profile
            } label: {
                let isSelected = selectedTab == .profile
                VStack(spacing: 4) {
                    Text(userInitials)
                        .font(TallyFont.avatarSmall)
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(isSelected ? TallyColors.accent : TallyColors.ink.opacity(0.15))
                        .clipShape(Circle())
                    Text("Profile")
                        .font(TallyFont.micro)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .foregroundStyle(isSelected ? TallyColors.ink : TallyColors.ink.opacity(0.55))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, TallySpacing.xs)
                .padding(.horizontal, 4)
            }
        }
        .buttonStyle(TallyTabBarButtonStyle())
        .padding(.horizontal, TallySpacing.sm)
        .padding(.vertical, TallySpacing.sm)
        .glassEffect(.regular, in: Rectangle())
    }

    private func tabButton(for tab: TallyTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            let isSelected = selectedTab == tab
            VStack(spacing: 4) {
                Image(systemName: isSelected ? tab.activeIcon : tab.icon)
                    .font(TallyIcon.xl)
                Text(tab.title)
                    .font(TallyFont.micro)
                    .fontWeight(isSelected ? .semibold : .regular)
            }
            .foregroundStyle(isSelected ? TallyColors.ink : TallyColors.ink.opacity(0.55))
            .frame(maxWidth: .infinity)
            .padding(.vertical, TallySpacing.xs)
            .padding(.horizontal, 4)
        }
    }
}

// Button style that disables the default pressed highlight/scale for tab bar items
private struct TallyTabBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

// MARK: - Activity Models

struct ActivityItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let amount: Double
    let isCredit: Bool
    let date: Date
    let icon: ActivityIcon

    var formattedAmount: String {
        let prefix = isCredit ? "+" : "-"
        return "\(prefix)$\(String(format: "%.2f", amount))"
    }
}

enum ActivityIcon {
    case category(emoji: String, background: Color)
    case person(initial: String, color: Color)
}

extension ActivityItem {
    static let samples: [ActivityItem] = [
        ActivityItem(title: "Starbucks",    subtitle: "Coffee",        amount: 12.50,  isCredit: false, date: .now,                              icon: .category(emoji: "☕️", background: TallyColors.cardPeach)),
        ActivityItem(title: "Sarah Kim",    subtitle: "Roommates",     amount: 43.20,  isCredit: true,  date: .now.addingTimeInterval(-3_600),   icon: .person(initial: "S", color: .orange)),
        ActivityItem(title: "Spotify",      subtitle: "Music",         amount: 14.99,  isCredit: false, date: .now.addingTimeInterval(-86_400),  icon: .category(emoji: "🎵", background: TallyColors.cardMint)),
        ActivityItem(title: "Whole Foods",  subtitle: "Groceries",     amount: 86.40,  isCredit: false, date: .now.addingTimeInterval(-86_400),  icon: .category(emoji: "🛒", background: TallyColors.cardSky)),
        ActivityItem(title: "Alex Chen",    subtitle: "Ski Trip",      amount: 150.00, isCredit: true,  date: .now.addingTimeInterval(-86_400),  icon: .person(initial: "A", color: .blue)),
        ActivityItem(title: "Uber",         subtitle: "Transport",     amount: 28.00,  isCredit: false, date: .now.addingTimeInterval(-172_800), icon: .category(emoji: "🚗", background: TallyColors.cardCream)),
        ActivityItem(title: "Netflix",      subtitle: "Entertainment", amount: 22.99,  isCredit: false, date: .now.addingTimeInterval(-172_800), icon: .category(emoji: "🎬", background: TallyColors.cardBlush)),
        ActivityItem(title: "Jordan Park",  subtitle: "Date Night",    amount: 65.00,  isCredit: true,  date: .now.addingTimeInterval(-259_200), icon: .person(initial: "J", color: .purple)),
        ActivityItem(title: "Trader Joe's", subtitle: "Groceries",     amount: 54.30,  isCredit: false, date: .now.addingTimeInterval(-259_200), icon: .category(emoji: "🛍️", background: TallyColors.cardSky)),
        ActivityItem(title: "Electric Bill",subtitle: "Utilities",     amount: 142.00, isCredit: false, date: .now.addingTimeInterval(-345_600), icon: .category(emoji: "⚡️", background: TallyColors.cardCream)),
    ]
}

// MARK: - Home Tab

private struct HomeTab: View {
    let circles: [TallyCircle]
    var onCirclesTap: () -> Void = {}
    @Environment(Clerk.self) private var clerk

    // Track scroll offset for header fade
    @State private var scrollOffset: CGFloat = 0
    @State private var cardScrollOffset: CGFloat = 0
    @State private var cardMaxOffset: CGFloat = 0

    private var groupedItems: [(label: String, items: [ActivityItem])] {
        let items = ActivityItem.samples
        let calendar = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"

        let grouped = Dictionary(grouping: items) { item -> String in
            if calendar.isDateInToday(item.date)     { return "Today" }
            if calendar.isDateInYesterday(item.date)  { return "Yesterday" }
            return fmt.string(from: item.date)
        }

        let pinned = ["Today", "Yesterday"]
        return grouped
            .map { (label: $0.key, items: $0.value) }
            .sorted { a, b in
                let ai = pinned.firstIndex(of: a.label) ?? 99
                let bi = pinned.firstIndex(of: b.label) ?? 99
                if ai != bi { return ai < bi }
                let ad = a.items.first?.date ?? .distantPast
                let bd = b.items.first?.date ?? .distantPast
                return ad > bd
            }
    }

    /// Hardcoded total balance for UI testing.
    private var totalBalance: String { "$1,000.00" }

    /// Header opacity: starts fading at 40pt, gone by 120pt
    private var headerOpacity: Double {
        let fadeStart: CGFloat = 40
        let fadeEnd: CGFloat = 120
        if scrollOffset <= fadeStart { return 1 }
        if scrollOffset >= fadeEnd { return 0 }
        return Double(1 - (scrollOffset - fadeStart) / (fadeEnd - fadeStart))
    }

    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 56)
                    greeting
                        .padding(.top, TallySpacing.lg)
                    balanceFlatSection
                        .padding(.top, TallySpacing.md)
                        .padding(.bottom, TallySpacing.xl)
                    cardsSection
                        .padding(.bottom, TallySpacing.xl)
                    quickButtonGrid
                        .padding(.bottom, TallySpacing.xl)
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

            // Floating header overlay
            topBar
                .allowsHitTesting(headerOpacity > 0.1)
        }
        .background(Color.white.ignoresSafeArea())
    }

    // MARK: - Top Bar (floating, fades on deep scroll)

    private var topBar: some View {
        HStack {
            Text("Mntly")
                .font(TallyFont.brandNav)
                .foregroundStyle(TallyColors.textPrimary)
            Spacer()
            GlassNavButton(icon: "bell") {}
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

    // MARK: - Greeting

    private var greeting: some View {
        Text("Hi, \(clerk.user?.firstName ?? "there")")
            .font(TallyFont.largeTitle)
            .foregroundStyle(TallyColors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, TallySpacing.screenPadding)
    }

    // MARK: - Flat Balance Section

    private var balanceFlatSection: some View {
        VStack(alignment: .leading, spacing: TallySpacing.sm) {
            Text("TOTAL BALANCE")
                .font(TallyFont.overline)
                .foregroundStyle(TallyColors.textSecondary)
                .tracking(0.5)
            Text(totalBalance)
                .font(TallyFont.balanceAmount)
                .foregroundStyle(TallyColors.textPrimary)
            HStack(spacing: TallySpacing.sm) {
                Button {} label: {
                    Text("Add Money")
                        .font(TallyFont.bodySmallBold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(TallyColors.textPrimary)
                        .clipShape(Capsule())
                }
                Button {} label: {
                    Text("Withdraw")
                        .font(TallyFont.bodySmallBold)
                        .foregroundStyle(TallyColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .overlay(Capsule().strokeBorder(TallyColors.textPrimary, lineWidth: 1.5))
                }
            }
            .padding(.top, TallySpacing.xs)
        }
        .padding(.horizontal, TallySpacing.screenPadding)
    }

    // MARK: - Cards Section

    private var activeCardIndex: Int {
        let dotCount = min(circles.count, 5)
        guard dotCount > 1 else { return 0 }
        if cardMaxOffset > 0 && cardScrollOffset >= cardMaxOffset - 8 {
            return dotCount - 1
        }
        let cardStep: CGFloat = 170 + 12
        return max(0, min(dotCount - 1, Int((cardScrollOffset + cardStep / 2) / cardStep)))
    }

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            HStack {
                HStack(spacing: TallySpacing.sm) {
                    Text("CARDS")
                        .font(TallyFont.overline)
                        .foregroundStyle(TallyColors.textSecondary)
                        .tracking(0.5)
                    if !circles.isEmpty {
                        Text("\(circles.count)")
                            .font(TallyFont.captionBold)
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(TallyColors.textPrimary)
                            .clipShape(Circle())
                    }
                }
                Spacer()
                Button {} label: {
                    Text("Add +")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.accent)
                }
            }
            .padding(.horizontal, TallySpacing.screenPadding)

            if circles.isEmpty {
                Text("Create a circle to get a card")
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textSecondary)
                    .padding(.horizontal, TallySpacing.screenPadding)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(circles.enumerated()), id: \.element.id) { index, circle in
                            Button { onCirclesTap() } label: {
                                TallyCard(
                                    circleName: circle.name,
                                    last4: circle.myCardLastFour ?? "0000",
                                    balance: circle.walletBalance,
                                    colorIndex: index,
                                    photo: circle.photo,
                                    compact: true
                                )
                            }
                        }
                    }
                    .padding(.horizontal, TallySpacing.screenPadding)
                }
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentOffset.x
                } action: { _, newOffset in
                    cardScrollOffset = max(0, newOffset)
                }
                .onScrollGeometryChange(for: CGFloat.self) { geo in
                    geo.contentSize.width - geo.containerSize.width
                } action: { _, newMax in
                    cardMaxOffset = max(0, newMax)
                }

                let dotCount = min(circles.count, 5)
                if dotCount > 1 {
                    HStack(spacing: 6) {
                        ForEach(0..<dotCount, id: \.self) { i in
                            Capsule()
                                .fill(activeCardIndex == i ? TallyColors.textPrimary : TallyColors.textSecondary.opacity(0.25))
                                .frame(width: activeCardIndex == i ? 20 : 8, height: 8)
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: activeCardIndex)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, TallySpacing.xs)
                }
            }
        }
    }

    // MARK: - Quick Button Grid

    private var quickButtonGrid: some View {
        VStack(alignment: .leading, spacing: TallySpacing.md) {
            Text("QUICK ACTIONS")
                .font(TallyFont.overline)
                .foregroundStyle(TallyColors.textSecondary)
                .tracking(0.5)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: TallySpacing.md), count: 3),
                spacing: TallySpacing.md
            ) {
                quickGridButton(icon: "plus.circle", label: "Top Up")
                quickGridButton(icon: "arrow.left.arrow.right", label: "Transfer")
                quickGridButton(icon: "arrow.down.circle", label: "Withdraw")
                quickGridButton(icon: "banknote", label: "Deposit")
                quickGridButton(icon: "doc.text", label: "Bills")
                quickGridButton(icon: "dollarsign.circle", label: "Currency")
            }
        }
        .padding(.horizontal, TallySpacing.screenPadding)
    }

    private func quickGridButton(icon: String, label: String) -> some View {
        Button {} label: {
            VStack(spacing: TallySpacing.sm) {
                Image(systemName: icon)
                    .font(TallyIcon.xxl)
                    .fontWeight(.semibold)
                    .foregroundStyle(TallyColors.textPrimary)
                Text(label)
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 80)
            .background(TallyColors.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
        }
    }

    // MARK: - Transactions

    private var transactionsHeader: some View {
        HStack {
            Text("TRANSACTIONS")
                .font(TallyFont.overline)
                .foregroundStyle(TallyColors.textSecondary)
                .tracking(0.5)
            Spacer()
            Button {} label: {
                HStack(spacing: TallySpacing.xs) {
                    Text("See all")
                        .font(TallyFont.body)
                        .foregroundStyle(TallyColors.accent)
                    Image(systemName: "chevron.right")
                        .font(TallyIcon.xs)
                        .fontWeight(.semibold)
                        .foregroundStyle(TallyColors.accent)
                }
            }
        }
        .padding(.horizontal, TallySpacing.screenPadding)
        .padding(.bottom, TallySpacing.md)
    }

    private var transactionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if groupedItems.isEmpty {
                emptyState
            } else {
                ForEach(groupedItems, id: \.label) { group in
                    Text(group.label)
                        .font(TallyFont.overline)
                        .foregroundStyle(TallyColors.textSecondary)
                        .tracking(0.3)
                        .padding(.horizontal, TallySpacing.screenPadding)
                        .padding(.top, TallySpacing.lg)
                        .padding(.bottom, TallySpacing.sm)

                    // Elevated card container for the group
                    VStack(spacing: 0) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            ActivityRowView(item: item)
                            if index < group.items.count - 1 {
                                Divider()
                                    .foregroundStyle(TallyColors.borderLight)
                                    .padding(.leading, 72) // align with text after icon
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

    private var emptyState: some View {
        VStack(spacing: TallySpacing.md) {
            Image(systemName: "tray")
                .font(TallyIcon.heroLg)
                .foregroundStyle(TallyColors.textTertiary)
            Text("No activity found")
                .font(TallyFont.bodySemibold)
                .foregroundStyle(TallyColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, TallySpacing.xxxl)
    }
}

// MARK: - Activity Row

private struct ActivityRowView: View {
    let item: ActivityItem

    var body: some View {
        HStack(spacing: TallySpacing.md) {
            ActivityIconView(icon: item.icon, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(TallyFont.bodySemibold)
                    .foregroundStyle(TallyColors.textPrimary)
                Text(item.subtitle)
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.textSecondary)
            }

            Spacer()

            Text(item.formattedAmount)
                .font(TallyFont.amountsSmall)
                .foregroundStyle(item.isCredit ? TallyColors.statusSuccess : TallyColors.textPrimary)
        }
        .padding(.horizontal, TallySpacing.lg)
        .padding(.vertical, TallySpacing.md)
    }
}

// MARK: - Activity Icon

private struct ActivityIconView: View {
    let icon: ActivityIcon
    var size: CGFloat = 44

    var body: some View {
        switch icon {
        case .category(let emoji, let background):
            Text(emoji)
                .font(.system(size: size * 0.46))  // dynamic size based on container
                .frame(width: size, height: size)
                .background(background.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        case .person(let initial, let color):
            Text(initial)
                .font(.system(size: size * 0.38, weight: .semibold))  // dynamic size based on container
                .foregroundStyle(color)
                .frame(width: size, height: size)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Circles Tab

private struct CirclesTab: View {
    @Bindable var viewModel: CirclesViewModel
    @State private var showCreateFlow = false
    @State private var navigationPath = NavigationPath()
    @State private var pendingCircle: TallyCircle?
    @State private var searchText = ""

    private var recentActivityText: String? {
        for circle in viewModel.circles {
            if let latest = circle.transactions
                .sorted(by: { $0.date > $1.date })
                .first {
                return "\(latest.paidBy) paid \(String(format: "$%.2f", latest.amount)) in \(circle.name)"
            }
        }
        return nil
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading && viewModel.circles.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.circles.isEmpty {
                    emptyState
                } else {
                    CircleListView(
                        circles: viewModel.circles,
                        searchText: $searchText,
                        onAdd: { showCreateFlow = true },
                        recentActivityText: recentActivityText
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TallyColors.bgSecondary)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: TallyCircle.self) { circle in
                CircleFeedView(circle: circle, viewModel: viewModel)
            }
            .fullScreenCover(isPresented: $showCreateFlow, onDismiss: {
                if let circle = pendingCircle {
                    pendingCircle = nil
                    navigationPath.append(circle)
                }
            }) {
                CreateCircleFlowView(viewModel: viewModel) { createdCircle in
                    pendingCircle = createdCircle
                }
            }
            .task(id: "circles") {
                await viewModel.fetchCircles()
            }
            .refreshable {
                await viewModel.fetchCircles(force: true)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: TallySpacing.lg) {
            Spacer()
            Image(systemName: "person.3")
                .font(TallyIcon.splash)
                .foregroundStyle(TallyColors.textSecondary)
            Text("No circles yet")
                .font(TallyFont.title)
                .foregroundStyle(TallyColors.textPrimary)
            Text("Create a circle to start splitting expenses with friends.")
                .font(TallyFont.body)
                .foregroundStyle(TallyColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, TallySpacing.xxl)
            Button("Create Circle") { showCreateFlow = true }
                .buttonStyle(TallyPrimaryButtonStyle())
                .padding(.horizontal, TallySpacing.screenPadding)
            Spacer()
        }
    }
}


// MARK: - Profile Tab

private struct ProfileTab: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(Clerk.self) private var clerk

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: TallySpacing.md) {
                        Circle()
                            .fill(TallyColors.accent)
                            .frame(width: 56, height: 56)
                            .overlay(
                                Text(initials)
                                    .font(TallyFont.avatarInitials)
                                    .foregroundStyle(.white)
                            )
                        VStack(alignment: .leading, spacing: TallySpacing.xs) {
                            Text(displayName)
                                .font(TallyFont.bodySemibold)
                                .foregroundStyle(TallyColors.textPrimary)
                            if let email = clerk.user?.primaryEmailAddress?.emailAddress {
                                Text(email)
                                    .font(TallyFont.caption)
                                    .foregroundStyle(TallyColors.textSecondary)
                            }
                        }
                    }
                    .padding(.vertical, TallySpacing.sm)
                }

                Section("Linked Accounts") {
                    Label("Add bank account", systemImage: "building.columns")
                        .foregroundStyle(TallyColors.textSecondary)
                }

                Section("Security") {
                    Label("Face ID", systemImage: "faceid")
                    Label("Change email", systemImage: "envelope")
                }

                Section("Preferences") {
                    Label("Notifications", systemImage: "bell")
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }

                Section("Legal") {
                    Label("Terms of Service", systemImage: "doc.text")
                    Label("Privacy Policy", systemImage: "hand.raised")
                }

                Section {
                    Button("Sign Out") {
                        signOut()
                    }
                    .foregroundStyle(TallyColors.statusAlert)
                    .frame(maxWidth: .infinity)
                }

                Section {
                    Button("Delete Account") {}
                        .foregroundStyle(TallyColors.statusAlert)
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Profile")
        }
    }

    private var displayName: String {
        let first = clerk.user?.firstName ?? ""
        let last = clerk.user?.lastName ?? ""
        let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? "Tally User" : full
    }

    private var initials: String {
        let first = clerk.user?.firstName?.prefix(1) ?? ""
        let last = clerk.user?.lastName?.prefix(1) ?? ""
        let result = "\(first)\(last)"
        return result.isEmpty ? "T" : result.uppercased()
    }

    private func signOut() {
        Task {
            try? await clerk.auth.signOut()
            authManager.signOut()
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
        .environment(Clerk.shared)
}

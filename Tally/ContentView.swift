//
//  ContentView.swift
//  Tally
//
//  Created by Evan Chang on 3/1/26.
//

import SwiftUI
import ClerkKit

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

    init() {
        // Hide the system tab bar globally
        UITabBar.appearance().isHidden = true

        // Nav bar: opaque with shadow, not floating/translucent
        let navAppearance = UINavigationBarAppearance()
        navAppearance.configureWithOpaqueBackground()
        navAppearance.backgroundColor = UIColor(TallyColors.bgPrimary)
        navAppearance.shadowColor = .clear
        UINavigationBar.appearance().standardAppearance = navAppearance
        UINavigationBar.appearance().scrollEdgeAppearance = navAppearance
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Tab content
            Group {
                switch selectedTab {
                case .home:
                    HomeTab()
                case .circles:
                    CirclesTab()
                case .pay:
                    PayTab()
                case .wallet:
                    WalletTab()
                case .profile:
                    ProfileTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom tab bar
            TallyTabBar(selectedTab: $selectedTab)
        }
        .ignoresSafeArea(.keyboard)
    }
}

// MARK: - Custom Tab Bar

private struct TallyTabBar: View {
    @Binding var selectedTab: TallyTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(TallyTab.allCases, id: \.rawValue) { tab in
                if tab == .pay {
                    // Raised center button
                    PayButton(isSelected: selectedTab == .pay) {
                        selectedTab = .pay
                    }
                } else {
                    TabBarItem(tab: tab, isSelected: selectedTab == tab) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(.horizontal, TallySpacing.sm)
        .padding(.top, TallySpacing.sm)
        .padding(.bottom, TallySpacing.xs)
        .background(
            TallyColors.bgPrimary
                .shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2))
        )
    }
}

private struct TabBarItem: View {
    let tab: TallyTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: TallySpacing.xs) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20))
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(isSelected ? TallyColors.accent : TallyColors.textSecondary)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct PayButton: View {
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: TallySpacing.xs) {
                ZStack {
                    Circle()
                        .fill(TallyColors.accent)
                        .frame(width: 44, height: 44)
                    Image(systemName: "dollarsign")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .offset(y: -12)
                Text("Pay")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(isSelected ? TallyColors.accent : TallyColors.textSecondary)
                    .offset(y: -12)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Home Tab

private struct HomeTab: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: TallySpacing.lg) {
                Spacer()
                Image(systemName: "house.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(TallyColors.textSecondary)
                Text("Home")
                    .font(TallyFont.title)
                    .foregroundStyle(TallyColors.textPrimary)
                Text("Your activity feed will appear here.")
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TallyColors.bgPrimary)
            .navigationTitle("Home")
        }
    }
}

// MARK: - Circles Tab

private struct CirclesTab: View {
    @State private var showCreateFlow = false
    @State private var circles: [TallyCircle] = []

    var body: some View {
        NavigationStack {
            Group {
                if circles.isEmpty {
                    emptyState
                } else {
                    CircleListView(circles: circles) { _ in }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TallyColors.bgPrimary)
            .navigationTitle("Circles")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showCreateFlow = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create circle")
                }
            }
            .fullScreenCover(isPresented: $showCreateFlow) {
                CreateCircleFlowView()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: TallySpacing.lg) {
            Spacer()
            Image(systemName: "person.3")
                .font(.system(size: 48))
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

// MARK: - Pay Tab

private struct PayTab: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: TallySpacing.lg) {
                Spacer()
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(TallyColors.textSecondary)
                Text("Pay & Request")
                    .font(TallyFont.title)
                    .foregroundStyle(TallyColors.textPrimary)
                Text("Send money or request payments from friends.")
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, TallySpacing.xxl)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TallyColors.bgPrimary)
            .navigationTitle("Pay")
        }
    }
}

// MARK: - Wallet Tab

private struct WalletTab: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: TallySpacing.lg) {
                Spacer()
                Text("$0.00")
                    .font(TallyFont.heroAmount)
                    .foregroundStyle(TallyColors.textPrimary)
                Text("Load your wallet to get started")
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textSecondary)
                HStack(spacing: TallySpacing.md) {
                    Button("Load Wallet") {}
                        .buttonStyle(TallyPrimaryButtonStyle())
                    Button("Transfer") {}
                        .buttonStyle(TallySecondaryButtonStyle())
                }
                .padding(.horizontal, TallySpacing.screenPadding)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TallyColors.bgPrimary)
            .navigationTitle("Wallet")
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
                                    .font(.system(size: 22, weight: .semibold))
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

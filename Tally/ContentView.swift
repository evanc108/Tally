//
//  ContentView.swift
//  Tally
//
//  Created by Evan Chang on 3/1/26.
//

import SwiftUI
import ClerkKit

struct ContentView: View {
    @Environment(Clerk.self) private var clerk

    var body: some View {
        TabView {
            Tab("Home", systemImage: "house.fill") {
                HomeTab()
            }
            Tab("Wallet", systemImage: "wallet.bifold.fill") {
                WalletTab()
            }
            Tab("Card", systemImage: "creditcard.fill") {
                CardTab()
            }
            Tab("You", systemImage: "person.fill") {
                ProfileTab()
            }
        }
        .tint(TallyColors.accent)
    }
}

// MARK: - Home Tab

private struct HomeTab: View {
    var body: some View {
        NavigationStack {
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
                Button("Create Circle") {}
                    .buttonStyle(TallyPrimaryButtonStyle())
                    .padding(.horizontal, TallySpacing.screenPadding)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TallyColors.bgPrimary)
            .navigationTitle("Circles")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Create circle")
                }
            }
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

// MARK: - Card Tab

private struct CardTab: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: TallySpacing.lg) {
                Spacer()
                Image(systemName: "creditcard")
                    .font(.system(size: 48))
                    .foregroundStyle(TallyColors.textSecondary)
                Text("No cards yet")
                    .font(TallyFont.title)
                    .foregroundStyle(TallyColors.textPrimary)
                Text("Join a circle to get a card.")
                    .font(TallyFont.body)
                    .foregroundStyle(TallyColors.textSecondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TallyColors.bgPrimary)
            .navigationTitle("Card")
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
            .navigationTitle("You")
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

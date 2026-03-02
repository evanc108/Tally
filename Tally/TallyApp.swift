//
//  TallyApp.swift
//  Tally
//
//  Created by Evan Chang on 3/1/26.
//

import SwiftUI
import ClerkKit

@main
struct TallyApp: App {
    @State private var authManager = AuthManager()

    init() {
        Clerk.configure(publishableKey: AppConfig.clerkPublishableKey)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .environment(Clerk.shared)
        }
    }
}

struct RootView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(Clerk.self) private var clerk

    var body: some View {
        Group {
            switch authManager.state {
            case .onboarding:
                OnboardingContainerView()
            case .welcome:
                WelcomeView()
            case .authenticating:
                AuthFlowView()
            case .authenticated:
                ContentView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authManager.state)
        .task {
            // Skip to authenticated if Clerk already has an active session
            if clerk.session != nil {
                authManager.completeAuth()
            }
        }
        .onChange(of: clerk.session) {
            if clerk.session != nil, authManager.state != .authenticated {
                authManager.completeAuth()
            } else if clerk.session == nil, authManager.state == .authenticated {
                authManager.signOut()
            }
        }
    }
}

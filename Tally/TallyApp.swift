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
        ZStack {
            switch authManager.state {
            case .welcome:
                WelcomeView()
                    .transition(.move(edge: .leading).combined(with: .opacity.animation(.easeOut(duration: 0.15))))
                    .zIndex(0)
            case .onboarding:
                OnboardingContainerView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .trailing)
                    ))
                    .zIndex(1)
            case .authenticating:
                AuthFlowView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing),
                        removal: .move(edge: .trailing)
                    ))
                    .zIndex(2)
            case .authenticated:
                ContentView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .move(edge: .bottom).combined(with: .opacity)
                    ))
                    .zIndex(3)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: authManager.state)
        .task {
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

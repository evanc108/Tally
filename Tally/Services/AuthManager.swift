import SwiftUI

// MARK: - Auth State

enum AuthState: Equatable {
    case onboarding
    case welcome
    case authenticating
    case authenticated
}

// MARK: - Auth Manager

@Observable
final class AuthManager {
    var state: AuthState

    // MARK: - Init

    init() {
        let hasSeenOnboarding = UserDefaults.standard.bool(forKey: "hasSeenOnboarding")

        if hasSeenOnboarding {
            state = .welcome
        } else {
            state = .onboarding
        }
    }

    // MARK: - Onboarding

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        state = .welcome
    }

    // MARK: - Auth

    func startAuth() {
        state = .authenticating
    }

    func completeAuth() {
        state = .authenticated
    }

    func signOut() {
        state = .welcome
    }
}

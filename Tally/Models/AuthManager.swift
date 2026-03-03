import SwiftUI

@Observable
final class AuthManager {
    enum State: Equatable {
        case welcome
        case onboarding
        case authenticating
        case authenticated
    }

    enum AuthMode: Equatable {
        case login
        case signUp
    }

    private(set) var state: State = .welcome
    var authMode: AuthMode = .signUp

    func showOnboarding() {
        state = .onboarding
    }

    func beginAuth(mode: AuthMode) {
        authMode = mode
        state = .authenticating
    }

    func completeAuth() {
        state = .authenticated
    }

    func signOut() {
        state = .welcome
    }

    func backToWelcome() {
        state = .welcome
    }
}

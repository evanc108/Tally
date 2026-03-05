import SwiftUI

@Observable
final class AuthManager {
    enum State: Equatable {
        case welcome
        case onboarding
        case authenticating
        case verifyingEmail
        case verifyingIdentity
        case authenticated
    }

    enum AuthMode: Equatable {
        case login
        case signUp
    }

    private(set) var state: State = .welcome
    var authMode: AuthMode = .signUp
    var pendingEmail: String?

    func showOnboarding() {
        state = .onboarding
    }

    func beginAuth(mode: AuthMode) {
        authMode = mode
        state = .authenticating
    }

    func requireEmailVerification(email: String) {
        pendingEmail = email
        state = .verifyingEmail
    }

    func requireIdentityVerification() {
        state = .verifyingIdentity
    }

    func completeAuth() {
        state = .authenticated
    }

    func signOut() {
        state = .welcome
        pendingEmail = nil
    }

    func backToWelcome() {
        state = .welcome
        pendingEmail = nil
    }
}

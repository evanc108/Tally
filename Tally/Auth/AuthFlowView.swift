import SwiftUI
import ClerkKit

enum AuthRoute: Hashable {
    case signUp
    case forgotPassword
    case verifyEmail(email: String, isPasswordReset: Bool)
    case resetPassword
}

@Observable
final class AuthFlowModel {
    var currentSignIn: SignIn?
    var currentSignUp: SignUp?
}

struct AuthFlowView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(Clerk.self) private var clerk
    @State private var path: [AuthRoute] = []
    @State private var flowModel = AuthFlowModel()

    var body: some View {
        NavigationStack(path: $path) {
            SignInView(path: $path)
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .signUp:
                        SignUpView(path: $path)
                    case .forgotPassword:
                        ForgotPasswordView(path: $path)
                    case .verifyEmail(let email, let isPasswordReset):
                        VerifyEmailView(email: email, isPasswordReset: isPasswordReset, path: $path)
                    case .resetPassword:
                        ResetPasswordView(path: $path)
                    }
                }
        }
        .environment(flowModel)
        .task {
            if clerk.session != nil {
                authManager.completeAuth()
            }
        }
        .onChange(of: clerk.session) {
            if clerk.session != nil {
                authManager.completeAuth()
            }
        }
    }
}

#Preview {
    AuthFlowView()
        .environment(AuthManager())
        .environment(Clerk.shared)
}

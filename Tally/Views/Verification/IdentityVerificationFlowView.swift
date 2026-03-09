import SwiftUI

enum VerificationStep: Int, CaseIterable {
    case intro
    case selectIDType
    case captureFront
    case captureBack
    case selfie
    case processing
    case result
}

enum IDType: String, CaseIterable, Identifiable {
    case driversLicense = "Driver's License"
    case passport = "Passport"
    case nationalID = "National ID Card"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .driversLicense: return "Front and back required"
        case .passport: return "Photo page only"
        case .nationalID: return "Front and back required"
        }
    }

    var icon: String {
        switch self {
        case .driversLicense: return "car.fill"
        case .passport: return "text.book.closed.fill"
        case .nationalID: return "person.text.rectangle.fill"
        }
    }

    var requiresBack: Bool {
        self != .passport
    }
}

struct IdentityVerificationFlowView: View {
    @Environment(AuthManager.self) private var authManager
    @Environment(\.openURL) private var openURL

    @State private var step: VerificationStep = .intro
    @State private var selectedIDType: IDType = .driversLicense
    @State private var verificationSucceeded = true
    @State private var isStartingKYC = false
    @State private var kycError: String?

    var body: some View {
        ZStack(alignment: .bottom) {
            TallyColors.white.ignoresSafeArea()

            switch step {
            case .intro:
                VerifyIdentityIntroView(onBegin: { advanceTo(.selectIDType) }, onBack: { authManager.backToWelcome() })
                    .transition(slideTransition)
            case .selectIDType:
                SelectIDTypeView(
                    selectedType: $selectedIDType,
                    onContinue: { advanceTo(.captureFront) },
                    onBack: { advanceTo(.intro) }
                )
                .transition(slideTransition)
            case .captureFront:
                ScanIDView(
                    side: .front,
                    idType: selectedIDType,
                    onCapture: {
                        if selectedIDType.requiresBack {
                            advanceTo(.captureBack)
                        } else {
                            advanceTo(.selfie)
                        }
                    },
                    onBack: { advanceTo(.selectIDType) }
                )
                .transition(slideTransition)
            case .captureBack:
                ScanIDView(
                    side: .back,
                    idType: selectedIDType,
                    onCapture: { advanceTo(.selfie) },
                    onBack: { advanceTo(.captureFront) }
                )
                .transition(slideTransition)
            case .selfie:
                SelfieVerificationView(
                    onCapture: { advanceTo(.processing) },
                    onBack: {
                        if selectedIDType.requiresBack {
                            advanceTo(.captureBack)
                        } else {
                            advanceTo(.captureFront)
                        }
                    }
                )
                .transition(slideTransition)
            case .processing:
                VerificationProcessingView(onComplete: { succeeded in
                    verificationSucceeded = succeeded
                    advanceTo(.result)
                })
                .task {
                    await startKYC()
                }
                .transition(.opacity)
            case .result:
                VerificationResultView(
                    succeeded: verificationSucceeded,
                    onContinue: { authManager.completeAuth() },
                    onRetry: { advanceTo(.captureFront) },
                    onCancel: { authManager.backToWelcome() }
                )
                .transition(slideTransition)
            }

            if let kycError {
                Text(kycError)
                    .font(TallyFont.caption)
                    .foregroundStyle(TallyColors.statusAlert)
                    .padding(.horizontal, TallySpacing.screenPadding)
                    .padding(.vertical, TallySpacing.sm)
                    .background(TallyColors.statusAlertBg)
                    .clipShape(RoundedRectangle(cornerRadius: TallyRadius.md))
                    .padding(.bottom, TallySpacing.xl)
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.1), value: step)
    }

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private func advanceTo(_ newStep: VerificationStep) {
        step = newStep
    }

    private func startKYC() async {
        if isStartingKYC {
            return
        }
        isStartingKYC = true
        kycError = nil

        struct KYCStartRequest: Encodable {
            let memberId: String

            enum CodingKeys: String, CodingKey {
                case memberId = "member_id"
            }
        }

        struct KYCStartResponse: Decodable {
            let sessionID: String
            let url: String

            enum CodingKeys: String, CodingKey {
                case sessionID = "session_id"
                case url
            }
        }

        do {
            let request = KYCStartRequest(memberId: UUID().uuidString)
            let response: KYCStartResponse = try await APIClient.shared.post(
                path: "/v1/users/me/kyc",
                body: request
            )
            if let url = URL(string: response.url),
               let scheme = url.scheme,
               scheme == "http" || scheme == "https" {
                await openURL(url)
            }
        } catch {
            kycError = "Could not start verification. Please try again."
        }

        isStartingKYC = false
    }
}

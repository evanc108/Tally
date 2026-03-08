import SwiftUI

struct PayFlowView: View {
    /// Pre-populated viewModel from the scan modal (has receipt already set).
    var preloadedViewModel: PayFlowViewModel? = nil
    @State private var viewModel: PayFlowViewModel
    @Environment(\.dismiss) private var dismiss

    init(preloadedViewModel: PayFlowViewModel? = nil) {
        self.preloadedViewModel = preloadedViewModel
        self._viewModel = State(initialValue: preloadedViewModel ?? PayFlowViewModel())
    }

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            PayReceiptReviewView(viewModel: viewModel)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        GlassNavButton(icon: "xmark") { dismiss() }
                    }
                }
                .navigationDestination(for: PayFlowRoute.self) { route in
                    destination(for: route)
                }
        }
    }

    // MARK: - Destination Router

    @ViewBuilder
    private func destination(for route: PayFlowRoute) -> some View {
        switch route {
        case .receiptReview:
            PayReceiptReviewView(viewModel: viewModel)
                .withPayBackButton { viewModel.pop() }

        case .splitConfig:
            PaySplitConfigView(viewModel: viewModel)
                .withPayBackButton { viewModel.pop() }

        case .leaderAssign:
            PayLeaderAssignView(viewModel: viewModel)
                .withPayBackButton { viewModel.pop() }

        case .memberSelect:
            PayMemberSelectView(viewModel: viewModel)
                .withPayBackButton { viewModel.pop() }

        case .waiting:
            PayWaitingView(viewModel: viewModel)
                .withPayBackButton { viewModel.pop() }

        case .tipConfig:
            PayTipConfigView(viewModel: viewModel)
                .withPayBackButton { viewModel.pop() }

        case .leaderApprove:
            PayLeaderApproveView(viewModel: viewModel)
                .withPayBackButton { viewModel.pop() }

        case .cardReady:
            // Merged into LeaderApproveView — redirect
            PayLeaderApproveView(viewModel: viewModel)
                .withPayBackButton { viewModel.pop() }

        case .complete:
            PayCompleteView(viewModel: viewModel, onDone: { dismiss() })
                .navigationBarBackButtonHidden()

        case .walletConfirm:
            PayWalletConfirmView(viewModel: viewModel, onDone: { dismiss() })
                .withPayBackButton { viewModel.pop() }

        case .percentageSplit:
            PayPercentageSplitView(viewModel: viewModel)
                .withPayBackButton { viewModel.pop() }
        }
    }
}

// MARK: - Back Button Modifier

private struct PayBackButtonModifier: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    GlassNavButton(icon: "chevron.left", action: action)
                }
            }
    }
}

extension View {
    fileprivate func withPayBackButton(action: @escaping () -> Void) -> some View {
        modifier(PayBackButtonModifier(action: action))
    }
}

// MARK: - Preview

#Preview {
    PayFlowView(preloadedViewModel: {
        let vm = PayFlowViewModel()
        vm.receipt = PayReceipt.sample
        return vm
    }())
}

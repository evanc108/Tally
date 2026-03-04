import SwiftUI

struct PayFlowView: View {
    @State private var viewModel = PayFlowViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $viewModel.path) {
            PayReceiptEntryView(viewModel: viewModel)
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(TallyColors.textPrimary)
                        }
                    }
                }
                .navigationDestination(for: PayFlowRoute.self) { route in
                    destination(for: route)
                }
        }
        .task {
            await viewModel.fetchCirclesWithCards()
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

        case .leaderApprove:
            PayLeaderApproveView(viewModel: viewModel)
                .withPayBackButton { viewModel.pop() }

        case .cardReady:
            PayCardReadyView(viewModel: viewModel)
                .withPayBackButton { viewModel.pop() }

        case .complete:
            PayCompleteView(viewModel: viewModel, onDone: { dismiss() })
                .navigationBarBackButtonHidden()
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
                    Button(action: action) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(TallyColors.textPrimary)
                    }
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
    PayFlowView()
}

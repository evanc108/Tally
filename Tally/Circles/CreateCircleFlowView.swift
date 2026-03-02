import SwiftUI

struct CreateCircleFlowView: View {
    @State private var state = CreateCircleState.seeded()
    @State private var path: [CreateCircleRoute] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack(path: $path) {
            CircleNameView(state: state) { path.append(.addMembers) }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        CloseButton { dismiss() }
                    }
                }
                .navigationDestination(for: CreateCircleRoute.self) { route in
                    destination(for: route)
                }
        }
    }

    @ViewBuilder
    private func destination(for route: CreateCircleRoute) -> some View {
        switch route {
        case .addMembers:
            AddMembersView(state: state) { path.append(.splitMethod) }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden()
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        BackChevron { path.removeLast() }
                    }
                }

        case .splitMethod:
            SplitMethodView(state: state) { path.append(.chooseLeader) }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden()
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        BackChevron { path.removeLast() }
                    }
                }

        case .chooseLeader:
            ChooseLeaderView(state: state) { path.append(.cardIssued) }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden()
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        BackChevron { path.removeLast() }
                    }
                }

        case .cardIssued:
            CardIssuedView(state: state) { path.append(.circleReady) }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .navigationBarBackButtonHidden()
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        BackChevron { path.removeLast() }
                    }
                }

        case .circleReady:
            CircleReadyView(state: state) { dismiss() }
        }
    }
}

// MARK: - Navigation Buttons (Venmo-style)

private struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TallyColors.textPrimary)
                .frame(width: 32, height: 32)
                .background(TallyColors.bgSecondary)
                .clipShape(Circle())
        }
    }
}

private struct BackChevron: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(TallyColors.textPrimary)
                .frame(width: 32, height: 32)
                .background(TallyColors.bgSecondary)
                .clipShape(Circle())
        }
    }
}

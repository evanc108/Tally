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
                .toolbar { cancelToolbar() }
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

        case .splitMethod:
            SplitMethodView(state: state) { path.append(.chooseLeader) }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)

        case .chooseLeader:
            ChooseLeaderView(state: state) { path.append(.cardIssued) }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)

        case .cardIssued:
            CardIssuedView(state: state) { path.append(.circleReady) }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)

        case .circleReady:
            CircleReadyView(state: state) { dismiss() }
        }
    }

    @ToolbarContentBuilder
    private func cancelToolbar() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button("Cancel") { dismiss() }
                .foregroundStyle(TallyColors.textSecondary)
        }
    }
}

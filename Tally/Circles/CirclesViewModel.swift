import ClerkKit
import Foundation

@Observable
@MainActor
final class CirclesViewModel {
    var circles: [TallyCircle] = []
    var isLoading = false
    var error: TallyError?
    private var hasFetched = false

    private static let deletedKey = "tally.deletedCircleIDs"

    /// Server IDs of circles the user deleted locally — persisted across app launches.
    private var deletedServerIDs: Set<String> {
        didSet { Self.saveDeletedIDs(deletedServerIDs) }
    }

    init() {
        self.deletedServerIDs = Self.loadDeletedIDs()
    }

    private static func loadDeletedIDs() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: deletedKey) ?? []
        return Set(arr)
    }

    private static func saveDeletedIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids), forKey: deletedKey)
    }

    // MARK: - Fetch

    func fetchCircles() async {
        // Allow first fetch to populate; subsequent calls refresh in-place
        let isFirstFetch = !hasFetched
        hasFetched = true
        isLoading = true
        defer { isLoading = false }
        do {
            let response: ListCirclesResponseDTO = try await APIClient.shared.get(path: "/v1/groups")
            let fetched = response.groups
                .map { TallyCircle(from: $0) }
                .filter { circle in
                    // Exclude circles that were deleted locally
                    guard let sid = circle.serverId else { return true }
                    return !deletedServerIDs.contains(sid)
                }
            // Prune stale deleted IDs that the server no longer returns
            let serverIDs = Set(response.groups.compactMap(\.groupID) as [String])
            let stale = deletedServerIDs.subtracting(serverIDs)
            if !stale.isEmpty { deletedServerIDs.subtract(stale) }

            // Merge with persisted local data (members, display name, split, leader)
            let persisted = CircleStore.loadAll()
            circles = fetched.map { apiCircle in
                var circle = apiCircle
                // First: merge from in-memory existing data (highest priority)
                if let existing = circles.first(where: { $0.serverId == apiCircle.serverId }),
                   !existing.members.isEmpty {
                    circle.members = existing.members
                    circle.transactions = existing.transactions
                    circle.walletBalance = existing.walletBalance
                    circle.splitMethod = existing.splitMethod
                    circle.leaderId = existing.leaderId
                    circle.name = existing.name
                } else if let sid = apiCircle.serverId, let saved = persisted[sid] {
                    // Fallback: merge from disk persistence
                    saved.apply(to: &circle)
                }
                return circle
            }
        } catch let e as TallyError {
            error = e
            if isFirstFetch && circles.isEmpty { circles = TallyCircle.samples }
        } catch {
            if isFirstFetch && circles.isEmpty { circles = TallyCircle.samples }
        }
    }

    // MARK: - Create

    /// Ensures the user row exists in the backend, then creates the group.
    /// Appends the new circle locally and returns it.
    func createCircle(state: CreateCircleState) async throws -> TallyCircle {
        try await ensureUser()

        let slug = state.circleName
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")

        // Build member list from the local state (excludes the creator — backend adds them automatically).
        let totalPeople = Double(state.members.count + 1) // +1 for the creator
        let memberDTOs = state.members.map { member in
            CreateGroupMemberDTO(
                displayName: member.name,
                splitWeight: member.splitPercentage > 0
                    ? member.splitPercentage / 100.0
                    : 1.0 / totalPeople
            )
        }

        let req = CreateCircleRequestDTO(
            name: slug,
            displayName: state.circleName,
            currency: "USD",
            members: memberDTOs
        )
        let response: CreateCircleResponseDTO = try await APIClient.shared.post(
            path: "/v1/groups",
            body: req
        )

        let isoFormatter = ISO8601DateFormatter()
        let circle = TallyCircle(
            serverId: response.groupID,
            name: state.circleName,
            members: state.members,
            splitMethod: state.splitMethod,
            leaderId: state.leaderId,
            transactions: [],
            createdAt: isoFormatter.date(from: response.createdAt) ?? .now
        )
        circles.insert(circle, at: 0)
        CircleStore.save(PersistedCircle(from: circle))
        return circle
    }

    // MARK: - Update

    /// Patches the circle's name and/or split mode on the backend, then updates locally.
    func updateCircle(_ circle: TallyCircle, name: String?, splitMethod: SplitMethod?) async {
        // Update locally first for instant feedback
        if let idx = circles.firstIndex(where: { $0.id == circle.id }) {
            if let name { circles[idx].name = name }
            if let splitMethod { circles[idx].splitMethod = splitMethod }
            CircleStore.save(PersistedCircle(from: circles[idx]))
        }

        // Sync to server
        guard let serverId = circle.serverId else { return }
        let req = UpdateCircleRequestDTO(
            displayName: name,
            splitMode: splitMethod?.rawValue.lowercased()
        )
        do {
            try await APIClient.shared.patch(path: "/v1/groups/\(serverId)", body: req)
        } catch {
            print("[Tally] Failed to update circle \(serverId): \(error)")
        }
    }

    // MARK: - Close (Archive)

    /// Archives the circle on the backend, then removes it from local state.
    /// Always removes locally — the API call is best-effort.
    func closeCircle(_ circle: TallyCircle) async {
        if let serverId = circle.serverId {
            deletedServerIDs.insert(serverId)
            CircleStore.remove(serverId: serverId)
            do {
                // Void delete — doesn't try to decode the response body
                try await APIClient.shared.delete(path: "/v1/groups/\(serverId)")
            } catch {
                print("[Tally] Failed to delete circle \(serverId) on server: \(error)")
            }
        }
        circles.removeAll { $0.id == circle.id }
    }

    // MARK: - Private

    private func ensureUser() async throws {
        let first = Clerk.shared.user?.firstName ?? ""
        let last = Clerk.shared.user?.lastName ?? ""
        let body = ["first_name": first, "last_name": last]
        let _: MeResponseDTO = try await APIClient.shared.post(path: "/v1/users/me", body: body)
    }
}

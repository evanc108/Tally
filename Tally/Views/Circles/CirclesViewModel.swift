import ClerkKit
import Foundation
import UIKit

@Observable
@MainActor
final class CirclesViewModel {
    var circles: [TallyCircle] = []
    var isLoading = false
    var error: TallyError?
    private var hasFetched = false

    /// Hardcoded starting balance per circle for UI testing.
    /// Backend tally_balance_cents starts at 0 and goes negative on spend,
    /// so this offset makes the displayed balance = startingBalance + delta.
    static let startingBalance: Double = 100

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

    func fetchCircles(force: Bool = false) async {
        // Skip if already fetched — callers pass force: true to refresh
        if hasFetched && !force { return }
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
            circles = fetched.enumerated().map { index, apiCircle in
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
                    circle.photo = existing.photo
                } else if let sid = apiCircle.serverId, let saved = persisted[sid] {
                    // Fallback: merge from disk persistence
                    saved.apply(to: &circle)
                }
                // Load photo from local cache
                if circle.photo == nil, let sid = circle.serverId {
                    circle.photo = CirclePhotoCache.load(serverId: sid)
                }
                // Default wallet balance for UI testing
                if circle.walletBalance == 0 {
                    circle.walletBalance = Self.startingBalance
                }
                return circle
            }

            // Fetch photos from server for circles that have them but aren't loaded yet
            for i in circles.indices where circles[i].hasServerPhoto && circles[i].photo == nil {
                let serverId = circles[i].serverId!
                let idx = i
                Task {
                    guard let data = try? await APIClient.shared.getRaw(path: "/v1/groups/\(serverId)/photo"),
                          let image = UIImage(data: data) else { return }
                    self.circles[idx].photo = image
                    CirclePhotoCache.save(image, serverId: serverId)
                }
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
        var circle = TallyCircle(
            serverId: response.groupID,
            name: state.circleName,
            members: state.members,
            splitMethod: state.splitMethod,
            leaderId: state.leaderId,
            transactions: [],
            createdAt: isoFormatter.date(from: response.createdAt) ?? .now
        )

        // Save photo locally and upload to backend
        if let photo = state.photo {
            circle.photo = photo
            CirclePhotoCache.save(photo, serverId: response.groupID)
            Task {
                guard let jpegData = photo.jpegData(compressionQuality: 0.7) else { return }
                try? await APIClient.shared.putRaw(
                    path: "/v1/groups/\(response.groupID)/photo",
                    data: jpegData,
                    contentType: "image/jpeg"
                )
            }
        }

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

    // MARK: - Circle Detail (transactions + balance)

    /// Fetches transactions and member balances for a specific circle from the backend.
    /// Updates the circle in-place with real data.
    func fetchCircleDetail(for circle: TallyCircle) async {
        guard let serverId = circle.serverId else { return }

        // Fetch transactions and group detail in parallel
        async let txnTask: ListTransactionsResponseDTO? = {
            try? await APIClient.shared.get(path: "/v1/groups/\(serverId)/transactions")
        }()
        async let detailTask: GroupDetailResponseDTO? = {
            try? await APIClient.shared.get(path: "/v1/groups/\(serverId)")
        }()

        let txnResponse = await txnTask
        let detailResponse = await detailTask

        guard let idx = circles.firstIndex(where: { $0.id == circle.id }) else { return }

        // Map backend transactions → CircleTransaction
        if let txns = txnResponse?.transactions {
            circles[idx].transactions = txns.map { CircleTransaction(from: $0) }
        }

        // Compute wallet balance: starting balance + backend delta.
        // tally_balance_cents starts at 0 and goes negative as members spend,
        // so we add it to the hardcoded starting balance for consistency.
        if let members = detailResponse?.members {
            let deltaCents = members.reduce(Int64(0)) { $0 + $1.tallyBalanceCents }
            circles[idx].walletBalance = Self.startingBalance + Double(deltaCents) / 100.0
        }
    }

    /// Refreshes a circle by serverId — called after payment completes.
    func refreshCircle(serverId: String) async {
        guard let circle = circles.first(where: { $0.serverId == serverId }) else { return }
        await fetchCircleDetail(for: circle)
    }

    // MARK: - Private

    private func ensureUser() async throws {
        let first = Clerk.shared.user?.firstName ?? ""
        let last = Clerk.shared.user?.lastName ?? ""
        let body = ["first_name": first, "last_name": last]
        let _: MeResponseDTO = try await APIClient.shared.post(path: "/v1/users/me", body: body)
    }
}

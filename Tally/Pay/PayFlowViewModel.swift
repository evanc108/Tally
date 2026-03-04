import Foundation
import UIKit
import Vision

// MARK: - PayFlowViewModel

/// Orchestrates the entire Pay flow, driving a NavigationStack via `path`.
/// All network calls go through `APIClient.shared`; state updates land on @MainActor.
@Observable
@MainActor
final class PayFlowViewModel {

    // MARK: - Navigation

    var path: [PayFlowRoute] = []

    // MARK: - Data

    var circles: [TallyCircle] = []
    var selectedCircle: TallyCircle?
    /// Server-authoritative members for the selected circle (fetched via GET /v1/groups/:id).
    var serverMembers: [GroupMemberDTO] = []
    var fundingSource: FundingSource = .card
    var receipt: PayReceipt?
    var session: PaySession?
    var splits: [PaySplit] = []
    var manualAmountCents: Int64 = 0
    var merchantName: String = ""
    var splitMethod: PaySplitMethod = .equal
    var assignmentMode: AssignmentMode = .leader
    var tapResult: SimulateTapResponseDTO?
    var memberPercentages: [String: Double] = [:]

    // MARK: - Payment Methods

    var paymentMethods: [PaymentMethod] = []
    var selectedPaymentMethod: PaymentMethod?

    // MARK: - Scanning State

    var isScanning = false
    var scanError: String?

    // MARK: - UI State

    var isLoading = false
    var error: TallyError?

    // MARK: - Computed

    /// The authoritative total for this pay flow — receipt wins when present.
    var totalCents: Int64 {
        receipt?.totalCents ?? manualAmountCents
    }

    // MARK: - Navigation Helpers

    func push(_ route: PayFlowRoute) {
        path.append(route)
    }

    func pop() {
        guard !path.isEmpty else { return }
        path.removeLast()
    }

    // MARK: - Circles & Payment Methods

    /// Fetches the user's circles and builds the payment method list from card data.
    func fetchCirclesWithCards() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let response: ListCirclesResponseDTO = try await APIClient.shared.get(
                path: "/v1/groups"
            )
            circles = response.groups.map { TallyCircle(from: $0) }
            buildPaymentMethods()
        } catch let tallyError as TallyError {
            error = tallyError
        } catch {
            self.error = .network(URLError(.unknown))
        }
    }

    /// Builds the payment method dropdown list from circles with cards + wallet.
    private func buildPaymentMethods() {
        var methods: [PaymentMethod] = []

        for circle in circles {
            guard let groupId = circle.serverId else { continue }
            // Use real card data when available, mock lastFour from groupId otherwise
            let lastFour = circle.myCardLastFour ?? String(groupId.suffix(4))
            methods.append(PaymentMethod(
                id: "\(groupId):card",
                kind: .circleCard,
                circleName: circle.name,
                groupId: groupId,
                lastFour: lastFour
            ))
        }

        methods.append(PaymentMethod(
            id: "wallet",
            kind: .wallet,
            circleName: nil,
            groupId: nil,
            lastFour: nil
        ))

        paymentMethods = methods
        restoreOrAutoSelect()
    }

    // MARK: - Payment Method Persistence

    private static let lastPaymentMethodKey = "lastPaymentMethodId"

    private func restoreOrAutoSelect() {
        let lastId = UserDefaults.standard.string(forKey: Self.lastPaymentMethodKey)
        if let lastId, let match = paymentMethods.first(where: { $0.id == lastId }) {
            selectPaymentMethod(match)
        } else if let first = paymentMethods.first {
            selectPaymentMethod(first)
        }
    }

    /// Selects a payment method, setting funding source and auto-resolving the circle.
    func selectPaymentMethod(_ method: PaymentMethod) {
        selectedPaymentMethod = method
        UserDefaults.standard.set(method.id, forKey: Self.lastPaymentMethodKey)

        switch method.kind {
        case .circleCard:
            fundingSource = .card
            if let groupId = method.groupId,
               let circle = circles.first(where: { $0.serverId == groupId }) {
                selectedCircle = circle
                // Default to circle's split preference
                switch circle.splitMethod {
                case .equal:      splitMethod = .equal
                case .percentage: splitMethod = .percentage
                case .custom:     splitMethod = .itemized
                }
                Task { await fetchGroupMembers() }
            }
        case .wallet:
            fundingSource = .wallet
            selectedCircle = nil
        }
    }

    /// Selects a circle and fetches its server members for accurate splits.
    func selectCircle(_ circle: TallyCircle) async {
        selectedCircle = circle
        await fetchGroupMembers()
        computeEqualSplits()
    }

    /// Fetches the full member list from GET /v1/groups/:id.
    private func fetchGroupMembers() async {
        guard let groupId = selectedCircle?.serverId else { return }

        do {
            let detail: GroupDetailResponseDTO = try await APIClient.shared.get(
                path: "/v1/groups/\(groupId)"
            )
            serverMembers = detail.members
        } catch {
            // Non-fatal — we'll proceed with whatever members we have.
            serverMembers = []
        }
    }

    // MARK: - Splits

    /// Integer-only equal split across all server members of the selected circle.
    ///
    /// For `N` members splitting `totalCents`:
    /// - Each member gets `totalCents / N`
    /// - The first `totalCents % N` members each receive an extra cent
    ///
    /// This guarantees the sum of splits equals `totalCents` exactly.
    func computeEqualSplits() {
        guard !serverMembers.isEmpty else {
            splits = []
            return
        }

        let count = Int64(serverMembers.count)
        let total = totalCents
        let base = total / count
        let remainder = Int(total % count)

        splits = serverMembers.enumerated().map { index, member in
            let extra: Int64 = index < remainder ? 1 : 0
            return PaySplit(
                memberId: member.memberID,
                memberName: member.displayName,
                amountCents: base + extra,
                tipCents: 0,
                fundingSource: fundingSource
            )
        }
    }

    /// Percentage split using largest-remainder method for integer-safe distribution.
    ///
    /// Each member's percentage maps to `floor(total * pct / 100)` cents.
    /// The first N members (sorted by largest fractional remainder) each get +1 cent
    /// so that splits sum to `totalCents` exactly.
    func computePercentageSplits() {
        guard !serverMembers.isEmpty else {
            splits = []
            return
        }

        let total = totalCents

        // Build raw shares from percentages
        var rawShares: [(id: String, name: String, cents: Double)] = []
        for member in serverMembers {
            let pct = memberPercentages[member.memberID]
                ?? (100.0 / Double(serverMembers.count))
            rawShares.append((member.memberID, member.displayName, Double(total) * pct / 100.0))
        }

        // Largest-remainder allocation
        var floors = rawShares.map { Int64(floor($0.cents)) }
        let floorSum = floors.reduce(0, +)
        var remainder = Int(total - floorSum)

        let fractionals = rawShares.enumerated()
            .map { (index: $0.offset, frac: $0.element.cents - floor($0.element.cents)) }
            .sorted { $0.frac > $1.frac }

        for item in fractionals where remainder > 0 {
            floors[item.index] += 1
            remainder -= 1
        }

        splits = rawShares.enumerated().map { i, share in
            PaySplit(
                memberId: share.id,
                memberName: share.name,
                amountCents: floors[i],
                tipCents: 0,
                fundingSource: fundingSource
            )
        }
    }

    // MARK: - Session Lifecycle

    /// Creates a pay session on the backend for the selected circle.
    func createSession() async {
        guard let groupId = selectedCircle?.serverId else {
            error = .serverError(statusCode: 0, message: "No circle selected.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        let body = CreateSessionRequestDTO(
            totalCents: totalCents,
            currency: "USD",
            splitMethod: splitMethod.rawValue,
            merchantName: merchantName,
            assignmentMode: assignmentMode.rawValue
        )

        do {
            let dto: SessionResponseDTO = try await APIClient.shared.post(
                path: "/v1/groups/\(groupId)/sessions",
                body: body
            )
            session = PaySession(from: dto)
        } catch let tallyError as TallyError {
            error = tallyError
        } catch {
            self.error = .network(URLError(.unknown))
        }
    }

    /// Submits the current splits to the backend.
    func submitSplits() async {
        guard let groupId = selectedCircle?.serverId else {
            error = .serverError(statusCode: 0, message: "No circle selected.")
            return
        }
        guard let sessionId = session?.serverId else {
            error = .serverError(statusCode: 0, message: "No active session.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        let body = SetSplitsRequestDTO(
            splits: splits.map { split in
                SplitInputDTO(
                    memberId: split.memberId,
                    amountCents: split.amountCents,
                    tipCents: split.tipCents,
                    fundingSource: split.fundingSource.rawValue
                )
            }
        )

        do {
            let dto: SessionResponseDTO = try await APIClient.shared.post(
                path: "/v1/groups/\(groupId)/sessions/\(sessionId)/splits",
                body: body
            )
            session = PaySession(from: dto)
        } catch let tallyError as TallyError {
            error = tallyError
        } catch {
            self.error = .network(URLError(.unknown))
        }
    }

    /// Leader approves the session — transitions it to "ready" on the backend.
    func approveSession() async {
        guard let groupId = selectedCircle?.serverId else {
            error = .serverError(statusCode: 0, message: "No circle selected.")
            return
        }
        guard let sessionId = session?.serverId else {
            error = .serverError(statusCode: 0, message: "No active session.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let dto: SessionResponseDTO = try await APIClient.shared.post(
                path: "/v1/groups/\(groupId)/sessions/\(sessionId)/approve"
            )
            session = PaySession(from: dto)
        } catch let tallyError as TallyError {
            error = tallyError
        } catch {
            self.error = .network(URLError(.unknown))
        }
    }

    /// Simulates a card tap against the armed session.
    /// On approval, navigates to the `.complete` screen.
    func simulateTap() async {
        guard let groupId = selectedCircle?.serverId else {
            error = .serverError(statusCode: 0, message: "No circle selected.")
            return
        }
        guard let sessionId = session?.serverId else {
            error = .serverError(statusCode: 0, message: "No active session.")
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let dto: SimulateTapResponseDTO = try await APIClient.shared.post(
                path: "/v1/groups/\(groupId)/sessions/\(sessionId)/simulate-tap"
            )
            tapResult = dto
            if dto.decision == "APPROVE" {
                push(.complete)
            }
        } catch let tallyError as TallyError {
            error = tallyError
        } catch {
            self.error = .network(URLError(.unknown))
        }
    }

    // MARK: - Receipt OCR

    /// Processes a receipt image: extracts text via VisionKit OCR, then parses via backend.
    /// On success, auto-navigates to receipt review (if items found) or split config (manual fallback).
    func processReceiptImage(_ image: UIImage) async {
        guard let cgImage = image.cgImage else {
            scanError = "Could not read image"
            return
        }

        isScanning = true
        scanError = nil
        defer { isScanning = false }

        do {
            let text = try await recognizeText(from: cgImage)
            guard !text.isEmpty else {
                scanError = "No text found in image"
                return
            }
            await parseReceiptText(text)

            // Auto-navigate after successful parse
            if let receipt {
                if receipt.totalCents > 0 || !receipt.items.isEmpty {
                    push(.receiptReview)
                } else {
                    scanError = "Could not read receipt items or total. Try entering the amount manually."
                }
            }
        } catch {
            scanError = "Failed to read receipt: \(error.localizedDescription)"
        }
    }

    /// Uses Vision framework to extract text from an image.
    nonisolated func recognizeText(from image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Parses receipt text using on-device Apple Intelligence (primary) or backend (fallback).
    func parseReceiptText(_ text: String) async {
        isLoading = true
        defer { isLoading = false }

        // 1. Try Apple Intelligence (on-device, free)
        if ReceiptParser.isAvailable {
            do {
                let output = try await ReceiptParser.parse(text)
                let parsed = PayReceipt(fromOnDevice: output)

                if parsed.items.isEmpty && parsed.totalCents == 0 {
                    scanError = "Could not read receipt details. Try entering the amount manually."
                    return
                }

                receipt = parsed
                if let name = output.merchantName, !name.isEmpty {
                    merchantName = name
                }
                return
            } catch {
                // Fall through to backend
            }
        }

        // 2. Fallback: backend parse endpoint
        do {
            let body = ParseReceiptRequestBody(rawText: text)
            let response: ParseReceiptResponseDTO = try await APIClient.shared.post(
                path: "/v1/receipts/parse",
                body: body
            )
            guard let data = response.data else {
                scanError = "Could not parse receipt. Try entering the amount manually."
                return
            }

            let parsed = PayReceipt(fromParsed: data)

            if parsed.items.isEmpty && parsed.totalCents == 0 {
                scanError = "Could not read receipt details. Try entering the amount manually."
                return
            }

            receipt = parsed
            if !parsed.merchantName.isEmpty {
                merchantName = parsed.merchantName
            }
        } catch {
            scanError = "Could not parse receipt. Try entering the amount manually."
        }
    }

    // MARK: - Reset

    /// Clears all flow state so the user can start fresh.
    func reset() {
        path = []
        circles = []
        selectedCircle = nil
        serverMembers = []
        fundingSource = .card
        receipt = nil
        session = nil
        splits = []
        manualAmountCents = 0
        merchantName = ""
        splitMethod = .equal
        assignmentMode = .leader
        tapResult = nil
        memberPercentages = [:]
        paymentMethods = []
        selectedPaymentMethod = nil
        isScanning = false
        scanError = nil
        isLoading = false
        error = nil
    }
}

// MARK: - Private DTOs

/// Lightweight request body for the receipt-parse endpoint.
private struct ParseReceiptRequestBody: Encodable {
    let rawText: String

    enum CodingKeys: String, CodingKey {
        case rawText = "raw_text"
    }
}

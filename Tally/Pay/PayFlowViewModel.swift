import ClerkKit
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
    var isFetchingMembers = false
    var error: TallyError?

    // MARK: - Tip

    /// Additional tip added by the leader (cents). Separate from auto-grat on receipt.
    var tipTotalCents: Int64 = 0

    // MARK: - Computed

    /// Bill total before any tip: total − gratuity (receipt) or manualAmountCents.
    /// Derived from totalCents − tipCents because the receipt total is the most
    /// reliably parsed number (avoids issues when the parser misses a tax line).
    var preTipCents: Int64 {
        if let r = receipt {
            return r.totalCents - r.tipCents
        }
        return manualAmountCents
    }

    /// Auto-gratuity already on the receipt (locked, unchangeable).
    var receiptTipCents: Int64 {
        receipt?.tipCents ?? 0
    }

    /// The authoritative total: bill + auto-grat + additional tip.
    var totalCents: Int64 {
        preTipCents + receiptTipCents + tipTotalCents
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
    /// Also syncs the user's name from Clerk to the backend.
    func fetchCirclesWithCards() async {
        isLoading = true
        defer { isLoading = false }

        // Sync user name to backend (non-blocking, best-effort)
        let first = Clerk.shared.user?.firstName ?? ""
        let last = Clerk.shared.user?.lastName ?? ""
        if !first.isEmpty || !last.isEmpty {
            let body = ["first_name": first, "last_name": last]
            let _: MeResponseDTO? = try? await APIClient.shared.post(path: "/v1/users/me", body: body)
        }

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

        for circle in circles where !circle.isArchived {
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
                isFetchingMembers = true
                Task {
                    await fetchGroupMembers()
                    isFetchingMembers = false
                }
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
    /// Splits `preTipCents` only — tip is applied separately via `applyTipToSplits()`.
    func computeEqualSplits() {
        guard !serverMembers.isEmpty else {
            splits = []
            return
        }

        let count = Int64(serverMembers.count)
        let total = preTipCents
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

    /// Initializes equal percentages for all server members (whole integers).
    func initializeEqualPercentages() {
        guard !serverMembers.isEmpty else { return }
        let base = Int(100 / serverMembers.count)
        let remainder = 100 - base * serverMembers.count
        for (i, member) in serverMembers.enumerated() {
            memberPercentages[member.memberID] = Double(base + (i < remainder ? 1 : 0))
        }
    }

    /// When a member's percentage changes, redistribute the remainder proportionally
    /// among all other members — same algorithm as circle creation.
    func updateMemberPercentage(memberId: String, to newValue: Double) {
        let old = memberPercentages[memberId] ?? 0
        let clamped = min(max(newValue.rounded(), 0), 100)
        memberPercentages[memberId] = clamped

        let delta = clamped - old
        if delta == 0 { return }

        // Gather all other members' shares
        let otherIds = serverMembers.map(\.memberID).filter { $0 != memberId }
        if otherIds.isEmpty { return }

        let othersTotal = otherIds.reduce(0.0) { $0 + (memberPercentages[$1] ?? 0) }
        let newOthersTotal = max(othersTotal - delta, 0)

        // Round each, then fix remainder on the largest share
        var newValues = otherIds.map { id -> Double in
            let share = memberPercentages[id] ?? 0
            let proportion = othersTotal > 0 ? share / othersTotal : 1.0 / Double(otherIds.count)
            return max((newOthersTotal * proportion).rounded(), 0)
        }
        let roundedSum = newValues.reduce(0.0, +)
        let diff = newOthersTotal - roundedSum
        if diff != 0, let maxIdx = newValues.indices.max(by: { newValues[$0] < newValues[$1] }) {
            newValues[maxIdx] += diff
        }

        for (i, id) in otherIds.enumerated() {
            memberPercentages[id] = newValues[i]
        }
    }

    /// Itemized split: sums each member's assigned item totals, then distributes
    /// tax proportionally based on each member's share of the subtotal.
    ///
    /// Unassigned items are distributed equally across all members.
    /// Tip is NOT distributed here — it's applied separately via `applyTipToSplits()`.
    func computeItemizedSplits(assignments: [UUID: String], items: [PayReceiptItem]) {
        guard !serverMembers.isEmpty else {
            splits = []
            return
        }

        // 1. Sum item totals per member
        var memberItemCents: [String: Int64] = [:]
        for member in serverMembers {
            memberItemCents[member.memberID] = 0
        }

        var unassignedCents: Int64 = 0
        for item in items {
            if let memberId = assignments[item.id], memberItemCents[memberId] != nil {
                memberItemCents[memberId, default: 0] += item.totalCents
            } else {
                unassignedCents += item.totalCents
            }
        }

        // Distribute unassigned cents equally (largest-remainder)
        if unassignedCents > 0 {
            let count = Int64(serverMembers.count)
            let base = unassignedCents / count
            let remainder = Int(unassignedCents % count)
            for (index, member) in serverMembers.enumerated() {
                let extra: Int64 = index < remainder ? 1 : 0
                memberItemCents[member.memberID, default: 0] += base + extra
            }
        }

        // 2. Distribute tax proportionally to each member's item share
        let subtotal = memberItemCents.values.reduce(0, +)
        let taxPool = receipt?.taxCents ?? 0

        struct Share {
            let id: String
            let name: String
            var itemCents: Int64
            var rawTax: Double
        }

        let shares = serverMembers.map { member -> Share in
            let item = memberItemCents[member.memberID] ?? 0
            let proportion = subtotal > 0 ? Double(item) / Double(subtotal) : 1.0 / Double(serverMembers.count)
            return Share(
                id: member.memberID,
                name: member.displayName,
                itemCents: item,
                rawTax: Double(taxPool) * proportion
            )
        }

        // Largest-remainder for tax
        var taxFloors = shares.map { Int64(floor($0.rawTax)) }
        var taxRemainder = Int(taxPool - taxFloors.reduce(0, +))
        let taxFracs = shares.enumerated()
            .map { (index: $0.offset, frac: $0.element.rawTax - floor($0.element.rawTax)) }
            .sorted { $0.frac > $1.frac }
        for item in taxFracs where taxRemainder > 0 {
            taxFloors[item.index] += 1
            taxRemainder -= 1
        }

        // 3. Build splits: amountCents = items + tax, tipCents = 0 (applied later)
        splits = shares.enumerated().map { i, share in
            PaySplit(
                memberId: share.id,
                memberName: share.name,
                amountCents: share.itemCents + taxFloors[i],
                tipCents: 0,
                fundingSource: fundingSource
            )
        }
    }

    /// Percentage split using largest-remainder method for integer-safe distribution.
    /// Splits `preTipCents` only — tip is applied separately via `applyTipToSplits()`.
    func computePercentageSplits() {
        guard !serverMembers.isEmpty else {
            splits = []
            return
        }

        let total = preTipCents

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

    // MARK: - Tip

    /// Resets additional tip to 0. Auto-grat is tracked via `receiptTipCents` (computed).
    func initializeTipFromReceipt() {
        tipTotalCents = 0
    }

    /// Sets `tipTotalCents` as a percentage of `preTipCents`.
    func setTipPercentage(_ percent: Int) {
        tipTotalCents = Int64((Double(preTipCents) * Double(percent) / 100.0).rounded())
    }

    /// Distributes total tip (auto-grat + additional) proportionally across splits.
    /// When splits are equal, proportional = equal. For percentage/itemized, tip follows bill share.
    func applyTipToSplits() {
        guard !splits.isEmpty else { return }
        let tip = receiptTipCents + tipTotalCents
        guard tip > 0 else {
            for i in splits.indices { splits[i].tipCents = 0 }
            return
        }

        let count = splits.count
        let totalAmount = splits.reduce(Int64(0)) { $0 + $1.amountCents }

        guard totalAmount > 0 else {
            // Fallback to equal if all amounts are zero
            let base = tip / Int64(count)
            let remainder = Int(tip % Int64(count))
            for i in splits.indices {
                splits[i].tipCents = base + (i < remainder ? 1 : 0)
            }
            return
        }

        // Largest-remainder for proportional tip
        let rawTips = splits.map { Double(tip) * Double($0.amountCents) / Double(totalAmount) }
        var floors = rawTips.map { Int64(floor($0)) }
        var rem = Int(tip - floors.reduce(0, +))
        let fracs = rawTips.enumerated()
            .map { (index: $0.offset, frac: $0.element - floor($0.element)) }
            .sorted { $0.frac > $1.frac }
        for item in fracs where rem > 0 {
            floors[item.index] += 1
            rem -= 1
        }
        for i in splits.indices {
            splits[i].tipCents = floors[i]
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
    /// Groups text observations by vertical position so item names and prices
    /// on the same receipt line stay together (prevents price-shift parsing bugs).
    nonisolated func recognizeText(from image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []

                // Pair each observation with its recognized text and bounding box.
                // VisionKit uses normalized coords where (0,0) is bottom-left.
                struct TextBlock {
                    let text: String
                    let midY: CGFloat   // vertical center (0 = bottom, 1 = top)
                    let minX: CGFloat   // left edge
                }

                let blocks: [TextBlock] = observations.compactMap { obs in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    let box = obs.boundingBox
                    return TextBlock(
                        text: candidate.string,
                        midY: box.midY,
                        minX: box.minX
                    )
                }

                // Group blocks into lines: blocks within 1.5% vertical distance
                // are considered the same receipt line.
                let lineThreshold: CGFloat = 0.015
                var lines: [[TextBlock]] = []

                // Sort top-to-bottom (high midY = top of page)
                let sorted = blocks.sorted { $0.midY > $1.midY }

                for block in sorted {
                    if let lastIdx = lines.lastIndex(where: {
                        abs($0[0].midY - block.midY) < lineThreshold
                    }) {
                        lines[lastIdx].append(block)
                    } else {
                        lines.append([block])
                    }
                }

                // Within each line, sort left-to-right and join with tab
                let text = lines.map { line in
                    line.sorted { $0.minX < $1.minX }
                        .map(\.text)
                        .joined(separator: "\t")
                }.joined(separator: "\n")

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
                initializeTipFromReceipt()
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
            initializeTipFromReceipt()
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
        tipTotalCents = 0
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

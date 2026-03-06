import FoundationModels

// MARK: - Generable Output Types

@Generable(description: "Structured receipt data parsed from OCR text")
struct ParsedReceiptOutput {
    @Guide(description: "Restaurant or store name from receipt header. Reconstruct if OCR fragments it across lines.")
    var merchantName: String?

    @Guide(description: "Receipt date in ISO format YYYY-MM-DD. Parse any format: 'Aug16\u{2019}15' becomes '2015-08-16', '03/01/2026' becomes '2026-03-01'. Nil if no date found.")
    var receiptDate: String?

    @Guide(description: "Only purchased items (food, drinks, goods). Never include subtotal, tax, tip, gratuity, total, percentage lines, payment lines, or SNAP/EBT lines. For weighted items use the final line price, not per-unit rate.")
    var items: [ParsedItemOutput]

    @Guide(description: "Subtotal in integer cents — sum of items before tax/tip. $12.34 = 1234")
    var subtotalCents: Int?

    @Guide(description: "Tax amount in integer cents. SUM of ALL tax lines — if multiple exist (e.g. TIF 4.75% AND HST 13%), add them together.")
    var taxCents: Int?

    @Guide(description: "Tip/gratuity dollar amount in integer cents. NOT the percentage. Include auto-gratuity and service charges.")
    var tipCents: Int?

    @Guide(description: "Final total amount due in integer cents, including tax and tip.")
    var totalCents: Int?
}

@Generable(description: "A single purchased item on a receipt")
struct ParsedItemOutput {
    @Guide(description: "Item name as shown on the receipt")
    var name: String

    @Guide(description: "Quantity purchased, default 1")
    var quantity: Int

    @Guide(description: "Price per unit in integer cents")
    var unitCents: Int

    @Guide(description: "Total price for this line in integer cents (quantity * unitCents)")
    var totalCents: Int
}

// MARK: - Receipt Parser

enum ReceiptParser {

    private static let instructions = """
    Parse receipt OCR text into structured data.

    ITEMS: Only purchased products. \
    Never include subtotal, tax, tip, gratuity, total, percentage lines, payment lines, SNAP/EBT lines. \
    CRITICAL: Each item's price is the dollar amount on the SAME line as the item name. \
    Tab-separated text means columns: the item name and its price are in the same row. \
    Match each price to the item on its row — never shift prices between lines. \
    unitCents = totalCents / quantity. \
    Weighted items (e.g. "0.65 lb @ $0.59 /lb" then "BANANAS 0.38"): use the final line price as totalCents, quantity=1. \
    Letters after prices (B, S, F, T) are tax codes — ignore them.

    SUMMARY (integer cents, $12.34 = 1234): \
    subtotal = item sum before tax/tip. \
    tax = SUM of ALL tax lines (e.g. TIF + HST + GST + PST + sales tax). If multiple tax lines exist, add them together. \
    tip = gratuity dollar amount, not percentage. \
    total = final amount due.

    DATE: ISO YYYY-MM-DD. MERCHANT: store name, reconstruct if OCR-fragmented.
    """

    /// Whether Apple Intelligence is available for on-device receipt parsing.
    static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Parses OCR text into structured receipt data using on-device Apple Intelligence.
    static func parse(_ ocrText: String) async throws -> ParsedReceiptOutput {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(
            to: ocrText,
            generating: ParsedReceiptOutput.self
        )
        return response.content
    }
}

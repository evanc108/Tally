import FoundationModels

// MARK: - Generable Output Types

@Generable(description: "Structured receipt data parsed from OCR text")
struct ParsedReceiptOutput {
    @Guide(description: "Restaurant or store name from receipt header. Reconstruct if OCR fragments it across lines.")
    var merchantName: String?

    @Guide(description: "Receipt date in ISO format YYYY-MM-DD. Parse any format: 'Aug16\u{2019}15' becomes '2015-08-16', '03/01/2026' becomes '2026-03-01'. Nil if no date found.")
    var receiptDate: String?

    @Guide(description: "Only purchased items (food, drinks, goods). Never include subtotal, tax, tip, gratuity, total, percentage lines, or payment lines.")
    var items: [ParsedItemOutput]

    @Guide(description: "Subtotal in integer cents — sum of items before tax/tip. $12.34 = 1234")
    var subtotalCents: Int?

    @Guide(description: "Tax amount in integer cents. Sum all tax lines (HST, GST, sales tax, etc).")
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
    Never include subtotal, tax, tip, gratuity, total, percentage lines, payment lines. \
    unitCents = totalCents / quantity.

    SUMMARY (integer cents, $12.34 = 1234): \
    subtotal = item sum before tax/tip. \
    tax = all tax lines summed. \
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

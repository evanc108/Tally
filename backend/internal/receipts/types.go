package receipts

// ReceiptItem represents a single parsed line item from a receipt.
type ReceiptItem struct {
	Name       string `json:"name"`
	Quantity   int    `json:"quantity"`
	UnitCents  int64  `json:"unit_cents"`
	TotalCents int64  `json:"total_cents"`
}

// ParsedReceipt is the structured output of receipt parsing.
type ParsedReceipt struct {
	Items         []ReceiptItem `json:"items"`
	SubtotalCents *int64        `json:"subtotal_cents,omitempty"`
	TaxCents      *int64        `json:"tax_cents,omitempty"`
	TipCents      *int64        `json:"tip_cents,omitempty"`
	TotalCents    *int64        `json:"total_cents,omitempty"`
	Confidence    float64       `json:"confidence"`
	Warnings      []string      `json:"warnings,omitempty"`
}

package receipts

import (
	"math"
	"testing"
)

func TestToReceipt_BasicConversion(t *testing.T) {
	g := NewGeminiClient("", "")
	parsed := &geminiParsedReceipt{
		MerchantName: "Test Diner",
		ReceiptDate:  "2026-03-01",
		Items: []geminiItem{
			{Name: "Burger", Quantity: 1, UnitCents: 1299, TotalCents: 1299},
			{Name: "Fries", Quantity: 2, UnitCents: 399, TotalCents: 798},
		},
		SubtotalCents: 2097,
		TaxCents:      168,
		TipCents:      400,
		TotalCents:    2665,
	}

	result := g.toReceipt(parsed)

	if result.MerchantName != "Test Diner" {
		t.Errorf("MerchantName = %q, want %q", result.MerchantName, "Test Diner")
	}
	if result.ReceiptDate != "2026-03-01" {
		t.Errorf("ReceiptDate = %q, want %q", result.ReceiptDate, "2026-03-01")
	}
	if len(result.Items) != 2 {
		t.Fatalf("Items count = %d, want 2", len(result.Items))
	}
	if result.Items[0].Name != "Burger" {
		t.Errorf("Items[0].Name = %q, want %q", result.Items[0].Name, "Burger")
	}
	if result.Items[1].Quantity != 2 {
		t.Errorf("Items[1].Quantity = %d, want 2", result.Items[1].Quantity)
	}
	if result.SubtotalCents == nil || *result.SubtotalCents != 2097 {
		t.Errorf("SubtotalCents = %v, want 2097", result.SubtotalCents)
	}
	if result.TaxCents == nil || *result.TaxCents != 168 {
		t.Errorf("TaxCents = %v, want 168", result.TaxCents)
	}
	if result.TipCents == nil || *result.TipCents != 400 {
		t.Errorf("TipCents = %v, want 400", result.TipCents)
	}
	if result.TotalCents == nil || *result.TotalCents != 2665 {
		t.Errorf("TotalCents = %v, want 2665", result.TotalCents)
	}
	if result.Confidence != 0.9 {
		t.Errorf("Confidence = %f, want 0.9", result.Confidence)
	}
	if len(result.Warnings) != 0 {
		t.Errorf("Warnings = %v, want empty", result.Warnings)
	}
}

func TestToReceipt_ZeroQuantityDefaultsToOne(t *testing.T) {
	g := NewGeminiClient("", "")
	parsed := &geminiParsedReceipt{
		Items: []geminiItem{
			{Name: "Widget", Quantity: 0, UnitCents: 500, TotalCents: 500},
			{Name: "Gadget", Quantity: -1, UnitCents: 300, TotalCents: 300},
		},
		SubtotalCents: 800,
	}

	result := g.toReceipt(parsed)

	for i, item := range result.Items {
		if item.Quantity != 1 {
			t.Errorf("Items[%d].Quantity = %d, want 1 (default for non-positive)", i, item.Quantity)
		}
	}
}

func TestToReceipt_CrossValidationWarning(t *testing.T) {
	g := NewGeminiClient("", "")
	// Items sum to 2000, but subtotal says 3000 — over 50 cent threshold
	parsed := &geminiParsedReceipt{
		Items: []geminiItem{
			{Name: "A", Quantity: 1, UnitCents: 1000, TotalCents: 1000},
			{Name: "B", Quantity: 1, UnitCents: 1000, TotalCents: 1000},
		},
		SubtotalCents: 3000,
		TotalCents:    3000,
	}

	result := g.toReceipt(parsed)

	if len(result.Warnings) != 1 {
		t.Fatalf("Warnings count = %d, want 1", len(result.Warnings))
	}
	if result.Confidence != 0.7 {
		t.Errorf("Confidence = %f, want 0.7 (reduced due to mismatch)", result.Confidence)
	}
}

func TestToReceipt_NoWarningWithinTolerance(t *testing.T) {
	g := NewGeminiClient("", "")
	// Items sum to 1000, subtotal says 1030 — within 50 cent tolerance
	parsed := &geminiParsedReceipt{
		Items: []geminiItem{
			{Name: "A", Quantity: 1, UnitCents: 1000, TotalCents: 1000},
		},
		SubtotalCents: 1030,
		TotalCents:    1030,
	}

	result := g.toReceipt(parsed)

	if len(result.Warnings) != 0 {
		t.Errorf("Warnings = %v, want none (within 50 cent tolerance)", result.Warnings)
	}
	if result.Confidence != 0.9 {
		t.Errorf("Confidence = %f, want 0.9", result.Confidence)
	}
}

func TestToReceipt_FallbackSubtotalFromItems(t *testing.T) {
	g := NewGeminiClient("", "")
	// No subtotal provided — should compute from items
	parsed := &geminiParsedReceipt{
		Items: []geminiItem{
			{Name: "A", Quantity: 1, UnitCents: 500, TotalCents: 500},
			{Name: "B", Quantity: 1, UnitCents: 700, TotalCents: 700},
		},
	}

	result := g.toReceipt(parsed)

	if result.SubtotalCents == nil || *result.SubtotalCents != 1200 {
		t.Errorf("SubtotalCents = %v, want 1200 (computed from items)", result.SubtotalCents)
	}
}

func TestToReceipt_FallbackTotalFromSubtotalTaxTip(t *testing.T) {
	g := NewGeminiClient("", "")
	// No total — should compute from subtotal + tax + tip
	parsed := &geminiParsedReceipt{
		Items: []geminiItem{
			{Name: "A", Quantity: 1, UnitCents: 1000, TotalCents: 1000},
		},
		SubtotalCents: 1000,
		TaxCents:      80,
		TipCents:      200,
	}

	result := g.toReceipt(parsed)

	if result.TotalCents == nil || *result.TotalCents != 1280 {
		t.Errorf("TotalCents = %v, want 1280 (1000 + 80 + 200)", result.TotalCents)
	}
}

func TestToReceipt_ZeroFieldsAreNil(t *testing.T) {
	g := NewGeminiClient("", "")
	parsed := &geminiParsedReceipt{
		Items: []geminiItem{
			{Name: "A", Quantity: 1, UnitCents: 1000, TotalCents: 1000},
		},
		SubtotalCents: 1000,
		TaxCents:      0,
		TipCents:      0,
		TotalCents:    0, // zero means not found
	}

	result := g.toReceipt(parsed)

	if result.TaxCents != nil {
		t.Errorf("TaxCents = %v, want nil (zero means not found)", result.TaxCents)
	}
	if result.TipCents != nil {
		t.Errorf("TipCents = %v, want nil (zero means not found)", result.TipCents)
	}
	// TotalCents should be computed from subtotal fallback
	if result.TotalCents == nil || *result.TotalCents != 1000 {
		t.Errorf("TotalCents = %v, want 1000 (fallback from subtotal)", result.TotalCents)
	}
}

func TestToReceipt_EmptyItems(t *testing.T) {
	g := NewGeminiClient("", "")
	parsed := &geminiParsedReceipt{
		MerchantName:  "Empty Store",
		SubtotalCents: 0,
		TotalCents:    0,
	}

	result := g.toReceipt(parsed)

	if len(result.Items) != 0 {
		t.Errorf("Items count = %d, want 0", len(result.Items))
	}
	if result.SubtotalCents != nil {
		t.Errorf("SubtotalCents = %v, want nil (no items, zero subtotal)", result.SubtotalCents)
	}
}

func TestFormatCents(t *testing.T) {
	tests := []struct {
		cents int64
		want  string
	}{
		{0, "0.00"},
		{1, "0.01"},
		{100, "1.00"},
		{1299, "12.99"},
		{21700, "217.00"},
		{-500, "-5.00"},
		{-1, "-0.01"},
	}
	for _, tt := range tests {
		got := formatCents(tt.cents)
		if got != tt.want {
			t.Errorf("formatCents(%d) = %q, want %q", tt.cents, got, tt.want)
		}
	}
}

func TestAbs64(t *testing.T) {
	tests := []struct {
		n, want int64
	}{
		{0, 0},
		{5, 5},
		{-5, 5},
		{math.MinInt64 + 1, math.MaxInt64},
	}
	for _, tt := range tests {
		got := abs64(tt.n)
		if got != tt.want {
			t.Errorf("abs64(%d) = %d, want %d", tt.n, got, tt.want)
		}
	}
}

func TestGeminiClient_Available(t *testing.T) {
	withKey := NewGeminiClient("test-key", "")
	if !withKey.Available() {
		t.Error("Expected Available() = true when key is set")
	}

	noKey := NewGeminiClient("", "")
	if noKey.Available() {
		t.Error("Expected Available() = false when key is empty")
	}
}

func TestGeminiClient_DefaultModel(t *testing.T) {
	g := NewGeminiClient("key", "")
	if g.model != "gemini-2.5-flash-lite" {
		t.Errorf("default model = %q, want %q", g.model, "gemini-2.5-flash-lite")
	}

	g2 := NewGeminiClient("key", "gemini-pro")
	if g2.model != "gemini-pro" {
		t.Errorf("custom model = %q, want %q", g2.model, "gemini-pro")
	}
}

package receipts

import (
	"encoding/json"
	"testing"
)

func TestReceiptItem_JSONRoundTrip(t *testing.T) {
	item := ReceiptItem{
		Name:       "Burger Deluxe",
		Quantity:   2,
		UnitCents:  1299,
		TotalCents: 2598,
	}

	data, err := json.Marshal(item)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var decoded ReceiptItem
	if err := json.Unmarshal(data, &decoded); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}

	if decoded.Name != item.Name {
		t.Errorf("Name = %q, want %q", decoded.Name, item.Name)
	}
	if decoded.Quantity != item.Quantity {
		t.Errorf("Quantity = %d, want %d", decoded.Quantity, item.Quantity)
	}
	if decoded.UnitCents != item.UnitCents {
		t.Errorf("UnitCents = %d, want %d", decoded.UnitCents, item.UnitCents)
	}
	if decoded.TotalCents != item.TotalCents {
		t.Errorf("TotalCents = %d, want %d", decoded.TotalCents, item.TotalCents)
	}
}

func TestParsedReceipt_JSONKeys(t *testing.T) {
	subtotal := int64(1000)
	tax := int64(80)
	tip := int64(200)
	total := int64(1280)

	receipt := ParsedReceipt{
		Items: []ReceiptItem{
			{Name: "Test Item", Quantity: 1, UnitCents: 1000, TotalCents: 1000},
		},
		SubtotalCents: &subtotal,
		TaxCents:      &tax,
		TipCents:      &tip,
		TotalCents:    &total,
		MerchantName:  "Test Store",
		ReceiptDate:   "2026-03-01",
		Confidence:    0.95,
		Warnings:      []string{"test warning"},
	}

	data, err := json.Marshal(receipt)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	// Verify JSON key names match snake_case convention
	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatalf("unmarshal raw: %v", err)
	}

	requiredKeys := []string{"items", "subtotal_cents", "tax_cents", "tip_cents", "total_cents", "merchant_name", "receipt_date", "confidence", "warnings"}
	for _, key := range requiredKeys {
		if _, ok := raw[key]; !ok {
			t.Errorf("missing JSON key %q", key)
		}
	}
}

func TestParsedReceipt_OmitsNilFields(t *testing.T) {
	receipt := ParsedReceipt{
		Items:      []ReceiptItem{},
		Confidence: 0.9,
	}

	data, err := json.Marshal(receipt)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	var raw map[string]json.RawMessage
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatalf("unmarshal raw: %v", err)
	}

	// Nil pointer fields should be omitted
	omittedKeys := []string{"subtotal_cents", "tax_cents", "tip_cents", "total_cents", "merchant_name", "receipt_date", "warnings"}
	for _, key := range omittedKeys {
		if _, ok := raw[key]; ok {
			t.Errorf("expected JSON key %q to be omitted (nil), but it was present", key)
		}
	}
}

func TestParsedReceipt_IntegerCentsOnly(t *testing.T) {
	// Verify monetary fields are integer cents, not float dollars
	subtotal := int64(1299)
	receipt := ParsedReceipt{
		Items:         []ReceiptItem{{Name: "Item", Quantity: 1, UnitCents: 1299, TotalCents: 1299}},
		SubtotalCents: &subtotal,
		Confidence:    0.9,
	}

	data, err := json.Marshal(receipt)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}

	// Parse as generic and verify subtotal_cents is an integer
	var raw map[string]interface{}
	if err := json.Unmarshal(data, &raw); err != nil {
		t.Fatalf("unmarshal raw: %v", err)
	}

	v, ok := raw["subtotal_cents"]
	if !ok {
		t.Fatal("subtotal_cents not in JSON")
	}
	num, ok := v.(float64) // JSON numbers decode as float64
	if !ok {
		t.Fatalf("subtotal_cents is not a number: %T", v)
	}
	if num != 1299 {
		t.Errorf("subtotal_cents = %v, want 1299", num)
	}
}

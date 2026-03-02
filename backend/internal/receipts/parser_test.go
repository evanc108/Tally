package receipts

import (
	"fmt"
	"os"
	"strings"
	"testing"
)

func int64Ptr(v int64) *int64 { return &v }

func TestParseReceiptText(t *testing.T) {
	tests := []struct {
		name           string
		input          string
		wantItemCount  int
		wantSubtotal   *int64
		wantTax        *int64
		wantTip        *int64
		wantTotal      *int64
		wantMinConf    float64
		wantMaxConf    float64
		wantMinWarns   int
		checkFirstItem *ReceiptItem
	}{
		{
			name: "simple restaurant receipt",
			input: "OLIVE GARDEN\nTable 4 Server: Mike\n" +
				"Chicken Parm  18.99\n" +
				"Iced Tea  2.99\n" +
				"Caesar Salad  9.49\n" +
				"Subtotal  31.47\n" +
				"Tax  2.52\n" +
				"Total  33.99\n",
			wantItemCount: 3,
			wantSubtotal:  int64Ptr(3147),
			wantTax:       int64Ptr(252),
			wantTotal:     int64Ptr(3399),
			wantMinConf:   0.5,
		},
		{
			name: "receipt with quantities",
			input: "2 Iced Tea  5.98\n" +
				"1 Chicken Parm  18.99\n" +
				"Subtotal  24.97\n" +
				"Tax  2.00\n" +
				"Total  26.97\n",
			wantItemCount: 2,
			wantSubtotal:  int64Ptr(2497),
			wantTax:       int64Ptr(200),
			wantTotal:     int64Ptr(2697),
			wantMinConf:   0.5,
			checkFirstItem: &ReceiptItem{
				Name:       "Iced Tea",
				Quantity:   2,
				UnitCents:  299,
				TotalCents: 598,
			},
		},
		{
			name: "receipt with tip",
			input: "Burger  12.99\n" +
				"Fries  4.99\n" +
				"Subtotal  17.98\n" +
				"Tax  1.44\n" +
				"Tip  3.60\n" +
				"Total  23.02\n",
			wantItemCount: 2,
			wantSubtotal:  int64Ptr(1798),
			wantTax:       int64Ptr(144),
			wantTip:       int64Ptr(360),
			wantTotal:     int64Ptr(2302),
			wantMinConf:   0.5,
		},
		{
			name: "no subtotal",
			input: "Pasta  14.99\n" +
				"Wine  8.00\n" +
				"Tax  1.84\n" +
				"Total  24.83\n",
			wantItemCount: 2,
			wantTax:       int64Ptr(184),
			wantTotal:     int64Ptr(2483),
			wantMinConf:   0.1,
		},
		{
			name: "modifier lines",
			input: "Burger  12.99\n" +
				"+ Extra Cheese  1.50\n" +
				"Subtotal  14.49\n" +
				"Tax  1.16\n" +
				"Total  15.65\n",
			wantItemCount: 2,
			wantSubtotal:  int64Ptr(1449),
			wantMinConf:   0.5,
		},
		{
			name: "discount lines",
			input: "Steak  34.50\n" +
				"Wine  12.00\n" +
				"Happy Hour  -3.00\n" +
				"Subtotal  43.50\n" +
				"Tax  3.48\n" +
				"Total  46.98\n",
			wantItemCount: 3,
			wantSubtotal:  int64Ptr(4350),
			wantMinConf:   0.5,
		},
		{
			name: "dot leaders",
			input: "Chicken Parm......18.99\n" +
				"Iced Tea..........2.99\n" +
				"Subtotal  21.98\n" +
				"Total  21.98\n",
			wantItemCount: 2,
			wantSubtotal:  int64Ptr(2198),
			wantMinConf:   0.5,
		},
		{
			name: "dash leaders not negative",
			input: "Steak --- 34.50\n" +
				"Subtotal  34.50\n" +
				"Total  34.50\n",
			wantItemCount: 1,
			wantSubtotal:  int64Ptr(3450),
			wantMinConf:   0.5,
			checkFirstItem: &ReceiptItem{
				Name:       "Steak",
				Quantity:   1,
				UnitCents:  3450,
				TotalCents: 3450,
			},
		},
		{
			name: "multi-word keywords",
			input: "Pasta  14.99\n" +
				"Sub Total  14.99\n" +
				"Sales Tax  1.20\n" +
				"Grand Total  16.19\n",
			wantItemCount: 1,
			wantSubtotal:  int64Ptr(1499),
			wantTax:       int64Ptr(120),
			wantTotal:     int64Ptr(1619),
			wantMinConf:   0.5,
		},
		{
			name: "amount due as total",
			input: "Burger  12.99\n" +
				"Amount Due  12.99\n",
			wantItemCount: 1,
			wantTotal:     int64Ptr(1299),
			wantMinConf:   0.1,
		},
		{
			name: "phone number ignored",
			input: "(555) 123-4567\n" +
				"Burger  12.99\n" +
				"Total  12.99\n",
			wantItemCount: 1,
			wantTotal:     int64Ptr(1299),
		},
		{
			name: "date line ignored",
			input: "03/01/2026  7:45 PM\n" +
				"Burger  12.99\n" +
				"Total  12.99\n",
			wantItemCount: 1,
			wantTotal:     int64Ptr(1299),
		},
		{
			name: "credit card line skipped",
			input: "Burger  12.99\n" +
				"Total  12.99\n" +
				"Visa ***1234  12.99\n",
			wantItemCount: 1,
			wantTotal:     int64Ptr(1299),
		},
		{
			name:          "empty input",
			input:         "",
			wantItemCount: 0,
			wantMaxConf:   0.15,
		},
		{
			name:          "garbage input no prices",
			input:         "Hello world\nThis is not a receipt\nNo prices here",
			wantItemCount: 0,
			wantMaxConf:   0.15,
		},
		{
			name:          "only prices no names",
			input:         "18.99\n5.98\n",
			wantItemCount: 2,
			wantMinConf:   0.1,
		},
		{
			name:         "sum check passes",
			input:        "A  10.00\nB  20.00\nSubtotal  30.00\n",
			wantItemCount: 2,
			wantSubtotal:  int64Ptr(3000),
			wantMinConf:   0.5,
			wantMinWarns:  0,
		},
		{
			name:          "sum check fails",
			input:         "A  10.00\nB  20.00\nSubtotal  35.00\n",
			wantItemCount: 2,
			wantSubtotal:  int64Ptr(3500),
			wantMinWarns:  1,
		},
		{
			name: "total cross-check passes",
			input: "A  10.00\n" +
				"Subtotal  10.00\n" +
				"Tax  0.80\n" +
				"Total  10.80\n",
			wantItemCount: 1,
			wantSubtotal:  int64Ptr(1000),
			wantTax:       int64Ptr(80),
			wantTotal:     int64Ptr(1080),
			wantMinConf:   0.7,
		},
		{
			name: "quantity with x separator",
			input: "2x Burger  25.98\n" +
				"Subtotal  25.98\n",
			wantItemCount: 1,
			wantSubtotal:  int64Ptr(2598),
			checkFirstItem: &ReceiptItem{
				Name:       "Burger",
				Quantity:   2,
				UnitCents:  1299,
				TotalCents: 2598,
			},
		},
		{
			name: "gratuity as tip",
			input: "Steak  34.99\n" +
				"Subtotal  34.99\n" +
				"Tax  2.80\n" +
				"Gratuity  7.00\n" +
				"Total  44.79\n",
			wantItemCount: 1,
			wantTip:       int64Ptr(700),
			wantTotal:     int64Ptr(4479),
		},
		{
			name: "service charge as tip",
			input: "Dinner  50.00\n" +
				"Subtotal  50.00\n" +
				"Service Charge  10.00\n" +
				"Total  60.00\n",
			wantItemCount: 1,
			wantTip:       int64Ptr(1000),
			wantTotal:     int64Ptr(6000),
		},
		{
			name: "comma-formatted prices",
			input: "Premium Wagyu  1,234.56\n" +
				"Subtotal  1,234.56\n" +
				"Tax  98.76\n" +
				"Total  1,333.32\n",
			wantItemCount: 1,
			wantSubtotal:  int64Ptr(123456),
			wantTax:       int64Ptr(9876),
			wantTotal:     int64Ptr(133332),
			wantMinConf:   0.5,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := ParseReceiptText(tt.input)
			if result == nil {
				t.Fatal("ParseReceiptText returned nil")
			}

			if len(result.Items) != tt.wantItemCount {
				t.Errorf("item count: got %d, want %d", len(result.Items), tt.wantItemCount)
				for i, item := range result.Items {
					t.Logf("  item[%d]: %+v", i, item)
				}
			}

			checkPtr := func(name string, got, want *int64) {
				t.Helper()
				if want == nil {
					return
				}
				if got == nil {
					t.Errorf("%s: got nil, want %d", name, *want)
					return
				}
				if *got != *want {
					t.Errorf("%s: got %d, want %d", name, *got, *want)
				}
			}

			checkPtr("subtotal", result.SubtotalCents, tt.wantSubtotal)
			checkPtr("tax", result.TaxCents, tt.wantTax)
			checkPtr("tip", result.TipCents, tt.wantTip)
			checkPtr("total", result.TotalCents, tt.wantTotal)

			if tt.wantMinConf > 0 && result.Confidence < tt.wantMinConf {
				t.Errorf("confidence too low: got %f, want >= %f", result.Confidence, tt.wantMinConf)
			}
			if tt.wantMaxConf > 0 && result.Confidence > tt.wantMaxConf {
				t.Errorf("confidence too high: got %f, want <= %f", result.Confidence, tt.wantMaxConf)
			}
			if tt.wantMinWarns > 0 && len(result.Warnings) < tt.wantMinWarns {
				t.Errorf("warnings: got %d, want >= %d", len(result.Warnings), tt.wantMinWarns)
			}

			if tt.checkFirstItem != nil && len(result.Items) > 0 {
				got := result.Items[0]
				want := *tt.checkFirstItem
				if got.Name != want.Name {
					t.Errorf("first item name: got %q, want %q", got.Name, want.Name)
				}
				if got.Quantity != want.Quantity {
					t.Errorf("first item quantity: got %d, want %d", got.Quantity, want.Quantity)
				}
				if got.UnitCents != want.UnitCents {
					t.Errorf("first item unit_cents: got %d, want %d", got.UnitCents, want.UnitCents)
				}
				if got.TotalCents != want.TotalCents {
					t.Errorf("first item total_cents: got %d, want %d", got.TotalCents, want.TotalCents)
				}
			}
		})
	}
}

func TestParseReceiptText_Fixtures(t *testing.T) {
	fixtures := []struct {
		file          string
		wantMinItems  int
		wantMaxItems  int
		wantSubtotal  bool
		wantTotal     bool
	}{
		{"testdata/simple_restaurant.txt", 3, 3, true, true},
		{"testdata/restaurant_with_quantities.txt", 3, 3, true, true},
		{"testdata/restaurant_with_tip.txt", 4, 4, true, true},
		{"testdata/restaurant_with_discounts.txt", 4, 5, true, true},
		{"testdata/messy_formatting.txt", 4, 6, true, true},
		{"testdata/minimal_receipt.txt", 3, 3, false, true},
		{"testdata/empty.txt", 0, 0, false, false},
		{"testdata/no_prices.txt", 0, 0, false, false},
	}

	for _, f := range fixtures {
		t.Run(f.file, func(t *testing.T) {
			data, err := os.ReadFile(f.file)
			if err != nil {
				t.Fatalf("read fixture: %v", err)
			}

			result := ParseReceiptText(string(data))
			if result == nil {
				t.Fatal("nil result")
			}

			if len(result.Items) < f.wantMinItems || len(result.Items) > f.wantMaxItems {
				t.Errorf("items: got %d, want %d–%d", len(result.Items), f.wantMinItems, f.wantMaxItems)
				for i, item := range result.Items {
					t.Logf("  item[%d]: %+v", i, item)
				}
			}
			if f.wantSubtotal && result.SubtotalCents == nil {
				t.Error("expected subtotal, got nil")
			}
			if f.wantTotal && result.TotalCents == nil {
				t.Error("expected total, got nil")
			}
		})
	}
}

func TestParseReceiptText_VeryLongInput(t *testing.T) {
	var sb strings.Builder
	for i := 0; i < 500; i++ {
		sb.WriteString(fmt.Sprintf("Item %d  %d.99\n", i, i%100))
	}
	result := ParseReceiptText(sb.String())
	if result == nil {
		t.Fatal("nil result")
	}
	if len(result.Items) == 0 {
		t.Error("expected items from long input")
	}
}

func TestParseReceiptText_DiscountTotalCents(t *testing.T) {
	input := "Steak  34.50\nDiscount  -5.00\n"
	result := ParseReceiptText(input)

	if len(result.Items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(result.Items))
	}

	discount := result.Items[1]
	if discount.TotalCents >= 0 {
		t.Errorf("discount should be negative: got %d", discount.TotalCents)
	}
}

func TestParseReceiptText_ModifierStripsPrefix(t *testing.T) {
	tests := []struct {
		line     string
		wantName string
	}{
		{"+ Extra Cheese  1.50", "Extra Cheese"},
		{"Add Bacon  2.00", "Bacon"},
		{"Extra Guac  1.50", "Guac"},
	}

	for _, tt := range tests {
		t.Run(tt.line, func(t *testing.T) {
			result := ParseReceiptText(tt.line)
			if len(result.Items) != 1 {
				t.Fatalf("expected 1 item, got %d", len(result.Items))
			}
			if result.Items[0].Name != tt.wantName {
				t.Errorf("name: got %q, want %q", result.Items[0].Name, tt.wantName)
			}
		})
	}
}

func TestCustomParserConfig(t *testing.T) {
	cfg := DefaultConfig()
	cfg.SummaryKeywords["service fee"] = FieldTip
	cfg.SkipKeywords = append(cfg.SkipKeywords, "loyalty")

	input := "Burger  12.99\nService Fee  2.00\nLoyalty Points  12.99\n"
	result := cfg.Parse(input)

	if result.TipCents == nil {
		t.Fatal("expected service fee as tip")
	}
	if *result.TipCents != 200 {
		t.Errorf("tip: got %d, want 200", *result.TipCents)
	}
	if len(result.Items) != 1 {
		t.Errorf("expected 1 item (loyalty line skipped), got %d", len(result.Items))
	}
}

func FuzzParseReceiptText(f *testing.F) {
	f.Add("1 Burger  12.99\nTax  1.04\nTotal  14.03")
	f.Add("")
	f.Add("random garbage no prices here")
	f.Add("Chicken Parm......18.99\nSub Total  18.99")
	f.Add("-3.00\n+Extra  1.50")
	f.Add("2x Beer  14.00\nGratuity  2.80\nGrand Total  16.80")
	f.Add("1,234.56\nSubtotal  1,234.56")

	f.Fuzz(func(t *testing.T, input string) {
		result := ParseReceiptText(input)
		if result == nil {
			t.Fatal("parser returned nil")
		}

		for _, item := range result.Items {
			if item.Quantity <= 0 {
				t.Errorf("item %q has invalid quantity: %d", item.Name, item.Quantity)
			}
		}

		if result.Confidence < 0 || result.Confidence > 1.0 {
			t.Errorf("confidence out of range: %f", result.Confidence)
		}
	})
}

func BenchmarkParseReceiptText(b *testing.B) {
	data, err := os.ReadFile("testdata/simple_restaurant.txt")
	if err != nil {
		b.Fatal(err)
	}
	receipt := string(data)
	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		ParseReceiptText(receipt)
	}
}

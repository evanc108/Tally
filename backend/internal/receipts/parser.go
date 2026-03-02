package receipts

import (
	"fmt"
	"math"
	"regexp"
	"strconv"
	"strings"
)

// SummaryField identifies which ParsedReceipt field a summary keyword maps to.
type SummaryField int

const (
	FieldSubtotal SummaryField = iota
	FieldTax
	FieldTip
	FieldTotal
)

// ParserConfig holds all configurable rules for receipt text parsing.
// Classification decisions are driven by these maps and patterns rather than
// inline conditionals, so new POS formats and locales can be supported by
// adjusting configuration alone.
type ParserConfig struct {
	// PricePattern matches decimal prices (e.g., "12.99", "1,234.56").
	PricePattern *regexp.Regexp

	// SummaryKeywords maps lowercased keywords to their receipt summary field.
	// Lines matching these keywords are extracted as subtotal/tax/tip/total
	// rather than treated as line items.
	SummaryKeywords map[string]SummaryField

	// SkipKeywords cause a line to be ignored even when it contains a price.
	// Matched case-insensitively against the full line.
	SkipKeywords []string

	// ModifierPrefixes identify add-on items ("+", "add ", "extra ").
	// Stripped from the item name during parsing; the line is still treated
	// as a separate line item.
	ModifierPrefixes []string

	// TrailingFillerPattern strips trailing dots, dashes, and spaces that
	// receipts use as visual filler between the item name and price.
	TrailingFillerPattern *regexp.Regexp

	// QuantityPattern matches a leading quantity prefix like "2 " or "2x ".
	QuantityPattern *regexp.Regexp

	// CrossValidationTolerance is the maximum acceptable difference in cents
	// when cross-checking item sums against stated totals (handles rounding).
	CrossValidationTolerance int64

	// Confidence scoring weights.
	MatchScore           float64 // Awarded when a cross-validation check passes.
	MismatchScore        float64 // Awarded when a cross-validation check fails.
	ItemsFoundScore      float64 // Base score for finding at least one item.
	NoCheckConfidence    float64 // Confidence when no cross-checks are possible.
	ConfidenceNormalizer float64 // Added to the check count in the denominator.
}

// multiSpaceRe collapses runs of whitespace to a single space.
var multiSpaceRe = regexp.MustCompile(`\s{2,}`)

// DefaultConfig returns the standard parser configuration for US restaurant receipts.
func DefaultConfig() ParserConfig {
	return ParserConfig{
		PricePattern: regexp.MustCompile(`\d{1,3}(?:,\d{3})*\.\d{2}`),
		SummaryKeywords: map[string]SummaryField{
			"subtotal":       FieldSubtotal,
			"sub total":      FieldSubtotal,
			"sub-total":      FieldSubtotal,
			"tax":            FieldTax,
			"sales tax":      FieldTax,
			"hst":            FieldTax,
			"gst":            FieldTax,
			"vat":            FieldTax,
			"tip":            FieldTip,
			"gratuity":       FieldTip,
			"service charge": FieldTip,
			"total":          FieldTotal,
			"amount due":     FieldTotal,
			"balance due":    FieldTotal,
			"balance":        FieldTotal,
			"grand total":    FieldTotal,
			"amount":         FieldTotal,
			"total due":      FieldTotal,
			"please pay":     FieldTotal,
		},
		SkipKeywords: []string{
			"visa", "mastercard", "amex", "american express",
			"discover", "diners", "jcb", "unionpay",
			"debit", "credit card", "change due",
		},
		ModifierPrefixes:         []string{"+", "add ", "extra "},
		TrailingFillerPattern:    regexp.MustCompile(`[\.\-\s]+$`),
		QuantityPattern:          regexp.MustCompile(`^(\d+)\s*[xX]?\s+`),
		CrossValidationTolerance: 10,
		MatchScore:               1.0,
		MismatchScore:            0.3,
		ItemsFoundScore:          0.5,
		NoCheckConfidence:        0.1,
		ConfidenceNormalizer:     0.5,
	}
}

// Parse processes raw OCR text into a structured ParsedReceipt.
// It never returns an error; malformed input yields an empty result with low
// confidence and warnings. This makes the function safe to call on any input.
func (cfg ParserConfig) Parse(rawText string) *ParsedReceipt {
	result := &ParsedReceipt{
		Items:    []ReceiptItem{},
		Warnings: []string{},
	}

	for _, raw := range strings.Split(rawText, "\n") {
		line := strings.TrimSpace(raw)
		if line == "" {
			continue
		}

		normalized := multiSpaceRe.ReplaceAllString(line, " ")
		lower := strings.ToLower(normalized)

		priceMatches := cfg.PricePattern.FindAllStringIndex(normalized, -1)
		if len(priceMatches) == 0 {
			continue
		}

		if cfg.matchesSkipKeyword(lower) {
			continue
		}

		// Use the rightmost price on the line (receipts put the total at the end).
		lastMatch := priceMatches[len(priceMatches)-1]
		priceStr := normalized[lastMatch[0]:lastMatch[1]]
		cents := dollarsToCents(priceStr)

		if isNegativePrice(normalized, lastMatch[0]) {
			cents = -cents
		}

		if field, ok := cfg.matchesSummaryKeyword(lower); ok {
			cfg.setSummaryField(result, field, cents)
			continue
		}

		textBeforePrice := strings.TrimSpace(normalized[:lastMatch[0]])
		item := cfg.parseLineItem(textBeforePrice, cents)
		result.Items = append(result.Items, item)
	}

	cfg.computeConfidence(result)
	return result
}

// ParseReceiptText is a convenience wrapper using DefaultConfig.
func ParseReceiptText(rawText string) *ParsedReceipt {
	return DefaultConfig().Parse(rawText)
}

// matchesSkipKeyword returns true if the lowercased line contains any skip keyword.
func (cfg ParserConfig) matchesSkipKeyword(lower string) bool {
	for _, kw := range cfg.SkipKeywords {
		if strings.Contains(lower, kw) {
			return true
		}
	}
	return false
}

// matchesSummaryKeyword returns the best-matching summary field for a line.
// Earliest position wins; for ties, the longest keyword wins. This prevents
// "total" from overriding "sub total" or "grand total".
func (cfg ParserConfig) matchesSummaryKeyword(lower string) (SummaryField, bool) {
	bestPos := -1
	bestLen := 0
	var bestField SummaryField
	matched := false

	for kw, field := range cfg.SummaryKeywords {
		pos := strings.Index(lower, kw)
		if pos < 0 {
			continue
		}
		if !matched || pos < bestPos || (pos == bestPos && len(kw) > bestLen) {
			bestPos = pos
			bestLen = len(kw)
			bestField = field
			matched = true
		}
	}

	return bestField, matched
}

// setSummaryField assigns a cents value to the corresponding ParsedReceipt field.
func (cfg ParserConfig) setSummaryField(r *ParsedReceipt, field SummaryField, cents int64) {
	switch field {
	case FieldSubtotal:
		r.SubtotalCents = &cents
	case FieldTax:
		r.TaxCents = &cents
	case FieldTip:
		r.TipCents = &cents
	case FieldTotal:
		r.TotalCents = &cents
	}
}

// parseLineItem extracts quantity, name, and unit price from the text preceding
// the rightmost price on a line.
func (cfg ParserConfig) parseLineItem(text string, totalCents int64) ReceiptItem {
	quantity := 1
	name := text

	// Strip modifier prefixes ("+", "add ", "extra ").
	lowerName := strings.ToLower(name)
	for _, prefix := range cfg.ModifierPrefixes {
		if strings.HasPrefix(lowerName, prefix) {
			name = strings.TrimSpace(name[len(prefix):])
			break
		}
	}

	// Check for quantity prefix ("2 Iced Tea", "2x Burger").
	if matches := cfg.QuantityPattern.FindStringSubmatch(name); len(matches) > 1 {
		if q, err := strconv.Atoi(matches[1]); err == nil && q > 0 {
			quantity = q
			name = name[len(matches[0]):]
		}
	}

	// Strip trailing filler (dots, dashes, spaces between name and price).
	name = cfg.TrailingFillerPattern.ReplaceAllString(name, "")
	name = strings.TrimSpace(name)

	unitCents := totalCents
	if quantity > 1 {
		unitCents = totalCents / int64(quantity)
	}

	return ReceiptItem{
		Name:       name,
		Quantity:   quantity,
		UnitCents:  unitCents,
		TotalCents: totalCents,
	}
}

// computeConfidence calculates a heuristic confidence score and appends warnings
// for any cross-validation mismatches.
func (cfg ParserConfig) computeConfidence(r *ParsedReceipt) {
	var score float64
	var checks int

	// Check 1: do item totals sum to the stated subtotal?
	if r.SubtotalCents != nil && len(r.Items) > 0 {
		var itemSum int64
		for _, item := range r.Items {
			itemSum += item.TotalCents
		}
		if abs64(itemSum-*r.SubtotalCents) <= cfg.CrossValidationTolerance {
			score += cfg.MatchScore
		} else {
			score += cfg.MismatchScore
			r.Warnings = append(r.Warnings, fmt.Sprintf(
				"Item total ($%s) differs from receipt subtotal ($%s)",
				formatCents(itemSum), formatCents(*r.SubtotalCents),
			))
		}
		checks++
	}

	// Check 2: does subtotal + tax + tip equal the stated total?
	if r.TotalCents != nil && r.SubtotalCents != nil {
		expected := *r.SubtotalCents
		if r.TaxCents != nil {
			expected += *r.TaxCents
		}
		if r.TipCents != nil {
			expected += *r.TipCents
		}
		if abs64(expected-*r.TotalCents) <= cfg.CrossValidationTolerance {
			score += cfg.MatchScore
		} else {
			score += cfg.MismatchScore
			r.Warnings = append(r.Warnings, "Computed total doesn't match receipt total")
		}
		checks++
	}

	// Check 3: did we find any items at all?
	if len(r.Items) > 0 {
		score += cfg.ItemsFoundScore
		checks++
	}

	if checks > 0 {
		r.Confidence = score / (float64(checks) + cfg.ConfidenceNormalizer)
	} else {
		r.Confidence = cfg.NoCheckConfidence
	}

	r.Confidence = math.Min(1.0, math.Max(0.0, r.Confidence))
}

// isNegativePrice checks whether the price at priceStart is preceded by a
// standalone minus sign. Consecutive dashes ("---") are treated as filler, not
// as a negative indicator.
func isNegativePrice(line string, priceStart int) bool {
	i := priceStart - 1
	for i >= 0 && (line[i] == ' ' || line[i] == '$') {
		i--
	}
	if i < 0 || line[i] != '-' {
		return false
	}
	return i == 0 || line[i-1] != '-'
}

// dollarsToCents converts a price string like "12.99" or "1,234.56" to cents.
func dollarsToCents(s string) int64 {
	s = strings.ReplaceAll(s, ",", "")
	f, err := strconv.ParseFloat(s, 64)
	if err != nil {
		return 0
	}
	return int64(math.Round(f * 100))
}

func abs64(n int64) int64 {
	if n < 0 {
		return -n
	}
	return n
}

func formatCents(c int64) string {
	if c < 0 {
		return fmt.Sprintf("-%d.%02d", -c/100, -c%100)
	}
	return fmt.Sprintf("%d.%02d", c/100, c%100)
}

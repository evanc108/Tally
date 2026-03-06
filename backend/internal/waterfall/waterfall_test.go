package waterfall

import (
	"testing"

	"github.com/google/uuid"
	"github.com/tally/backend/internal/ledger"
)

func TestBuildFundingPlan_AllMembersHavePM(t *testing.T) {
	members := []MemberRow{
		{
			ID:                    uuid.New(),
			AccountID:             uuid.New(),
			StripePaymentMethodID: "pm_alice",
			SplitWeight:           0.50,
		},
		{
			ID:                    uuid.New(),
			AccountID:             uuid.New(),
			StripePaymentMethodID: "pm_bob",
			SplitWeight:           0.50,
		},
	}

	splits, err := BuildFundingPlan(members, 10000)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(splits) != 2 {
		t.Fatalf("splits count = %d, want 2", len(splits))
	}
	if splits[0].AmountCents != 5000 {
		t.Errorf("splits[0].AmountCents = %d, want 5000", splits[0].AmountCents)
	}
	if splits[1].AmountCents != 5000 {
		t.Errorf("splits[1].AmountCents = %d, want 5000", splits[1].AmountCents)
	}
	for i, s := range splits {
		if s.FundingType != ledger.FundingDirectPull {
			t.Errorf("splits[%d].FundingType = %q, want %q", i, s.FundingType, ledger.FundingDirectPull)
		}
	}
}

func TestBuildFundingPlan_MissingPM(t *testing.T) {
	members := []MemberRow{
		{
			ID:                    uuid.New(),
			AccountID:             uuid.New(),
			StripePaymentMethodID: "pm_alice",
			SplitWeight:           0.50,
		},
		{
			ID:                    uuid.New(),
			AccountID:             uuid.New(),
			StripePaymentMethodID: "", // no payment method
			SplitWeight:           0.50,
		},
	}

	_, err := BuildFundingPlan(members, 10000)
	if err == nil {
		t.Fatal("expected error for member missing payment method")
	}
}

func TestBuildFundingPlan_SingleMember(t *testing.T) {
	members := []MemberRow{
		{
			ID:                    uuid.New(),
			AccountID:             uuid.New(),
			StripePaymentMethodID: "pm_sole",
			SplitWeight:           1.0,
		},
	}

	splits, err := BuildFundingPlan(members, 5000)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(splits) != 1 {
		t.Fatalf("splits count = %d, want 1", len(splits))
	}
	if splits[0].AmountCents != 5000 {
		t.Errorf("AmountCents = %d, want 5000", splits[0].AmountCents)
	}
}

func TestBuildFundingPlan_UnequalWeights(t *testing.T) {
	members := []MemberRow{
		{
			ID:                    uuid.New(),
			AccountID:             uuid.New(),
			StripePaymentMethodID: "pm_a",
			SplitWeight:           0.60,
		},
		{
			ID:                    uuid.New(),
			AccountID:             uuid.New(),
			StripePaymentMethodID: "pm_b",
			SplitWeight:           0.40,
		},
	}

	splits, err := BuildFundingPlan(members, 10000)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if splits[0].AmountCents != 6000 {
		t.Errorf("splits[0].AmountCents = %d, want 6000 (60%%)", splits[0].AmountCents)
	}
	if splits[1].AmountCents != 4000 {
		t.Errorf("splits[1].AmountCents = %d, want 4000 (40%%)", splits[1].AmountCents)
	}
}

func TestBuildFundingPlan_EmptyMembers(t *testing.T) {
	splits, err := BuildFundingPlan(nil, 10000)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(splits) != 0 {
		t.Errorf("expected empty splits for no members, got %d", len(splits))
	}
}

func TestBuildFundingPlan_PreservesAccountIDs(t *testing.T) {
	memberID := uuid.New()
	accountID := uuid.New()
	members := []MemberRow{
		{
			ID:                    memberID,
			AccountID:             accountID,
			StripePaymentMethodID: "pm_test",
			SplitWeight:           1.0,
		},
	}

	splits, err := BuildFundingPlan(members, 1000)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if splits[0].MemberID != memberID {
		t.Errorf("MemberID = %v, want %v", splits[0].MemberID, memberID)
	}
	if splits[0].AccountID != accountID {
		t.Errorf("AccountID = %v, want %v", splits[0].AccountID, accountID)
	}
}

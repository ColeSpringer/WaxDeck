package db

import (
	"context"
	"slices"
	"testing"
)

// The items failing a rule among those named are read from the index:
// named and flagged for that rule, nothing else.
func TestFailingItemsAmongReadsTheNamedItemsARuleFlags(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	for _, r := range []HealthRow{
		{ItemPID: "a", MediaType: "music", Rules: `["path-mismatch"]`, RuleCount: 1, SweptAtNS: 1},
		{ItemPID: "b", MediaType: "music", Rules: `["missing-art"]`, RuleCount: 1, SweptAtNS: 1},
		{ItemPID: "c", MediaType: "music", Rules: `["missing-art","path-mismatch"]`, RuleCount: 2, SweptAtNS: 1},
		{ItemPID: "d", MediaType: "music", Rules: `["path-mismatch"]`, RuleCount: 1, SweptAtNS: 1},
	} {
		if err := d.UpsertHealthRow(ctx, r); err != nil {
			t.Fatal(err)
		}
	}
	got, err := d.FailingItemsAmong(ctx, "path-mismatch", []string{"a", "b", "c", "e"})
	if err != nil || !slices.Equal(got, []string{"a", "c"}) {
		t.Fatalf("failing among a, b, c, e = %v (%v), want a and c", got, err)
	}
	if got, err := d.FailingItemsAmong(ctx, "path-mismatch", []string{"b", "e"}); err != nil || len(got) != 0 {
		t.Fatalf("failing among b, e = %v (%v), want none", got, err)
	}
}

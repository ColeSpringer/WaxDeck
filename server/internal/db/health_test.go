package db

import (
	"context"
	"errors"
	"testing"
)

// Taking one rule off a row changes that rule alone: a sweep that
// rewrote the row after the re-check read it keeps what it wrote, and the
// row goes only when the rule was its last.
func TestDropHealthRuleKeepsWhatASweepWrote(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	row := func(pid, rules string, count int, swept int64, title string) HealthRow {
		return HealthRow{ItemPID: pid, MediaType: "music", Title: title, Rules: rules, RuleCount: count, SweptAtNS: swept}
	}
	for _, r := range []HealthRow{
		row("x", `["missing-lyrics","missing-art"]`, 2, 1, "read"),
		// The sweep, after the re-check read x.
		row("x", `["missing-lyrics","missing-art","missing-genre"]`, 3, 2, "swept"),
		row("y", `["missing-lyrics"]`, 1, 2, "last"),
		row("z", `["missing-art"]`, 1, 2, "other"),
	} {
		if err := d.UpsertHealthRow(ctx, r); err != nil {
			t.Fatal(err)
		}
	}
	for _, pid := range []string{"x", "y", "z"} {
		if err := d.DropHealthRule(ctx, pid, "missing-lyrics"); err != nil {
			t.Fatal(err)
		}
	}
	x, err := d.HealthRowByItem(ctx, "x")
	if err != nil || x.Rules != `["missing-art","missing-genre"]` || x.RuleCount != 2 || x.SweptAtNS != 2 || x.Title != "swept" {
		t.Fatalf("x = %+v (%v), want the sweep's row less the dropped rule", x, err)
	}
	if _, err := d.HealthRowByItem(ctx, "y"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("y = %v, want the row gone with its last rule", err)
	}
	if z, err := d.HealthRowByItem(ctx, "z"); err != nil || z.Rules != `["missing-art"]` || z.RuleCount != 1 {
		t.Fatalf("z = %+v (%v), want it untouched", z, err)
	}
	if n, err := d.PruneHealthRows(ctx, 2); err != nil || n != 0 {
		t.Fatalf("pruned %d (%v), want the swept rows kept", n, err)
	}
}

// A row's detail travels with it and a re-sweep that finds none clears it.
func TestHealthRowCarriesItsDetail(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	r := HealthRow{ItemPID: "x", MediaType: "music", Rules: `["duration-mismatch"]`, RuleCount: 1, SweptAtNS: 1,
		Detail: `{"headerMs":1000,"decodedMs":2000}`}
	if err := d.UpsertHealthRow(ctx, r); err != nil {
		t.Fatal(err)
	}
	if got, err := d.HealthRowByItem(ctx, "x"); err != nil || got.Detail != r.Detail {
		t.Fatalf("row = %+v (%v), want detail %s", got, err, r.Detail)
	}
	if rows, err := d.ListHealthRows(ctx, "", 0, "", "", 10); err != nil || len(rows) != 1 || rows[0].Detail != r.Detail {
		t.Fatalf("listed %+v (%v), want the detail", rows, err)
	}
	r.Detail, r.SweptAtNS = "", 2
	if err := d.UpsertHealthRow(ctx, r); err != nil {
		t.Fatal(err)
	}
	if got, err := d.HealthRowByItem(ctx, "x"); err != nil || got.Detail != "" {
		t.Fatalf("row = %+v (%v), want the detail cleared", got, err)
	}
}

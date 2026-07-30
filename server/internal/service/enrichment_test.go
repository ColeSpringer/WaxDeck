package service

import (
	"testing"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
)

// A book provider that returns a plausible-but-invalid ISBN (a checksum typo,
// say) must not cost the rest of its contribution: WaxBin validates identifiers
// on write and rejects the whole edit for one bad value, so bookEnrichEdits
// drops the ISBN and keeps every other fill-when-empty field.
func TestBookEnrichEditsSkipsMalformedISBN(t *testing.T) {
	it := &model.ItemView{Kind: model.KindBook}
	detail := &model.BookDetail{} // nothing filled yet, so every field is a candidate
	cand := &enrich.Candidate{
		Publisher: "Recorded Books",
		ISBN:      "9780306406158", // valid shape, bad ISBN-13 checksum
		Fields:    map[string]string{"narrator": "Some Reader"},
	}

	edits, skipped := bookEnrichEdits(cand, detail, it, map[string]bool{})

	if skipped["isbn"] != "9780306406158" {
		t.Fatalf("skipped[isbn] = %q, want the malformed value reported for logging", skipped["isbn"])
	}
	if _, ok := edits["isbn"]; ok {
		t.Fatalf("malformed isbn leaked into edits: %v", edits)
	}
	if edits["publisher"] != "Recorded Books" {
		t.Fatalf("publisher dropped alongside the bad isbn: edits = %v", edits)
	}
	if edits["narrator"] != "Some Reader" {
		t.Fatalf("narrator dropped alongside the bad isbn: edits = %v", edits)
	}
}

// A valid ISBN rides through, and nothing is reported as skipped.
func TestBookEnrichEditsAppliesValidISBN(t *testing.T) {
	it := &model.ItemView{Kind: model.KindBook}
	detail := &model.BookDetail{}
	cand := &enrich.Candidate{ISBN: "9780306406157"} // valid ISBN-13

	edits, skipped := bookEnrichEdits(cand, detail, it, map[string]bool{})

	if len(skipped) != 0 {
		t.Fatalf("skipped = %v, want empty for a valid ISBN", skipped)
	}
	if edits["isbn"] != "9780306406157" {
		t.Fatalf("valid isbn not applied: edits = %v", edits)
	}
}

// WaxBin stores year as a non-negative integer and rejects the whole edit for
// anything else, so a provider year that is not one (a full date, say) is
// dropped like a bad ISBN while the provider's other fields still land.
func TestBookEnrichEditsYearMustBeNumeric(t *testing.T) {
	it := &model.ItemView{Kind: model.KindBook} // Year 0, so year is a candidate
	detail := &model.BookDetail{}

	bad := &enrich.Candidate{
		Publisher: "Recorded Books",
		Fields:    map[string]string{"year": "2020-04-15"},
	}
	edits, skipped := bookEnrichEdits(bad, detail, it, map[string]bool{})
	if skipped["year"] != "2020-04-15" {
		t.Fatalf("skipped[year] = %q, want the malformed value", skipped["year"])
	}
	if _, ok := edits["year"]; ok {
		t.Fatalf("non-numeric year leaked into edits: %v", edits)
	}
	if edits["publisher"] != "Recorded Books" {
		t.Fatalf("publisher dropped alongside the bad year: edits = %v", edits)
	}

	good := &enrich.Candidate{Fields: map[string]string{"year": "2021"}}
	edits, skipped = bookEnrichEdits(good, detail, it, map[string]bool{})
	if len(skipped) != 0 {
		t.Fatalf("skipped = %v, want empty for a numeric year", skipped)
	}
	if edits["year"] != "2021" {
		t.Fatalf("numeric year not applied: edits = %v", edits)
	}
}

// A locked field is never overwritten, and a field the item already carries is
// left alone - bookEnrichEdits only fills genuine gaps.
func TestBookEnrichEditsRespectsLocksAndExisting(t *testing.T) {
	it := &model.ItemView{Kind: model.KindBook, Narrator: "Existing Reader"}
	detail := &model.BookDetail{Publisher: "Existing Publisher"}
	cand := &enrich.Candidate{
		Publisher: "New Publisher",
		ISBN:      "9780306406157",
		Fields:    map[string]string{"narrator": "New Reader"},
	}
	locked := map[string]bool{"isbn": true}

	edits, skipped := bookEnrichEdits(cand, detail, it, locked)

	if len(skipped) != 0 {
		t.Fatalf("skipped = %v, want empty (isbn was locked, not malformed)", skipped)
	}
	if _, ok := edits["isbn"]; ok {
		t.Fatalf("locked isbn was written: %v", edits)
	}
	if _, ok := edits["publisher"]; ok {
		t.Fatalf("publisher overwrote an existing value: %v", edits)
	}
	if _, ok := edits["narrator"]; ok {
		t.Fatalf("narrator overwrote an existing value: %v", edits)
	}
	if len(edits) != 0 {
		t.Fatalf("expected no edits, got %v", edits)
	}
}

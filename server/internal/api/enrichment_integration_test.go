package api

import (
	"context"
	"testing"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// fakeBookProvider is a book-metadata enrich provider that returns a fixed
// candidate, for driving the enrichBook provider loop from a test.
type fakeBookProvider struct {
	name string
	cand *enrich.Candidate
}

func (f fakeBookProvider) Name() string                    { return f.name }
func (f fakeBookProvider) Capabilities() enrich.Capability { return enrich.CapBookMeta }
func (f fakeBookProvider) Enrich(context.Context, enrich.Request) (*enrich.Candidate, error) {
	return f.cand, nil
}

// A provider whose only novel value is one WaxBin would reject (a bad-checksum
// ISBN) must not end the enrich pass: enrichBook has to fall through to the next
// provider, which here supplies a valid publisher. Regression guard for the
// skip-refactor that briefly returned early on an all-malformed candidate.
func TestEnrichBookFallsThroughMalformedProvider(t *testing.T) {
	bad := fakeBookProvider{name: "bad", cand: &enrich.Candidate{ISBN: "9780306406158"}}     // valid shape, bad checksum
	good := fakeBookProvider{name: "good", cand: &enrich.Candidate{Publisher: "Beta House"}} // valid, fills the gap
	h := newHarnessWith(t, func(c *service.Config) {
		c.EnrichmentProviders = []enrich.Provider{bad, good}
	})
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	books := h.items(t, "?mediaType=audiobook")
	if len(books.Items) == 0 {
		t.Fatal("no audiobook scanned")
	}
	book := books.Items[0].Pid

	// Book providers key on ASIN, so the item needs one before enrichBook runs.
	resp := h.patchJSON(t, "/api/v1/items/"+book+"/metadata", map[string]any{
		"fields": map[string]string{"asin": "B000002L5R"},
	})
	wantStatus(t, resp, 200, "set asin")

	resp = h.postJSON(t, "/api/v1/items/"+book+"/enrich", map[string]any{"want": []string{"book"}})
	wantStatus(t, resp, 200, "enrich book")

	// The bad provider ran first and offered only the malformed ISBN; the good
	// provider's publisher lands only if the pass fell through instead of ending.
	if got := h.itemMeta(t, book).Fields["publisher"]; got != "Beta House" {
		t.Fatalf("publisher = %q, want Beta House - enrich did not fall through the malformed provider", got)
	}
}

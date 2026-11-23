package api

import (
	"context"
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
)

// Play-info mints with the caller's default for voice boost where nothing
// is stored for the book, and with the stored setting, off included, where
// something is.
func TestPlayInfoTakesTheCallersVoiceBoostDefault(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook").Items
	if len(books) != 1 {
		t.Fatalf("audiobooks = %d, want the fixture book", len(books))
	}
	book := books[0].Pid
	// Boost needs the part's measured loudness, which the analysis stores.
	get(t, h.ts, "/api/v1/items/"+book+"/skip-map?partIndex=0", h.token).Body.Close()
	for h.svc.Tools.DrainAnalysisQueue(context.Background()) {
	}
	boosted := func(query string) bool {
		t.Helper()
		pi, _ := playInfoCut(t, h, book, query)
		return pi.VoiceBoost != nil && *pi.VoiceBoost
	}

	if !boosted("?voiceBoostDefault=true") {
		t.Error("none stored, default on: the stream is not boosted")
	}
	if boosted("") {
		t.Error("none stored, no default: the stream is boosted")
	}
	wantStatus(t, h.putJSON(t, "/api/v1/books/"+book+"/settings", map[string]any{"voiceBoost": false}), 200, "book settings")
	if boosted("?voiceBoostDefault=true") {
		t.Error("stored off, default on: the stream is boosted")
	}
	if !boosted("?voiceBoost=true&voiceBoostDefault=false") {
		t.Error("stored off, explicit on: the stream is not boosted")
	}
}

package api

import (
	"context"
	"net/url"
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
)

// playInfoCut mints play-info for query and answers it with the cut its
// URL carries, after asserting the stream fetches.
func playInfoCut(t *testing.T, h *harness, pid, query string) (PlayInfo, string) {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/items/"+pid+"/play-info"+query, h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("play-info%s = %d", query, resp.StatusCode)
	}
	pi := decode[PlayInfo](t, resp)
	u, err := url.Parse(pi.Url)
	if err != nil {
		t.Fatal(err)
	}
	if code := fetchStatus(t, h, pi.Url); code != 200 {
		t.Fatalf("stream %s = %d", pi.Url, code)
	}
	return pi, u.Query().Get("t")
}

// A position on a capped stream mints it cut there, to the whole second
// before, and says where the audio begins.
func TestPlayInfoPositionCutsACappedStream(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "?limit=1").Items[0].Pid // Alpha Song, a 2 s flac

	pi, cut := playInfoCut(t, h, pid, "?maxBitrateKbps=128&positionMs=1500")
	if pi.Seekable || cut != "1" {
		t.Fatalf("seekable %v, cut %q; want an unseekable stream cut at 1", pi.Seekable, cut)
	}
	if pi.StartOffsetMs == nil || *pi.StartOffsetMs != 1000 {
		t.Fatalf("startOffsetMs = %v, want 1000", pi.StartOffsetMs)
	}
	if h.flowReq.cut != "1" || h.flowReq.format != "opus" || h.flowReq.bitrate != "128" {
		t.Fatalf("the engine saw cut %q, %s at %s; want 1, opus at 128", h.flowReq.cut, h.flowReq.format, h.flowReq.bitrate)
	}

	// Under a second there is nothing to cut, and no offset to report.
	pi, cut = playInfoCut(t, h, pid, "?maxBitrateKbps=128&positionMs=500")
	if cut != "" || pi.StartOffsetMs != nil {
		t.Fatalf("a sub-second position = cut %q, offset %v; want neither", cut, pi.StartOffsetMs)
	}
}

// An original is the client's to seek, so a position cuts nothing.
func TestPlayInfoPositionIsIgnoredForAnOriginal(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "?limit=1").Items[0].Pid

	pi, cut := playInfoCut(t, h, pid, "?positionMs=1500")
	if !pi.Seekable || cut != "" || pi.StartOffsetMs != nil {
		t.Fatalf("seekable %v, cut %q, offset %v; want the original uncut", pi.Seekable, cut, pi.StartOffsetMs)
	}
	if h.flowReq.cut != "" || h.flowReq.format != "auto" {
		t.Fatalf("the engine saw cut %q in %s, want the original", h.flowReq.cut, h.flowReq.format)
	}
}

// In a multi-file book the position is the book's, the cut is the part's:
// a voice-boosted part, which cannot be range-seeked, starts where the
// listener is inside it.
func TestPlayInfoPartOffsetForABoostedBook(t *testing.T) {
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
	// Boost derives its gain from the part's measured loudness, which the
	// skip-map analysis stores: ask for part two's map and run the worker.
	get(t, h.ts, "/api/v1/items/"+books[0].Pid+"/skip-map?partIndex=1", h.token).Body.Close()
	for h.svc.DrainAnalysisQueue(context.Background()) {
	}

	// Parts of 4, 5 and 6 s: 6.5 s into the book is 2.5 s into part two.
	pi, cut := playInfoCut(t, h, books[0].Pid, "?positionMs=6500&voiceBoost=true")
	if pi.VoiceBoost == nil || !*pi.VoiceBoost {
		t.Fatalf("voice boost did not engage: %+v", pi)
	}
	if pi.PartIndex == nil || *pi.PartIndex != 1 || pi.PartStartMs == nil || *pi.PartStartMs != 4000 {
		t.Fatalf("part = %v from %v, want part 1 from 4000", pi.PartIndex, pi.PartStartMs)
	}
	if pi.Seekable || cut != "2" || pi.StartOffsetMs == nil || *pi.StartOffsetMs != 2000 {
		t.Fatalf("seekable %v, cut %q, offset %v; want the part cut at 2 s", pi.Seekable, cut, pi.StartOffsetMs)
	}
	if h.flowReq.cut != "2" || h.flowReq.dynamics != "voice" {
		t.Fatalf("the engine saw cut %q with dynamics %q, want 2 and voice", h.flowReq.cut, h.flowReq.dynamics)
	}
}

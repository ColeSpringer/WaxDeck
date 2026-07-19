package api

import (
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
)

// The direct-playback suite runs the whole stack with no streaming
// bridge, the shape of a server started without WAXDECK_FLOW_URL:
// play-info serves original bytes through the tokenized download
// endpoint, span-carved tracks carry their window for the client to
// clip, and the Subsonic surface streams by redirect, refusing only
// what it cannot serve honestly.

func directGet(t *testing.T, h *harness, path string) *http.Response {
	t.Helper()
	resp, err := http.Get(h.ts.URL + path)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func TestDirectPlayback(t *testing.T) {
	h := newHarnessDirect(t)

	music := h.items(t, "?mediaType=music")
	var alpha, bravo ItemSummary
	for _, it := range music.Items {
		switch it.Title {
		case "Alpha Song":
			alpha = it
		case "Bravo Song":
			bravo = it
		}
	}
	if alpha.Pid == "" || bravo.Pid == "" {
		t.Fatalf("fixture items missing: %+v", music.Items)
	}

	// A plain track: play-info mints a tokenized download URL serving
	// the original bytes, ranged.
	pi := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+alpha.Pid+"/play-info", h.token))
	if !strings.HasPrefix(pi.Url, "/media/download?pid=") {
		t.Fatalf("direct url = %q", pi.Url)
	}
	if pi.MimeType != "audio/flac" || !pi.Seekable || pi.DurationMs != alpha.DurationMs {
		t.Fatalf("direct play-info = %+v", pi)
	}
	if pi.SpanStartMs != nil || pi.SpanEndMs != nil {
		t.Fatalf("plain track carries a span: %+v", pi)
	}
	resp := directGet(t, h, pi.Url)
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || len(body) == 0 || resp.Header.Get("Content-Type") != "audio/flac" {
		t.Fatalf("direct fetch status = %d type = %q bytes = %d", resp.StatusCode, resp.Header.Get("Content-Type"), len(body))
	}
	req, _ := http.NewRequest("GET", h.ts.URL+pi.Url, nil)
	req.Header.Set("Range", "bytes=0-99")
	ranged, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	part, _ := io.ReadAll(ranged.Body)
	ranged.Body.Close()
	if ranged.StatusCode != http.StatusPartialContent || len(part) != 100 {
		t.Fatalf("range status = %d bytes = %d, want 206 with 100", ranged.StatusCode, len(part))
	}

	// A multi-file book resolves one part per call; the served
	// duration is the part's, and the part file streams.
	if _, err := fixtures.GenerateBook(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	books := h.items(t, "?mediaType=audiobook")
	if len(books.Items) != 1 {
		t.Fatalf("audiobooks = %d, want 1", len(books.Items))
	}
	book := books.Items[0]
	pi = decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+book.Pid+"/play-info?positionMs=0", h.token))
	if pi.PartCount == nil || *pi.PartCount < 2 || pi.PartIndex == nil || *pi.PartIndex != 0 {
		t.Fatalf("book play-info parts = %+v", pi)
	}
	if !strings.Contains(pi.Url, "&f=") || pi.DurationMs >= book.DurationMs {
		t.Fatalf("book part url/duration = %q %d (book %d)", pi.Url, pi.DurationMs, book.DurationMs)
	}
	resp = directGet(t, h, pi.Url)
	body, _ = io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || len(body) == 0 {
		t.Fatalf("book part fetch status = %d bytes = %d", resp.StatusCode, len(body))
	}

	// A CUE rip carves the flac into virtual tracks. Direct play
	// serves the whole backing file and reports the window.
	flacs, err := filepath.Glob(filepath.Join(h.library, "alpha*"))
	if err != nil || len(flacs) != 1 {
		t.Fatalf("locating the fixture flac: %v %v", flacs, err)
	}
	cue := fmt.Sprintf("PERFORMER \"Cue Artist\"\nTITLE \"Cue Album\"\nFILE %q WAVE\n"+
		"  TRACK 01 AUDIO\n    TITLE \"Cue One\"\n    INDEX 01 00:00:00\n"+
		"  TRACK 02 AUDIO\n    TITLE \"Cue Two\"\n    INDEX 01 00:01:00\n",
		filepath.Base(flacs[0]))
	if err := os.WriteFile(filepath.Join(h.library, "alpha.cue"), []byte(cue), 0o644); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	var cueTwo ItemSummary
	for _, it := range h.items(t, "?mediaType=music&limit=50").Items {
		if it.Title == "Cue Two" {
			cueTwo = it
		}
	}
	if cueTwo.Pid == "" {
		t.Fatalf("cue virtual track missing: %+v", h.items(t, "?mediaType=music&limit=50").Items)
	}
	pi = decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+cueTwo.Pid+"/play-info", h.token))
	if pi.SpanStartMs == nil || pi.SpanEndMs == nil {
		t.Fatalf("cue track play-info carries no span: %+v", pi)
	}
	if *pi.SpanStartMs != 1000 || *pi.SpanEndMs <= *pi.SpanStartMs {
		t.Fatalf("span = [%d, %d)", *pi.SpanStartMs, *pi.SpanEndMs)
	}
	if pi.DurationMs != cueTwo.DurationMs {
		t.Fatalf("span item duration = %d, want the item's own %d", pi.DurationMs, cueTwo.DurationMs)
	}
	resp = directGet(t, h, pi.Url)
	body, _ = io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || len(body) == 0 {
		t.Fatalf("span backing fetch status = %d bytes = %d", resp.StatusCode, len(body))
	}

	// Subsonic: a plain track streams by redirect into the same
	// endpoint; the span track is refused with the explicit reason
	// (Subsonic clients cannot clip).
	secret := newSubsonicSecret(t, h)
	client := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	sresp, err := client.Get(h.ts.URL + "/rest/stream?apiKey=" + secret + "&id=" + bravo.Pid)
	if err != nil {
		t.Fatal(err)
	}
	sresp.Body.Close()
	if sresp.StatusCode != 302 || !strings.HasPrefix(sresp.Header.Get("Location"), "/media/download?pid=") {
		t.Fatalf("subsonic direct stream = %d %q", sresp.StatusCode, sresp.Header.Get("Location"))
	}
	resp = directGet(t, h, sresp.Header.Get("Location"))
	body, _ = io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || len(body) == 0 {
		t.Fatalf("subsonic redirected fetch status = %d bytes = %d", resp.StatusCode, len(body))
	}
	env := subsonicGet(t, h, "stream", secret, "&id="+cueTwo.Pid)
	if env.Status != "failed" || env.Error == nil || !strings.Contains(env.Error.Message, "streaming engine") {
		t.Fatalf("subsonic span stream = %+v", env)
	}

	// The engine-only surface reports itself unavailable rather than
	// half-working: no /media/stream route exists in this mode.
	resp = directGet(t, h, "/media/stream?pid="+alpha.Pid)
	resp.Body.Close()
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("/media/stream in direct mode = %d, want 404", resp.StatusCode)
	}
}

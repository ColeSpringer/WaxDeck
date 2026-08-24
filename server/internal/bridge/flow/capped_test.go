package flow

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// fakeGate counts admissions and answers a fixed per-user ceiling.
type fakeGate struct {
	ceiling  int
	acquired int
}

func (g *fakeGate) Acquire(context.Context, string) (func(), error) {
	g.acquired++
	return func() {}, nil
}

func (g *fakeGate) MaxBitrateKbps(context.Context, string) int { return g.ceiling }

// A bitrate cap on a source that cannot satisfy it is a real encode:
// clamped to the caller's ceiling at mint, carried on the URL, refused
// widening at fetch, charged an admission slot, and handed to the
// engine as the narrowed bitrate.
func TestPlayInfoBitrateCap(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "song.flac")
	if err := os.WriteFile(path, []byte("flacbytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	src := Source{Path: path, Size: 9, MTimeNS: 42, Codec: "flac", Container: "flac", BitrateKbps: 900}
	var got url.Values
	b := newTestBridge(t, func(w http.ResponseWriter, r *http.Request) {
		got = r.URL.Query()
		io.WriteString(w, "capped")
	}, src)
	gate := &fakeGate{ceiling: 192}
	b.SetTranscodeGate(gate)

	info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{MaxBitrateKbps: 320})
	if err != nil {
		t.Fatal(err)
	}
	// The request clamps to the caller's own ceiling at mint.
	if info.AppliedBitrateKbps != 192 {
		t.Fatalf("applied = %d, want the 192 ceiling", info.AppliedBitrateKbps)
	}
	// Unseekable is what excludes a capped stream from gapless preload.
	if info.Seekable {
		t.Fatal("a capped stream must not advertise seekable")
	}
	if info.MimeType != "audio/ogg" {
		t.Fatalf("mime = %q, want the opus encode", info.MimeType)
	}
	u, err := url.Parse(info.URL)
	if err != nil {
		t.Fatal(err)
	}
	if q := u.Query(); q.Get("fmt") != "opus" || q.Get("br") != "192" {
		t.Fatalf("url params fmt=%q br=%q", q.Get("fmt"), q.Get("br"))
	}

	rec := httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", info.URL, nil))
	if rec.Code != 200 {
		t.Fatalf("status = %d", rec.Code)
	}
	if gate.acquired != 1 {
		t.Fatalf("admission slots = %d, want 1: a capped stream is a real encode", gate.acquired)
	}
	if got.Get("format") != "opus" || got.Get("bitrate") != "192" {
		t.Fatalf("engine params format=%q bitrate=%q", got.Get("format"), got.Get("bitrate"))
	}

	// An edited br can only narrow: above the ceiling it is re-clamped.
	// got is reset so a request that never reached the fake sidecar
	// cannot pass on the first fetch's values.
	got = nil
	wide := strings.Replace(info.URL, "br=192", "br=320", 1)
	rec = httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", wide, nil))
	if rec.Code != 200 {
		t.Fatalf("widened fetch status = %d", rec.Code)
	}
	if got.Get("bitrate") != "192" {
		t.Fatalf("widened br reached the engine as %q, want the 192 ceiling", got.Get("bitrate"))
	}
}

// A lossy source already inside the cap streams exactly as before: the
// cap applies nothing, and direct play keeps its seekability.
func TestPlayInfoCapLeavesALossySourceInsideIt(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "song.mp3")
	if err := os.WriteFile(path, []byte("mp3"), 0o644); err != nil {
		t.Fatal(err)
	}
	src := Source{Path: path, Size: 3, MTimeNS: 1, Codec: "mp3", Container: "mp3", BitrateKbps: 128}
	b := newTestBridge(t, func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, "direct")
	}, src)

	info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{MaxBitrateKbps: 192})
	if err != nil {
		t.Fatal(err)
	}
	if info.AppliedBitrateKbps != 0 || !info.Seekable {
		t.Fatalf("info = %+v, want an untouched direct play", info)
	}
	if strings.Contains(info.URL, "br=") || strings.Contains(info.URL, "fmt=") {
		t.Fatalf("uncapped url carries cap params: %s", info.URL)
	}
}

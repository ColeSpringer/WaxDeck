package flow

import (
	"github.com/colespringer/waxdeck/server/internal/auth"

	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
)

// fakeGate counts admissions and answers a fixed per-user ceiling.
type fakeGate struct {
	ceiling int
	// ceilingReads counts how often the ceiling was asked for.
	ceilingReads int
	acquired     int
	// held counts admissions not yet released, and kinds records what
	// each was taken for, which is what the timeline slot's whole
	// lifetime is asserted through.
	held    int
	kinds   []TranscodeKind
	refuse  bool
	release func()
	// authErr is what AuthorizeMedia answers; authorized records every
	// token it was asked about.
	authErr    error
	authorized []auth.MediaClaims
}

func (g *fakeGate) Acquire(_ context.Context, _ string, kind TranscodeKind) (func(), error) {
	if g.refuse {
		return nil, ErrTranscodeLimited
	}
	g.acquired++
	g.held++
	g.kinds = append(g.kinds, kind)
	var once sync.Once
	release := func() {
		once.Do(func() { g.held-- })
	}
	g.release = release
	return release, nil
}

func (g *fakeGate) MaxBitrateKbps(context.Context, string) int {
	g.ceilingReads++
	return g.ceiling
}

func (g *fakeGate) AuthorizeMedia(_ context.Context, c auth.MediaClaims) error {
	g.authorized = append(g.authorized, c)
	return g.authErr
}

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

	// The token binds the cap, so an edited br is a bad token rather
	// than a wider stream, and so is one with the cap stripped. got is
	// reset so a request that never reached the fake sidecar cannot pass
	// on the first fetch's values.
	got = nil
	for _, edited := range []string{
		strings.Replace(info.URL, "br=192", "br=320", 1),
		strings.Replace(strings.Replace(info.URL, "&br=192", "", 1), "&fmt=opus", "", 1),
		strings.Replace(info.URL, "fmt=opus", "fmt=flac", 1),
	} {
		rec = httptest.NewRecorder()
		b.ServeStream(rec, httptest.NewRequest("GET", edited, nil))
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("edited url %s answered %d, want 401", edited, rec.Code)
		}
	}
	if got != nil {
		t.Fatalf("an edited url reached the engine with %v", got)
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

// A cap on a source that is already in the format the cap picked. The
// hint on the URL is then indistinguishable by name from one asking for
// a copy of the file, and reading it as one served the original bytes
// at the source's own bitrate - uncharged, and larger than the number
// the client had been handed.
func TestBitrateCapOnASourceAlreadyInTheCapsFormat(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "song.opus")
	if err := os.WriteFile(path, []byte("opusbytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	// Lossy, and over the cap, so the cap is a real encode - into opus,
	// which is what this file already is.
	src := Source{Path: path, Size: 9, MTimeNS: 42, Codec: "opus", Container: "ogg", BitrateKbps: 256}
	var got url.Values
	b := newTestBridge(t, func(w http.ResponseWriter, r *http.Request) {
		got = r.URL.Query()
		io.WriteString(w, "capped")
	}, src)
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)

	info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{MaxBitrateKbps: 128})
	if err != nil {
		t.Fatal(err)
	}
	if info.AppliedBitrateKbps != 128 || info.Seekable {
		t.Fatalf("info = %+v, want an unseekable 128 encode", info)
	}
	if !strings.Contains(info.URL, "br=128") {
		t.Fatalf("URL = %s, want the cap on it", info.URL)
	}

	rec := httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", info.URL, nil))
	if rec.Code != 200 {
		t.Fatalf("status = %d: %s", rec.Code, rec.Body.String())
	}
	if got.Get("bitrate") != "128" {
		t.Fatalf("engine bitrate = %q, want the cap the client was promised", got.Get("bitrate"))
	}
	if got.Get("format") != "opus" {
		t.Fatalf("engine format = %q, want the capped encode", got.Get("format"))
	}
	if gate.acquired != 1 {
		t.Fatalf("admissions = %d, want the encode charged", gate.acquired)
	}
}

// A capped account's engine-rendered stream is held to its ceiling even
// when the client named no cap of its own: a carved lossless track would
// otherwise render as full-rate FLAC. An original played directly is
// the file itself and stays as it is.
func TestCeilingHoldsAnEngineRenderTheClientDidNotCap(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "rip.flac")
	if err := os.WriteFile(path, []byte("flacbytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	serve := func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "audio") }
	for name, c := range map[string]struct {
		src     Source
		applied int
	}{
		"a carved lossless track": {Source{Path: path, Size: 9, MTimeNS: 42, Codec: "flac", Container: "flac",
			Virtual: true, FromSample: 0, ToSample: 44100}, 64},
		"an original played directly": {Source{Path: path, Size: 9, MTimeNS: 42, Codec: "flac", Container: "flac",
			BitrateKbps: 900}, 0},
	} {
		b := newTestBridge(t, serve, c.src)
		b.SetTranscodeGate(&fakeGate{ceiling: 64})
		info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{})
		if err != nil {
			t.Fatal(err)
		}
		if info.AppliedBitrateKbps != c.applied || strings.Contains(info.URL, "br=") != (c.applied > 0) {
			t.Errorf("%s: applied %d, url %s; want applied %d", name, info.AppliedBitrateKbps, info.URL, c.applied)
		}
	}
}

// A capped account's renderer gets a lossy encode of what the engine
// renders for it even when it plays flac, and the fetch holds that
// encode to the ceiling; an original it plays as it is stays the file.
func TestCeilingHoldsWhatTheEngineRendersForADevice(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "rip.flac")
	if err := os.WriteFile(path, []byte("flacbytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	carved := Source{Path: path, Size: 9, MTimeNS: 42, Codec: "flac", Container: "flac",
		Virtual: true, FromSample: 0, ToSample: 44100}
	whole := Source{Path: path, Size: 9, MTimeNS: 42, Codec: "flac", Container: "flac", BitrateKbps: 900}
	for name, c := range map[string]struct {
		src     Source
		ceiling int
		format  string
	}{
		"a carved track for a capped account":    {carved, 64, "mp3"},
		"a carved track for an uncapped account": {carved, 0, "flac"},
		"an original for a capped account":       {whole, 64, ""},
	} {
		var upstream string
		b := newTestBridge(t, func(w http.ResponseWriter, r *http.Request) {
			upstream = r.URL.RawQuery
			io.WriteString(w, "audio")
		}, c.src)
		b.SetTranscodeGate(&fakeGate{ceiling: c.ceiling})
		info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{
			ForceFormat: "mp3", DeviceFormats: []string{"audio/flac", "audio/mpeg"},
		})
		if err != nil {
			t.Fatal(err)
		}
		u, err := url.Parse(info.URL)
		if err != nil {
			t.Fatal(err)
		}
		if got := u.Query().Get("fmt"); got != c.format {
			t.Errorf("%s: fmt = %q, want %q (%s)", name, got, c.format, info.URL)
			continue
		}
		if c.format != "mp3" {
			continue
		}
		rec := httptest.NewRecorder()
		b.ServeStream(rec, httptest.NewRequest(http.MethodGet, info.URL, nil))
		if q, _ := url.ParseQuery(upstream); rec.Code != 200 || q.Get("bitrate") != "64" {
			t.Errorf("%s: fetch = %d, upstream %q; want the encode held to 64", name, rec.Code, upstream)
		}
	}
}

// A direct play reads no ceiling at fetch: the account's limit bounds
// engine encodes, and a passthrough of the original is not one, so its
// every Range request skips the account read.
func TestDirectPlayFetchReadsNoCeiling(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "song.flac")
	if err := os.WriteFile(path, []byte("flacbytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	b := newTestBridge(t, func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "audio") },
		Source{Path: path, Size: 9, MTimeNS: 42, Codec: "flac", Container: "flac", BitrateKbps: 900})
	gate := &fakeGate{ceiling: 64}
	b.SetTranscodeGate(gate)
	info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{})
	if err != nil {
		t.Fatal(err)
	}
	gate.ceilingReads = 0
	rec := httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", info.URL, nil))
	if rec.Code != http.StatusOK || gate.ceilingReads != 0 {
		t.Errorf("a direct play fetch = %d with %d ceiling reads, want 200 and none", rec.Code, gate.ceilingReads)
	}
}

// Per-fetch authorization fails closed: a bridge nobody wired a gate
// into cannot ask whether a token's account, credential and item still
// hold, so it refuses the token rather than serving it unchecked.
func TestNoGateRefusesMediaTokens(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "song.flac")
	if err := os.WriteFile(path, []byte("flacbytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	b := newTestBridge(t, func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, "audio") },
		Source{Path: path, Size: 9, MTimeNS: 42, Codec: "flac", Container: "flac"})
	b.SetTranscodeGate(nil)
	info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{})
	if err != nil {
		t.Fatal(err)
	}
	rec := httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", info.URL, nil))
	if rec.Code != http.StatusInternalServerError {
		t.Errorf("a fetch with no gate wired = %d, want 500", rec.Code)
	}
}

package flow

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// cutSource writes a stand-in file for src and answers src pointing at it.
func cutSource(t *testing.T, name string, src Source) Source {
	t.Helper()
	path := filepath.Join(t.TempDir(), name)
	if err := os.WriteFile(path, []byte("audio"), 0o644); err != nil {
		t.Fatal(err)
	}
	src.Path, src.Size, src.MTimeNS = path, 5, 1
	return src
}

// longFLAC is a whole lossless file long enough to cut 90 s into.
var longFLAC = Source{Codec: "flac", Container: "flac", BitrateKbps: 900, DurationMS: 200_000}

// mintQuery mints and answers the info and the parameters its URL carries.
func mintQuery(t *testing.T, b *Bridge, opts PlayOptions) (PlayInfo, url.Values) {
	t.Helper()
	info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", opts)
	if err != nil {
		t.Fatal(err)
	}
	u, err := url.Parse(info.URL)
	if err != nil {
		t.Fatal(err)
	}
	return info, u.Query()
}

// withT answers a minted URL with its cut set to raw, as a client moving
// the cut would.
func withT(t *testing.T, minted, raw string) string {
	t.Helper()
	u, err := url.Parse(minted)
	if err != nil {
		t.Fatal(err)
	}
	q := u.Query()
	q.Set("t", raw)
	u.RawQuery = q.Encode()
	return u.String()
}

// sidecar records the query of every request the fake engine received.
type sidecar struct{ got []url.Values }

func (s *sidecar) serve(w http.ResponseWriter, r *http.Request) {
	s.got = append(s.got, r.URL.Query())
	io.WriteString(w, "audio")
}

// A stream that cannot be range-seeked is cut where the client asked, to
// the whole second at or before it, and the info says where it begins.
func TestPlayInfoCutsANonSeekableStreamAtTheRequestedPosition(t *testing.T) {
	b := newTestBridge(t, func(http.ResponseWriter, *http.Request) {}, cutSource(t, "song.flac", longFLAC))
	info, q := mintQuery(t, b, PlayOptions{MaxBitrateKbps: 128, StartMS: 90_500})
	if info.Seekable {
		t.Fatal("a capped stream advertised seekable")
	}
	if q.Get("t") != "90" {
		t.Fatalf("cut = %q, want whole seconds floored to 90 (%s)", q.Get("t"), info.URL)
	}
	if info.StartOffsetMS != 90_000 {
		t.Fatalf("start offset = %d, want 90000", info.StartOffsetMS)
	}

	// Past the end is clamped into the item rather than handed on as an
	// empty stream, and under a second there is nothing to cut.
	info, q = mintQuery(t, b, PlayOptions{MaxBitrateKbps: 128, StartMS: 900_000})
	if q.Get("t") != "199" || info.StartOffsetMS != 199_000 {
		t.Errorf("a cut past the end = t %q, offset %d; want the last whole second, 199", q.Get("t"), info.StartOffsetMS)
	}
	info, q = mintQuery(t, b, PlayOptions{MaxBitrateKbps: 128, StartMS: 999})
	if q.Has("t") || info.StartOffsetMS != 0 {
		t.Errorf("a sub-second cut = t %q, offset %d; want none", q.Get("t"), info.StartOffsetMS)
	}
}

// A seekable stream is the client's to seek: a position cuts nothing, and
// a forced format, which the mint advertises seekable, is not cut either.
func TestPlayInfoLeavesASeekableStreamUncut(t *testing.T) {
	b := newTestBridge(t, func(http.ResponseWriter, *http.Request) {}, cutSource(t, "song.flac", longFLAC))
	for name, opts := range map[string]PlayOptions{
		"an original":     {StartMS: 90_500},
		"a forced format": {StartMS: 90_500, ForceFormat: "mp3"},
	} {
		info, q := mintQuery(t, b, opts)
		if !info.Seekable || q.Has("t") || info.StartOffsetMS != 0 {
			t.Errorf("%s: seekable %v, t %q, offset %d; want an uncut seekable stream",
				name, info.Seekable, q.Get("t"), info.StartOffsetMS)
		}
	}
}

// The cut the mint chose reaches the engine, and it is not part of the
// credential: a client moving it costs what minting again would.
func TestServeStreamForwardsTForACutStream(t *testing.T) {
	var engine sidecar
	b := newTestBridge(t, engine.serve, cutSource(t, "song.flac", longFLAC))
	info, _ := mintQuery(t, b, PlayOptions{MaxBitrateKbps: 128, StartMS: 90_500})
	for _, u := range []string{info.URL, withT(t, info.URL, "120")} {
		rec := httptest.NewRecorder()
		b.ServeStream(rec, httptest.NewRequest("GET", u, nil))
		if rec.Code != 200 {
			t.Fatalf("%s = %d: %s", u, rec.Code, rec.Body.String())
		}
	}
	if len(engine.got) != 2 {
		t.Fatalf("the engine saw %d requests, want 2", len(engine.got))
	}
	for i, want := range []string{"90", "120"} {
		if q := engine.got[i]; q.Get("t") != want || q.Get("bitrate") != "128" || q.Get("format") != "opus" {
			t.Errorf("request %d reached the engine as %v, want t=%s at opus 128", i, q, want)
		}
	}
}

// A forced format is an engine render whatever the mint advertised to the
// device, so its cut reaches the engine, admitted: the jukebox seeks every
// item that is not already a WAV this way.
func TestServeStreamForwardsTForAForcedFormat(t *testing.T) {
	var engine sidecar
	b := newTestBridge(t, engine.serve, cutSource(t, "song.flac", longFLAC))
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)
	info, q := mintQuery(t, b, PlayOptions{ForceFormat: "wav"})
	if q.Get("fmt") != "wav" {
		t.Fatalf("minted %s, want the forced wav", info.URL)
	}
	rec := httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", withT(t, info.URL, "1.5"), nil))
	if rec.Code != 200 || gate.acquired != 1 || len(engine.got) != 1 {
		t.Fatalf("a forced format's cut = %d with %d slots and %d engine requests, want 200, one and one: %s",
			rec.Code, gate.acquired, len(engine.got), rec.Body.String())
	}
	if got := engine.got[0]; got.Get("format") != "wav" || got.Get("t") != "1.5" {
		t.Fatalf("the engine saw %v, want wav from 1.5", got)
	}
}

// A cut on a direct play is refused before anything reaches the engine or
// takes a slot: the original's bytes are seeked by range, and a cut would
// turn them into an unadmitted decode.
func TestServeStreamRefusesTOnADirectPlayShape(t *testing.T) {
	var engine sidecar
	b := newTestBridge(t, engine.serve, cutSource(t, "song.flac", longFLAC))
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)
	info, _ := mintQuery(t, b, PlayOptions{})
	for name, u := range map[string]string{
		"an original":            withT(t, info.URL, "1"),
		"a copy of the original": withT(t, shapedURL(t, b, "tr-X", url.Values{"fmt": {"flac"}}), "1"),
	} {
		rec := httptest.NewRecorder()
		b.ServeStream(rec, httptest.NewRequest("GET", u, nil))
		wantEnvelope(t, rec, http.StatusBadRequest, "invalid-request")
		if len(engine.got) != 0 || gate.acquired != 0 {
			t.Fatalf("%s: the engine saw %d requests and %d slots were taken, want none", name, len(engine.got), gate.acquired)
		}
	}
	// The same URL without the cut plays.
	rec := httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", info.URL, nil))
	if rec.Code != 200 || engine.got[0].Get("format") != "auto" {
		t.Fatalf("the uncut original = %d, engine %v", rec.Code, engine.got)
	}
}

// A cut the engine could not use is refused the same way, before a slot;
// one at or past the end clamps to the item's last millisecond, as the
// mint clamps it (the engine reads the end itself as an empty stream), and
// what reaches the engine is one spelling per cut.
func TestServeStreamRefusesABadT(t *testing.T) {
	var engine sidecar
	b := newTestBridge(t, engine.serve, cutSource(t, "song.flac", longFLAC))
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)
	info, _ := mintQuery(t, b, PlayOptions{MaxBitrateKbps: 128, StartMS: 90_500})
	for _, raw := range []string{"abc", "-1", "-0.5", "NaN", "Inf", "+Inf", "-Inf", "infinity", "1e400", "0x", "1,5"} {
		rec := httptest.NewRecorder()
		b.ServeStream(rec, httptest.NewRequest("GET", withT(t, info.URL, raw), nil))
		if rec.Code != http.StatusBadRequest {
			t.Errorf("t=%s = %d, want 400", raw, rec.Code)
			continue
		}
		wantEnvelope(t, rec, http.StatusBadRequest, "invalid-request")
	}
	if len(engine.got) != 0 || gate.acquired != 0 {
		t.Fatalf("refused cuts reached the engine %d times and took %d slots", len(engine.got), gate.acquired)
	}

	for raw, want := range map[string]string{
		"1e18":   "199.999", // past the end: the item's last millisecond
		"200":    "199.999", // the end itself
		"0090":   "90",
		"90.25":  "90.25",
		"0.29":   "0.29",
		"0x1p3":  "8",
		"0":      "", // no cut at all
		"-0":     "",
		"0.0001": "",
	} {
		engine.got = nil
		rec := httptest.NewRecorder()
		b.ServeStream(rec, httptest.NewRequest("GET", withT(t, info.URL, raw), nil))
		if rec.Code != 200 || len(engine.got) != 1 {
			t.Errorf("t=%s = %d with %d engine requests, want 200 and one", raw, rec.Code, len(engine.got))
			continue
		}
		if got := engine.got[0]; got.Get("t") != want || got.Has("t") != (want != "") {
			t.Errorf("t=%s reached the engine as t=%q, want %q", raw, got.Get("t"), want)
		}
	}
}

// A cut is a transcode like any other: refused at the session limit, one
// slot when admitted.
func TestServeStreamAdmitsACutLikeAnyTranscode(t *testing.T) {
	var engine sidecar
	b := newTestBridge(t, engine.serve, cutSource(t, "song.flac", longFLAC))
	gate := &fakeGate{refuse: true}
	b.SetTranscodeGate(gate)
	info, q := mintQuery(t, b, PlayOptions{MaxBitrateKbps: 128, StartMS: 90_500})
	if q.Get("t") != "90" {
		t.Fatalf("minted %s, want a cut at 90", info.URL)
	}
	rec := httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", info.URL, nil))
	wantEnvelope(t, rec, http.StatusTooManyRequests, "transcode-limited")
	if len(engine.got) != 0 {
		t.Fatalf("a refused cut reached the engine")
	}

	gate.refuse = false
	rec = httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", info.URL, nil))
	if rec.Code != 200 || gate.acquired != 1 || gate.held != 0 {
		t.Fatalf("an admitted cut = %d, %d slots taken, %d still held; want one taken and released",
			rec.Code, gate.acquired, gate.held)
	}
	if engine.got[0].Get("t") != "90" {
		t.Fatalf("the admitted cut reached the engine as %v", engine.got[0])
	}
}

// The engine's own admission says busy in its envelope; the client is
// handed the one busy code it already knows, with the engine's retry hint.
// Any other refusal keeps its status and its retry hint, in the API's
// envelope rather than the engine's.
func TestSidecarOverloadedBecomesTranscodeLimited(t *testing.T) {
	answer := func(code string) http.HandlerFunc {
		return func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			w.Header().Set("Retry-After", "2")
			w.WriteHeader(http.StatusServiceUnavailable)
			fmt.Fprintf(w, `{"error":"no","code":%q,"schemaVersion":1}`, code)
		}
	}
	src := cutSource(t, "song.flac", longFLAC)
	b := newTestBridge(t, answer("overloaded"), src)
	info, _ := mintQuery(t, b, PlayOptions{MaxBitrateKbps: 128})
	rec := httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", info.URL, nil))
	wantEnvelope(t, rec, http.StatusTooManyRequests, "transcode-limited")
	if got := rec.Header().Get("Retry-After"); got != "2" {
		t.Errorf("Retry-After = %q, want the engine's 2", got)
	}

	b = newTestBridge(t, answer("catalog-unavailable"), src)
	info, _ = mintQuery(t, b, PlayOptions{MaxBitrateKbps: 128})
	rec = httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", info.URL, nil))
	wantEnvelope(t, rec, http.StatusServiceUnavailable, "internal")
	if got := rec.Header().Get("Retry-After"); got != "2" {
		t.Errorf("Retry-After = %q, want the engine's 2", got)
	}
}

// A track carved out of a larger file is never seekable, so it is cut too,
// and the cut counts from the track's own start: the window still rides
// beside it.
func TestVirtualTrackCutIsRelativeToItsWindow(t *testing.T) {
	var engine sidecar
	src := cutSource(t, "album.flac", Source{
		Codec: "flac", Container: "flac", DurationMS: 120_000,
		Virtual: true, FromSample: 44100 * 300,
	})
	b := newTestBridge(t, engine.serve, src)
	info, q := mintQuery(t, b, PlayOptions{StartMS: 30_400})
	if info.Seekable || q.Get("t") != "30" || info.StartOffsetMS != 30_000 {
		t.Fatalf("carved track cut = seekable %v, t %q, offset %d; want t=30 from its own start",
			info.Seekable, q.Get("t"), info.StartOffsetMS)
	}
	rec := httptest.NewRecorder()
	b.ServeStream(rec, httptest.NewRequest("GET", info.URL, nil))
	if rec.Code != 200 || len(engine.got) != 1 {
		t.Fatalf("carved cut = %d: %s", rec.Code, rec.Body.String())
	}
	if got := engine.got[0]; got.Get("t") != "30" || got.Get("from") != fmt.Sprint(44100*300) || got.Has("to") {
		t.Fatalf("carved cut reached the engine as %v, want t=30 inside the open window", got)
	}
}

// An original asked to start part way in, by a client with no other way to
// say so, takes the encode a cap at its own bitrate would: lossless stays
// lossless, lossy keeps its codec where the engine has one and never goes
// above its own rate, a cap that applies shapes it exactly as it shapes
// the uncut stream, and every cut is admitted.
func TestCutOriginalTakesTheRungACapAtTheSourceRateWould(t *testing.T) {
	for name, c := range map[string]struct {
		src      Source
		ceiling  int
		maxKbps  int
		fmt, br  string
		engineBR string
	}{
		"a lossless original stays lossless": {
			src: longFLAC, fmt: "flac"},
		"a lossy original keeps its codec and rate": {
			src: Source{Codec: "mp3", Container: "mp3", BitrateKbps: 192, DurationMS: 200_000},
			fmt: "mp3", br: "192", engineBR: "192"},
		"a codec the engine does not write lands in opus": {
			src: Source{Codec: "vorbis", Container: "ogg", BitrateKbps: 160, DurationMS: 200_000},
			fmt: "opus", br: "160", engineBR: "160"},
		"an unknown rate takes the top of the range": {
			src: Source{Codec: "aac", Container: "mp4", DurationMS: 200_000},
			fmt: "aac", br: "320", engineBR: "320"},
		"a capped account's cut keeps to its ceiling": {
			src: longFLAC, ceiling: 64, fmt: "opus", br: "64", engineBR: "64"},
		"a client cap shapes it as it shapes the uncut stream": {
			src:     Source{Codec: "mp3", Container: "mp3", BitrateKbps: 192, DurationMS: 200_000},
			maxKbps: 96, fmt: "opus", br: "96", engineBR: "96"},
		"a cap above the source's own rate does not raise it": {
			src:     Source{Codec: "mp3", Container: "mp3", BitrateKbps: 128, DurationMS: 200_000},
			maxKbps: 192, fmt: "mp3", br: "128", engineBR: "128"},
	} {
		t.Run(name, func(t *testing.T) {
			var engine sidecar
			b := newTestBridge(t, engine.serve, cutSource(t, "source", c.src))
			gate := &fakeGate{ceiling: c.ceiling}
			b.SetTranscodeGate(gate)
			info, q := mintQuery(t, b, PlayOptions{StartMS: 61_500, CutOriginal: true, MaxBitrateKbps: c.maxKbps})
			if info.Seekable || info.StartOffsetMS != 61_000 {
				t.Fatalf("info = %+v, want an unseekable cut at 61 s", info)
			}
			if q.Get("fmt") != c.fmt || q.Get("br") != c.br || q.Get("enc") != "1" || q.Get("t") != "61" {
				t.Fatalf("url %s, want fmt=%s br=%s marked an encode, t=61", info.URL, c.fmt, c.br)
			}
			rec := httptest.NewRecorder()
			b.ServeStream(rec, httptest.NewRequest("GET", info.URL, nil))
			if rec.Code != 200 || gate.acquired != 1 {
				t.Fatalf("fetch = %d with %d slots taken, want 200 and one: %s", rec.Code, gate.acquired, rec.Body.String())
			}
			got := engine.got[0]
			if got.Get("format") != c.fmt || got.Get("bitrate") != c.engineBR || got.Get("t") != "61" {
				t.Fatalf("the engine saw %v, want %s at %q from 61 s", got, c.fmt, c.engineBR)
			}
		})
	}

	// Without a whole second to cut at, an original stays the file, and
	// without the flag an offset never touches one.
	b := newTestBridge(t, func(http.ResponseWriter, *http.Request) {}, cutSource(t, "song.flac", longFLAC))
	for name, opts := range map[string]PlayOptions{
		"a sub-second offset": {StartMS: 999, CutOriginal: true},
		"no flag":             {StartMS: 61_500},
	} {
		info, q := mintQuery(t, b, opts)
		if !info.Seekable || strings.Contains(info.URL, "fmt=") || q.Has("t") {
			t.Errorf("%s: %s seekable %v, want the original as it is", name, info.URL, info.Seekable)
		}
	}
}

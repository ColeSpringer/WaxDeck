package flow

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/auth"
)

// staticResolver serves one fixed source for any pid.
type staticResolver struct{ src Source }

func (r staticResolver) StreamSource(context.Context, string, string) (Source, error) {
	return r.src, nil
}

// capsJSON is what the fake sidecar reports. aac is an output because
// the one format whose container and codec can disagree is aac, and
// voice is a dynamics mode because a boosted stream is the case where
// forcing the source's own format is still a real encode.
func capsJSON() string {
	return `{"schemaVersion":1,
		"outputs":[{"name":"flac","live":true},{"name":"opus","live":true},
			{"name":"mp3","live":true},{"name":"aac","live":true}],
		"delivery":{"progressive":true,"cutFormats":["opus","aac"]},
		"dsp":{"dynamics":["off","voice"],"gainMaxVoiceDb":24}}`
}

func newTestBridge(t *testing.T, upstream http.HandlerFunc, src Source) *Bridge {
	t.Helper()
	fake := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/caps" {
			fmt.Fprint(w, capsJSON())
			return
		}
		upstream(w, r)
	}))
	t.Cleanup(fake.Close)

	b, err := New(context.Background(), Config{
		BaseURL:  fake.URL,
		APIKey:   "key",
		Roots:    []Root{{Name: "lib", Path: filepath.Dir(src.Path)}},
		Tokens:   auth.NewMediaTokens([]byte("test-secret-test-secret-test-sec"), 0),
		Resolver: staticResolver{src},
	})
	if err != nil {
		t.Fatal(err)
	}
	return b
}

func tokenURL(t *testing.T, b *Bridge, pid string) string {
	t.Helper()
	info, err := b.PlayInfoFor(context.Background(), "us-1", pid, PlayOptions{})
	if err != nil {
		t.Fatal(err)
	}
	return info.URL
}

func TestStreamStaleRewrite(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "song.flac")
	if err := os.WriteFile(path, []byte("flacbytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	src := Source{Path: path, Size: 9, MTimeNS: 42, Codec: "flac", Container: "flac"}

	// The upstream answers every stream with WaxFlow's 410 envelope.
	b := newTestBridge(t, func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusGone)
		fmt.Fprint(w, `{"error":"the source changed","code":"source-changed","schemaVersion":1}`)
	}, src)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest("GET", tokenURL(t, b, "tr-X"), nil)
	b.ServeStream(rec, req)

	if rec.Code != http.StatusGone {
		t.Fatalf("status = %d, want 410", rec.Code)
	}
	var e struct{ Code, Message string }
	if err := json.Unmarshal(rec.Body.Bytes(), &e); err != nil {
		t.Fatalf("body %q: %v", rec.Body.String(), err)
	}
	if e.Code != "stream-stale" {
		t.Fatalf("code = %q, want stream-stale", e.Code)
	}
}

func TestVirtualTrackWindow(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "album.flac")
	if err := os.WriteFile(path, []byte("cuerip"), 0o644); err != nil {
		t.Fatal(err)
	}
	src := Source{
		Path: path, Size: 6, MTimeNS: 7,
		Virtual: true, FromSample: 44100, ToSample: 88200,
		Codec: "flac", Container: "flac",
	}

	var got url.Values
	b := newTestBridge(t, func(w http.ResponseWriter, r *http.Request) {
		got = r.URL.Query()
		io.WriteString(w, "windowed")
	}, src)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest("GET", tokenURL(t, b, "tr-X"), nil)
	b.ServeStream(rec, req)

	if rec.Code != 200 {
		t.Fatalf("status = %d", rec.Code)
	}
	if got.Get("from") != "44100" || got.Get("to") != "88200" {
		t.Fatalf("window params = from=%s to=%s", got.Get("from"), got.Get("to"))
	}
	// A virtual span must name its format; auto would disqualify the cut.
	if got.Get("format") != "flac" {
		t.Fatalf("format = %q, want flac", got.Get("format"))
	}
	if got.Get("id") != "6-7" {
		t.Fatalf("id pin = %q, want 6-7", got.Get("id"))
	}
	if got.Get("src") != "lib/album.flac" {
		t.Fatalf("src = %q", got.Get("src"))
	}
}

func TestStreamRejectsBadToken(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "song.mp3")
	if err := os.WriteFile(path, []byte("mp3"), 0o644); err != nil {
		t.Fatal(err)
	}
	src := Source{Path: path, Size: 3, MTimeNS: 1, Codec: "mp3", Container: "mp3"}
	b := newTestBridge(t, func(w http.ResponseWriter, r *http.Request) {
		io.WriteString(w, "never reached")
	}, src)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest("GET", "/media/stream?pid=tr-X&mt=bogus", nil)
	b.ServeStream(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want 401", rec.Code)
	}
	if !json.Valid(rec.Body.Bytes()) {
		t.Fatalf("401 body is not structured JSON: %q", rec.Body.String())
	}
}

// Forcing the format the file already holds is a copy of the source,
// not a transcode: the auto shape stands, nothing is admitted, and the
// original bytes serve. Every other spelling of "force" engages the
// engine, which is what a session slot pays for.
func TestForcedFormatMatchingSourceTakesNoSlot(t *testing.T) {
	quiet := -30.0
	cases := []struct {
		name         string
		file         string
		src          Source
		format       string
		boost        bool
		wantAdmitted int
		// The format the sidecar is asked for; auto is the direct play.
		wantEngine string
	}{
		{
			name:       "the source's own format is a copy",
			file:       "song.flac",
			src:        Source{Codec: "flac", Container: "flac"},
			format:     "flac",
			wantEngine: "auto",
		},
		{
			name:         "a real transcode admits",
			file:         "song.flac",
			src:          Source{Codec: "flac", Container: "flac"},
			format:       "mp3",
			wantAdmitted: 1,
			wantEngine:   "mp3",
		},
		{
			// Same codec, another wrapper: the engine has to reframe it.
			name:         "a remux admits",
			file:         "song.aac",
			src:          Source{Codec: "aac", Container: "aac (adts)"},
			format:       "aac",
			wantAdmitted: 1,
			wantEngine:   "aac",
		},
		{
			name:         "a virtual track has no whole file to copy",
			file:         "album.flac",
			src:          Source{Codec: "flac", Container: "flac", Virtual: true, FromSample: 44100, ToSample: 88200},
			format:       "flac",
			wantAdmitted: 1,
			wantEngine:   "flac",
		},
		{
			name:         "voice boost is a stage the stored bytes do not carry",
			file:         "episode.flac",
			src:          Source{Codec: "flac", Container: "flac", SpokenWord: true, IntegratedLUFS: &quiet},
			format:       "flac",
			boost:        true,
			wantAdmitted: 1,
			wantEngine:   "flac",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			path := filepath.Join(dir, tc.file)
			if err := os.WriteFile(path, []byte("bytes"), 0o644); err != nil {
				t.Fatal(err)
			}
			src := tc.src
			src.Path, src.Size, src.MTimeNS = path, 5, 1

			var got url.Values
			b := newTestBridge(t, func(w http.ResponseWriter, r *http.Request) {
				got = r.URL.Query()
				io.WriteString(w, "served")
			}, src)
			gate := &fakeGate{}
			b.SetTranscodeGate(gate)

			u := tokenURL(t, b, "tr-X") + "&fmt=" + tc.format
			if tc.boost {
				u += "&vb=1"
			}
			rec := httptest.NewRecorder()
			b.ServeStream(rec, httptest.NewRequest("GET", u, nil))
			if rec.Code != 200 || rec.Body.String() != "served" {
				t.Fatalf("status = %d body = %q", rec.Code, rec.Body.String())
			}
			if gate.acquired != tc.wantAdmitted {
				t.Fatalf("admissions = %d, want %d", gate.acquired, tc.wantAdmitted)
			}
			if got.Get("format") != tc.wantEngine {
				t.Fatalf("engine format = %q, want %q", got.Get("format"), tc.wantEngine)
			}
		})
	}
}

// The mint side of the same rule: a forced format naming the file's own
// never reaches the URL, so the client is told the container's real
// media type and the stream stays seekable.
func TestPlayInfoDropsForcedFormatMatchingSource(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "song.flac")
	if err := os.WriteFile(path, []byte("bytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	src := Source{Path: path, Size: 5, MTimeNS: 1, Codec: "flac", Container: "flac"}
	b := newTestBridge(t, func(http.ResponseWriter, *http.Request) {}, src)

	info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{ForceFormat: "flac"})
	if err != nil {
		t.Fatal(err)
	}
	u, err := url.Parse(info.URL)
	if err != nil {
		t.Fatal(err)
	}
	if u.Query().Get("fmt") != "" {
		t.Fatalf("URL = %s, want no format hint", info.URL)
	}
	if !info.Seekable || info.MimeType != "audio/flac" {
		t.Fatalf("info = %+v, want a seekable audio/flac direct play", info)
	}

	// The counterexample, on the same source: a format the file is not.
	info, err = b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{ForceFormat: "mp3"})
	if err != nil {
		t.Fatal(err)
	}
	u, err = url.Parse(info.URL)
	if err != nil {
		t.Fatal(err)
	}
	if u.Query().Get("fmt") != "mp3" || info.MimeType != "audio/mpeg" {
		t.Fatalf("forced mp3 = %s / %s", info.URL, info.MimeType)
	}
}

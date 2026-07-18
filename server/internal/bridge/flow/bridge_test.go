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

func (r staticResolver) StreamSource(context.Context, string) (Source, error) {
	return r.src, nil
}

func capsJSON() string {
	return `{"schemaVersion":1,
		"outputs":[{"name":"flac","live":true},{"name":"opus","live":true},{"name":"mp3","live":true}],
		"delivery":{"progressive":true,"cutFormats":["opus","aac"]},
		"dsp":{}}`
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
	info, err := b.PlayInfoFor(context.Background(), "us-1", pid)
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

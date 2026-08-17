package providers

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"slices"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// pngBytes is enough of a PNG for the sniffer to call it one, which is
// what the fetcher decides the served type from.
func pngBytes() []byte { return append([]byte("\x89PNG\r\n\x1a\n"), bytes.Repeat([]byte{0}, 64)...) }

func testCAA(srv *httptest.Server, maxBytes int64) *CoverArt {
	return NewCoverArt(CoverArtConfig{
		BaseURL:     srv.URL,
		HTTPClient:  srv.Client(),
		MinInterval: time.Nanosecond,
		MaxBytes:    maxBytes,
	})
}

// The archive holds several renditions and never upscales, so asking for
// the large one costs nothing where the source is small and is the only
// way to fill a full-screen face where it is not.
func TestCoverArtAsksForTheLargeRendition(t *testing.T) {
	t.Parallel()
	var gotPath atomic.Value
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotPath.Store(r.URL.Path)
		w.Header().Set("Content-Type", "image/png")
		w.Write(pngBytes())
	}))
	defer srv.Close()

	data, mime, err := testCAA(srv, 0).FrontCover(context.Background(), "rel-1")
	if err != nil {
		t.Fatal(err)
	}
	if got, _ := gotPath.Load().(string); got != "/release/rel-1/front-1200" {
		t.Fatalf("path = %q, want the 1200px rendition", got)
	}
	if mime != "image/png" || len(data) == 0 {
		t.Fatalf("cover = (%d bytes, %q)", len(data), mime)
	}
}

func TestCoverArtOutcomes(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name    string
		status  int
		body    []byte
		wantErr error
	}{
		{"a cover", http.StatusOK, pngBytes(), nil},
		// The ordinary answer: most releases have no art, and the caller
		// caches this for far longer than it caches a failure.
		{"nothing on file", http.StatusNotFound, nil, ErrNoCover},
		// The type comes from the bytes, never from the header: these are
		// served back from WaxDeck's own origin.
		{"an error page wearing an image header", http.StatusOK, []byte("<html>nope</html>"), ErrNoCover},
		{"an empty body", http.StatusOK, nil, ErrNoCover},
	}
	for _, tc := range cases {
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.Header().Set("Content-Type", "image/png")
			w.WriteHeader(tc.status)
			w.Write(tc.body)
		}))
		_, _, err := testCAA(srv, 0).FrontCover(context.Background(), "rel-1")
		if !errors.Is(err, tc.wantErr) {
			t.Errorf("%s: err = %v, want %v", tc.name, err, tc.wantErr)
		}
		srv.Close()
	}

	// A 5xx is neither of those: upstream may answer next time, and the
	// caller remembers that for minutes rather than for a day.
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer srv.Close()
	_, _, err := testCAA(srv, 0).FrontCover(context.Background(), "rel-1")
	if err == nil || errors.Is(err, ErrNoCover) {
		t.Fatalf("503 err = %v, want a reach error rather than a miss", err)
	}

	// An empty mbid asks nobody anything.
	if _, _, err := testCAA(srv, 0).FrontCover(context.Background(), ""); !errors.Is(err, ErrNoCover) {
		t.Fatalf("empty mbid err = %v, want ErrNoCover", err)
	}
}

// The cap is read one past and refused, so an oversize body is never
// held whole - and it is a reach error rather than a miss, because
// nothing about this release says it has no cover.
func TestCoverArtRefusesAnOversizeBody(t *testing.T) {
	t.Parallel()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "image/png")
		w.Write(append(pngBytes(), bytes.Repeat([]byte{0}, 4096)...))
	}))
	defer srv.Close()

	_, _, err := testCAA(srv, 512).FrontCover(context.Background(), "rel-1")
	if err == nil || errors.Is(err, ErrNoCover) {
		t.Fatalf("err = %v, want a refusal", err)
	}
}

// fakeReleaseLookup stands in for the MusicBrainz half of the composer.
type fakeReleaseLookup struct {
	ids  []string
	err  error
	call atomic.Int64
}

func (f *fakeReleaseLookup) ReleaseMBIDsForRecording(_ context.Context, _, _ string) ([]string, error) {
	f.call.Add(1)
	return f.ids, f.err
}

// errUpstream is a caller's own answered-and-empty sentinel, which is
// what the composer's NoCover field exists to carry.
var errUpstream = errors.New("test: nothing upstream")

func TestRecordingCoverWalksUntilOneReleaseHasArt(t *testing.T) {
	t.Parallel()
	var mu sync.Mutex
	var asked []string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id, _, _ := strings.Cut(strings.TrimPrefix(r.URL.Path, "/release/"), "/")
		mu.Lock()
		asked = append(asked, id)
		mu.Unlock()
		if id != "has-art" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "image/png")
		w.Write(pngBytes())
	}))
	defer srv.Close()

	rc := RecordingCover{
		MB:      &fakeReleaseLookup{ids: []string{"bare-1", "bare-2", "has-art", "never"}},
		CAA:     testCAA(srv, 0),
		NoCover: errUpstream,
	}
	data, mime, err := rc.FrontCover(context.Background(), "a-ha", "Take On Me")
	if err != nil {
		t.Fatal(err)
	}
	if mime != "image/png" || len(data) == 0 {
		t.Fatalf("cover = (%d bytes, %q)", len(data), mime)
	}
	// Having a release is not having a picture of it, and the walk stops
	// the moment one answers rather than asking the whole list.
	mu.Lock()
	defer mu.Unlock()
	if want := []string{"bare-1", "bare-2", "has-art"}; !slices.Equal(asked, want) {
		t.Fatalf("asked %q, want %q", asked, want)
	}
}

// A release the archive could not be asked about says nothing about the
// next one, so the error is held and only surfaces if none of them
// answers.
func TestRecordingCoverHoldsAReachErrorPastAWorkingRelease(t *testing.T) {
	t.Parallel()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.Contains(r.URL.Path, "broken") {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		w.Header().Set("Content-Type", "image/png")
		w.Write(pngBytes())
	}))
	defer srv.Close()

	rc := RecordingCover{
		MB:      &fakeReleaseLookup{ids: []string{"broken", "fine"}},
		CAA:     testCAA(srv, 0),
		NoCover: errUpstream,
	}
	if _, _, err := rc.FrontCover(context.Background(), "a-ha", "Take On Me"); err != nil {
		t.Fatalf("err = %v, want the cover from the release that answered", err)
	}

	// Nothing answered: the reach error is the outcome, not the miss, so
	// the caller remembers it for minutes rather than for a day.
	rc.MB = &fakeReleaseLookup{ids: []string{"broken-1", "broken-2"}}
	_, _, err := rc.FrontCover(context.Background(), "a-ha", "Take On Me")
	if err == nil || errors.Is(err, errUpstream) {
		t.Fatalf("err = %v, want a reach error rather than a miss", err)
	}
}

func TestRecordingCoverMissesAreTheCallersSentinel(t *testing.T) {
	t.Parallel()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	// MusicBrainz knows no recording by this name, which will still be
	// true tomorrow far more often than not.
	nothing := &fakeReleaseLookup{}
	rc := RecordingCover{MB: nothing, CAA: testCAA(srv, 0), NoCover: errUpstream}
	if _, _, err := rc.FrontCover(context.Background(), "Nobody", "Nothing"); !errors.Is(err, errUpstream) {
		t.Fatalf("err = %v, want the caller's sentinel", err)
	}

	// Every release answered and none had a picture: the same outcome.
	rc.MB = &fakeReleaseLookup{ids: []string{"bare-1", "bare-2"}}
	if _, _, err := rc.FrontCover(context.Background(), "a-ha", "Take On Me"); !errors.Is(err, errUpstream) {
		t.Fatalf("err = %v, want the caller's sentinel", err)
	}

	// A search that could not be made is not an empty search, and never
	// reaches the archive.
	rc.MB = &fakeReleaseLookup{err: errors.New("musicbrainz unreachable")}
	if _, _, err := rc.FrontCover(context.Background(), "a-ha", "Take On Me"); errors.Is(err, errUpstream) {
		t.Fatalf("err = %v, want the lookup's own error", err)
	}

	// Half-wired is not wired: no resolver means no request, not a panic.
	bare := RecordingCover{NoCover: errUpstream}
	if _, _, err := bare.FrontCover(context.Background(), "a-ha", "Take On Me"); !errors.Is(err, errUpstream) {
		t.Fatalf("unwired err = %v, want the caller's sentinel", err)
	}
	if nothing.call.Load() != 1 {
		t.Fatalf("lookup calls = %d, want 1", nothing.call.Load())
	}
}

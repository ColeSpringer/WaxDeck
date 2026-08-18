package providers

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"slices"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/enrich"
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

// 500px is what a station face needs, and the archive's storage is slow
// enough that the bytes are the wait.
func TestCoverArtAsksForTheStationFaceRendition(t *testing.T) {
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
	if got, _ := gotPath.Load().(string); got != "/release/rel-1/front-500" {
		t.Fatalf("path = %q, want the 500px rendition", got)
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
		// served back from WaxDeck's own origin. And a 200 that is not a
		// raster is the archive's storage failing under load, not this
		// release being bare, so it is not the long-cached answer.
		{"an error page wearing an image header", http.StatusOK, []byte("<html>nope</html>"), errNotAnImage},
		{"an empty body", http.StatusOK, nil, errNotAnImage},
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

// The archive's 404 is the commonest answer and the most stable one, so
// it is remembered rather than re-asked at a paced request a time.
func TestCoverArtRemembersWhatTheArchiveDoesNotHold(t *testing.T) {
	t.Parallel()
	var hits atomic.Int64
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	caa := testCAA(srv, 0)
	for range 3 {
		if _, _, err := caa.FrontCover(context.Background(), "bare"); !errors.Is(err, ErrNoCover) {
			t.Fatalf("err = %v, want ErrNoCover", err)
		}
	}
	if got := hits.Load(); got != 1 {
		t.Fatalf("asked the archive %d times, want 1", got)
	}
	// A different release is a different question.
	if _, _, err := caa.FrontCover(context.Background(), "other"); !errors.Is(err, ErrNoCover) {
		t.Fatalf("err = %v, want ErrNoCover", err)
	}
	if got := hits.Load(); got != 2 {
		t.Fatalf("asked the archive %d times, want 2", got)
	}
}

// Only the 404. A 5xx says the archive could not answer, not that the
// release is bare, and remembering it would turn one bad minute upstream
// into a day of blank faces.
func TestCoverArtDoesNotRememberAFailureToAsk(t *testing.T) {
	t.Parallel()
	var hits atomic.Int64
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		if hits.Add(1) == 1 {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		w.Header().Set("Content-Type", "image/png")
		w.Write(pngBytes())
	}))
	defer srv.Close()

	caa := testCAA(srv, 0)
	if _, _, err := caa.FrontCover(context.Background(), "flaky"); err == nil {
		t.Fatal("a 502 answered as though it were a cover")
	}
	data, _, err := caa.FrontCover(context.Background(), "flaky")
	if err != nil || len(data) == 0 {
		t.Fatalf("the retry got (%d bytes, %v), want the cover", len(data), err)
	}
}

// A remembered miss expires: a release entered this week can have no
// cover today and one tomorrow.
func TestCoverArtForgetsAMissEventually(t *testing.T) {
	t.Parallel()
	var hits atomic.Int64
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	caa := NewCoverArt(CoverArtConfig{
		BaseURL:     srv.URL,
		HTTPClient:  srv.Client(),
		MinInterval: time.Nanosecond,
		MissTTL:     time.Millisecond,
	})
	caa.FrontCover(context.Background(), "bare")
	// Stored at all, first: without this the expiry below passes on a
	// memory that never remembered anything.
	caa.FrontCover(context.Background(), "bare")
	if got := hits.Load(); got != 1 {
		t.Fatalf("asked the archive %d times inside the ttl, want 1", got)
	}
	time.Sleep(5 * time.Millisecond)
	caa.FrontCover(context.Background(), "bare")
	if got := hits.Load(); got != 2 {
		t.Fatalf("asked the archive %d times, want 2 - the memory never expired", got)
	}
}

// The memory is the archive's 404s and nothing else, so an operator who
// switched the rung off and back on to force a refetch gets one rather
// than a day-old private map answering for it.
func TestCoverArtMissMemoryCanBeForgotten(t *testing.T) {
	t.Parallel()
	var hits atomic.Int64
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	caa := testCAA(srv, 0)
	caa.FrontCover(context.Background(), "bare")
	caa.FrontCover(context.Background(), "bare")
	if got := hits.Load(); got != 1 {
		t.Fatalf("asked the archive %d times, want 1", got)
	}
	RecordingCover{CAA: caa}.ForgetMisses()
	caa.FrontCover(context.Background(), "bare")
	if got := hits.Load(); got != 2 {
		t.Fatalf("asked the archive %d times after the purge, want 2", got)
	}
}

// An expired entry holding its slot is how a bounded memory stops
// remembering anything: the ids never come back, so nothing looks them
// up, so nothing drops them.
func TestCoverArtMissMemoryReclaimsExpiredSlots(t *testing.T) {
	t.Parallel()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	caa := NewCoverArt(CoverArtConfig{
		BaseURL:     srv.URL,
		HTTPClient:  srv.Client(),
		MinInterval: time.Nanosecond,
		MissTTL:     time.Millisecond,
		MaxMisses:   8,
	})
	for i := range 8 {
		caa.FrontCover(context.Background(), "gone-"+strconv.Itoa(i))
	}
	time.Sleep(5 * time.Millisecond)
	caa.FrontCover(context.Background(), "fresh")
	caa.missMu.Lock()
	defer caa.missMu.Unlock()
	if len(caa.misses) != 1 || len(caa.missOrder) != 1 {
		t.Fatalf("memory holds %d entries over %d slots, want 1 over 1",
			len(caa.misses), len(caa.missOrder))
	}
}

// A 200 carrying an error page is upstream failing, not a release with
// nothing on file, so it is held as a reach error and the walk keeps
// going rather than filing the release as bare for a day.
func TestRecordingCoverTreatsANonImageAsUpstreamFailing(t *testing.T) {
	t.Parallel()
	var hits atomic.Int64
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		w.Header().Set("Content-Type", "image/jpeg")
		w.Write([]byte("<html>the storage node is having a moment</html>"))
	}))
	defer srv.Close()

	caa := testCAA(srv, 0)
	rc := RecordingCover{
		MB:      &fakeReleaseLookup{ids: []string{"a", "b"}},
		CAA:     caa,
		NoCover: errUpstream,
	}
	_, _, err := rc.FrontCover(context.Background(), "a-ha", "Take On Me")
	if err == nil || errors.Is(err, errUpstream) {
		t.Fatalf("err = %v, want a reach error rather than the miss sentinel", err)
	}
	if got := hits.Load(); got != 2 {
		t.Fatalf("the walk made %d requests, want both releases asked", got)
	}
	if caa.knownBare("a") {
		t.Fatal("an error page was filed as a release with nothing on file")
	}
}

// The ids come from searches for titles a station chooses, so the memory
// is bounded like every other cache that grows on a stranger's input.
func TestCoverArtMissMemoryIsBounded(t *testing.T) {
	t.Parallel()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	caa := NewCoverArt(CoverArtConfig{
		BaseURL:     srv.URL,
		HTTPClient:  srv.Client(),
		MinInterval: time.Nanosecond,
		MaxMisses:   4,
	})
	for i := range 12 {
		caa.FrontCover(context.Background(), "rel-"+strconv.Itoa(i))
	}
	caa.missMu.Lock()
	defer caa.missMu.Unlock()
	if len(caa.misses) > 4 {
		t.Fatalf("the miss memory holds %d entries, want at most 4", len(caa.misses))
	}
}

// The property the walk needs: a second pass does not re-ask about the
// releases already known bare, which is what makes a retry after a
// budget timeout cheap enough to be worth making.
func TestRecordingCoverDoesNotRewalkKnownBareReleases(t *testing.T) {
	t.Parallel()
	var hits atomic.Int64
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		id, _, _ := strings.Cut(strings.TrimPrefix(r.URL.Path, "/release/"), "/")
		if id != "has-art" {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.Header().Set("Content-Type", "image/png")
		w.Write(pngBytes())
	}))
	defer srv.Close()

	rc := RecordingCover{
		MB:      &fakeReleaseLookup{ids: []string{"bare-1", "bare-2", "bare-3", "has-art"}},
		CAA:     testCAA(srv, 0),
		NoCover: errUpstream,
	}
	if _, _, err := rc.FrontCover(context.Background(), "a-ha", "Take On Me"); err != nil {
		t.Fatal(err)
	}
	if got := hits.Load(); got != 4 {
		t.Fatalf("the first walk made %d requests, want 4", got)
	}
	if _, _, err := rc.FrontCover(context.Background(), "a-ha", "Take On Me"); err != nil {
		t.Fatal(err)
	}
	// Only the release that actually has the picture is fetched again.
	if got := hits.Load(); got != 5 {
		t.Fatalf("after the second walk %d requests total, want 5", got)
	}
}

// One release that has gone quiet must not spend the whole walk's
// budget: a release with nothing on file answers in well under a
// second, so the next candidate is worth more than the wait.
func TestCoverArtAbandonsAnUnresponsiveRelease(t *testing.T) {
	t.Parallel()
	release := make(chan struct{})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		<-release
	}))
	defer srv.Close()
	defer close(release)

	caa := NewCoverArt(CoverArtConfig{
		BaseURL:        srv.URL,
		HTTPClient:     srv.Client(),
		MinInterval:    time.Nanosecond,
		RequestTimeout: 30 * time.Millisecond,
	})
	start := time.Now()
	_, _, err := caa.FrontCover(context.Background(), "hung")
	if err == nil || errors.Is(err, ErrNoCover) {
		t.Fatalf("err = %v, want the fetch abandoned rather than a miss", err)
	}
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Fatalf("waited %v, want the per-request bound to cut it", elapsed)
	}
	// Abandoning is not learning: nothing about this release was
	// established, so it is asked again rather than filed as bare.
	if caa.knownBare("hung") {
		t.Fatal("an abandoned fetch was remembered as a miss")
	}
}

// The walk's own budget still outranks the per-request bound: the
// deadline ends the walk rather than starting another fetch.
func TestRecordingCoverStopsWalkingWhenTheBudgetIsSpent(t *testing.T) {
	t.Parallel()
	var hits atomic.Int64
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		hits.Add(1)
		w.WriteHeader(http.StatusNotFound)
	}))
	defer srv.Close()

	rc := RecordingCover{
		MB:      &fakeReleaseLookup{ids: []string{"a", "b", "c", "d"}},
		CAA:     testCAA(srv, 0),
		NoCover: errUpstream,
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, _, err := rc.FrontCover(ctx, "a-ha", "Take On Me"); !errors.Is(err, context.Canceled) {
		t.Fatalf("err = %v, want the walk to end on the spent budget", err)
	}
	if got := hits.Load(); got != 0 {
		t.Fatalf("made %d requests past the deadline, want 0", got)
	}
}

// deezerFixture serves the track search and the album cover behind it.
// TLS because fetchImage refuses anything but https.
func deezerFixture(t *testing.T, hits string) (*Deezer, *atomic.Int64, *atomic.Value) {
	t.Helper()
	var covers atomic.Int64
	var gotQuery atomic.Value
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/search":
			gotQuery.Store(r.URL.Query().Get("q"))
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, hits, r.Host)
		case "/cover.jpg":
			covers.Add(1)
			w.Header().Set("Content-Type", "image/jpeg")
			w.Write(pngBytes())
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(srv.Close)
	return NewDeezer(DeezerConfig{
		BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	}), &covers, &gotQuery
}

// A station announces a song, so the query is a track search and the
// picture is the album carrying it. The caller's side is already
// normalized, so the two meet on a fold rather than on punctuation.
func TestDeezerFrontCoverTakesTheAlbumOfTheMatchingTrack(t *testing.T) {
	t.Parallel()
	d, covers, gotQuery := deezerFixture(t, `{"data": [
		{"title": "Hello, Goodbye", "artist": {"name": "The Beatles"},
		 "album": {"cover_big": "https://%s/cover.jpg"}}
	]}`)

	data, mime, err := d.FrontCover(context.Background(), "the beatles", "hello goodbye")
	if err != nil {
		t.Fatal(err)
	}
	if q, _ := gotQuery.Load().(string); q != `artist:"the beatles" track:"hello goodbye"` {
		t.Fatalf("q = %q, want the advanced track query", q)
	}
	// The type is the bytes' rather than the header's, which said jpeg.
	if mime != "image/png" || len(data) == 0 {
		t.Fatalf("cover = (%d bytes, %q)", len(data), mime)
	}
	if got := covers.Load(); got != 1 {
		t.Fatalf("fetched %d covers, want 1", got)
	}
}

// A hit that is not this song is worse than no hit: the wrong cover on
// the face reads as the station playing something it is not.
func TestDeezerFrontCoverRefusesAHitThatIsNotTheSong(t *testing.T) {
	t.Parallel()
	d, covers, _ := deezerFixture(t, `{"data": [
		{"title": "Ornithology", "artist": {"name": "Somebody Else"},
		 "album": {"cover_big": "https://%s/cover.jpg"}},
		{"title": "Something Else", "artist": {"name": "Charlie Parker"},
		 "album": {"cover_big": "https://%s/cover.jpg"}}
	]}`)

	if _, _, err := d.FrontCover(context.Background(), "charlie parker", "ornithology"); !errors.Is(err, ErrNoCover) {
		t.Fatalf("err = %v, want ErrNoCover", err)
	}
	if got := covers.Load(); got != 0 {
		t.Fatalf("fetched %d covers for a song nobody matched, want 0", got)
	}
}

// fakeTitleCover is one rung of a chain, with a call counter so a test
// can see the rung that was never reached.
type fakeTitleCover struct {
	data   []byte
	mime   string
	err    error
	calls  atomic.Int64
	forgot atomic.Int64
}

func (f *fakeTitleCover) FrontCover(context.Context, string, string) ([]byte, string, error) {
	f.calls.Add(1)
	return f.data, f.mime, f.err
}

func (f *fakeTitleCover) ForgetMisses() { f.forgot.Add(1) }

func TestCoverChainOutcomes(t *testing.T) {
	t.Parallel()
	png := pngBytes()
	// The cheap source answering is the whole point of the order.
	first := &fakeTitleCover{data: png, mime: "image/png"}
	second := &fakeTitleCover{data: png, mime: "image/png"}
	chain := CoverChain{Sources: []TitleCover{first, second}, NoCover: errUpstream}
	if data, _, err := chain.FrontCover(context.Background(), "a-ha", "Take On Me"); err != nil || len(data) == 0 {
		t.Fatalf("got (%d bytes, %v), want the first source's cover", len(data), err)
	}
	if got := second.calls.Load(); got != 0 {
		t.Errorf("the second source was asked %d times past an answer, want 0", got)
	}

	// A miss falls through to the source below it.
	second = &fakeTitleCover{data: png, mime: "image/png"}
	chain = CoverChain{Sources: []TitleCover{&fakeTitleCover{err: ErrNoCover}, second}, NoCover: errUpstream}
	if data, _, err := chain.FrontCover(context.Background(), "a-ha", "Take On Me"); err != nil || len(data) == 0 {
		t.Fatalf("got (%d bytes, %v), want the second source's cover", len(data), err)
	}

	// A source that could not be reached is held past a source that
	// answered emptily, so the caller backs off for minutes rather than
	// remembering a miss for a day.
	chain = CoverChain{
		Sources: []TitleCover{
			&fakeTitleCover{err: errors.New("503 from upstream")},
			&fakeTitleCover{err: ErrNoCover},
		},
		NoCover: errUpstream,
	}
	_, _, err := chain.FrontCover(context.Background(), "a-ha", "Take On Me")
	if err == nil || errors.Is(err, errUpstream) {
		t.Fatalf("err = %v, want the reach error rather than the sentinel", err)
	}

	// Everyone answered and nobody held one: that is the caller's own
	// sentinel, whichever sentinel each source speaks.
	chain = CoverChain{
		Sources: []TitleCover{&fakeTitleCover{err: ErrNoCover}, &fakeTitleCover{err: errUpstream}},
		NoCover: errUpstream,
	}
	if _, _, err := chain.FrontCover(context.Background(), "a-ha", "Take On Me"); !errors.Is(err, errUpstream) {
		t.Fatalf("err = %v, want the caller's sentinel", err)
	}
}

// An operator's purge has to reach every memory the chain is holding,
// not only the one the caller happens to know about.
func TestCoverChainForwardsThePurge(t *testing.T) {
	t.Parallel()
	forgetful := &fakeTitleCover{err: ErrNoCover}
	CoverChain{Sources: []TitleCover{forgetful, &fakeTitleCover{}}}.ForgetMisses()
	if got := forgetful.forgot.Load(); got != 1 {
		t.Fatalf("purged %d times, want 1", got)
	}
}

func TestCoverNameMatch(t *testing.T) {
	t.Parallel()
	cases := []struct {
		upstream, normalized string
		want                 bool
	}{
		{"Hello, Goodbye", "hello goodbye", true},
		{"Don't Stop Believin'", "don't stop believin'", true},
		{"Don’t Stop", "don't stop", true},
		{"Ornithology", "anthropology", false},
	}
	for _, c := range cases {
		if got := coverNameMatch(c.upstream, c.normalized); got != c.want {
			t.Errorf("coverNameMatch(%q, %q) = %v, want %v", c.upstream, c.normalized, got, c.want)
		}
	}
}

// A song is listed several times over - a single, an album, a deluxe
// edition - so a first hit whose cover cannot be used must not end the
// walk, and a picture that is merely too big is not Deezer failing.
func TestDeezerFrontCoverWalksPastAnUnusableCover(t *testing.T) {
	t.Parallel()
	var covers atomic.Int64
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/search":
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"data": [
				{"title": "Ornithology", "artist": {"name": "Charlie Parker"},
				 "album": {"cover_big": "https://%s/gone.jpg"}},
				{"title": "Ornithology", "artist": {"name": "Charlie Parker"},
				 "album": {"cover_big": "https://%s/huge.jpg"}},
				{"title": "Ornithology", "artist": {"name": "Charlie Parker"},
				 "album": {"cover_big": "https://%s/cover.jpg"}}
			]}`, r.Host, r.Host, r.Host)
		case "/gone.jpg":
			covers.Add(1)
			w.WriteHeader(http.StatusNotFound)
		case "/huge.jpg":
			covers.Add(1)
			w.Header().Set("Content-Type", "image/png")
			w.Write(append(pngBytes(), bytes.Repeat([]byte{0}, maxTitleCoverBytes)...))
		case "/cover.jpg":
			covers.Add(1)
			w.Header().Set("Content-Type", "image/png")
			w.Write(pngBytes())
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()

	d := NewDeezer(DeezerConfig{
		BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})
	data, mime, err := d.FrontCover(context.Background(), "charlie parker", "ornithology")
	if err != nil || mime != "image/png" || len(data) == 0 {
		t.Fatalf("got (%d bytes, %q, %v), want the third hit's cover", len(data), mime, err)
	}
	if got := covers.Load(); got != 3 {
		t.Fatalf("fetched %d covers, want all three tried", got)
	}
}

// An oversize cover is a permanent fact about the picture, so a walk that
// finds nothing else answers with a miss the caller remembers for a day -
// not a reach error it retries every five minutes forever.
func TestDeezerFrontCoverReportsAnOversizeCoverAsAMiss(t *testing.T) {
	t.Parallel()
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/search" {
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"data": [{"title": "Ornithology",
				"artist": {"name": "Charlie Parker"},
				"album": {"cover_big": "https://%s/huge.jpg"}}]}`, r.Host)
			return
		}
		w.Header().Set("Content-Type", "image/png")
		w.Write(append(pngBytes(), bytes.Repeat([]byte{0}, maxTitleCoverBytes)...))
	}))
	defer srv.Close()

	d := NewDeezer(DeezerConfig{
		BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})
	if _, _, err := d.FrontCover(context.Background(), "charlie parker", "ornithology"); !errors.Is(err, ErrNoCover) {
		t.Fatalf("err = %v, want ErrNoCover", err)
	}
}

// The searches this rung makes are built from strings a station
// announced, so switching the rung off drops them - without emptying the
// album searches enrichment makes through the same client.
func TestDeezerForgetMissesSparesTheEnrichmentSearches(t *testing.T) {
	t.Parallel()
	var tracks, albums atomic.Int64
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/search":
			tracks.Add(1)
			w.Write([]byte(`{"data": []}`))
		case "/search/album":
			albums.Add(1)
			w.Write([]byte(`{"data": []}`))
		}
	}))
	defer srv.Close()

	d := NewDeezer(DeezerConfig{
		BaseURL: srv.URL, HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})
	ask := func() {
		d.FrontCover(context.Background(), "charlie parker", "ornithology")
		d.Enrich(context.Background(), enrich.Request{
			Type: enrich.TargetReleaseGroup, Title: "Discovery", Artist: "Daft Punk",
		})
	}
	ask()
	ask()
	if tracks.Load() != 1 || albums.Load() != 1 {
		t.Fatalf("cached badly: %d track searches, %d album searches, want 1 and 1",
			tracks.Load(), albums.Load())
	}

	d.ForgetMisses()
	ask()
	if got := tracks.Load(); got != 2 {
		t.Fatalf("track searches = %d, want the purge to have dropped them", got)
	}
	if got := albums.Load(); got != 1 {
		t.Fatalf("album searches = %d, want enrichment's cache left alone", got)
	}
}

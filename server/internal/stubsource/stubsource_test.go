package stubsource

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"os"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxbin/source"
	"github.com/colespringer/waxbin/waxerr"
	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

// The stub runs the same pass as the real bridge, from the served file's own
// tags, so a test stack shows a Topic download landing clean.
func TestFetchWithCleansTheServedFile(t *testing.T) {
	t.Parallel()
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{Codec: fixtures.CodecMP3, Duration: 200 * time.Millisecond,
		Tags: map[string]string{"TITLE": "Stub Cut (Official Audio)", "ARTIST": "DJ Stub - Topic"}})
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "audio/mpeg")
		_, _ = w.Write(raw)
	}))
	t.Cleanup(srv.Close)
	p := New(srv.URL)
	for _, tc := range []struct {
		name  string
		music bool
		title string
	}{
		{"music", true, "Stub Cut"},
		{"not music", false, "Stub Cut (Official Audio)"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var out bytes.Buffer
			url := srv.URL + "/audio/vid-1"
			res, err := p.FetchWith(context.Background(), source.FetchRequest{URL: url}, &out, syncsource.FetchOptions{Music: tc.music, Format: "flac"})
			if err != nil {
				t.Fatalf("FetchWith: %v", err)
			}
			if res.Bytes != int64(out.Len()) || res.ContentType != "audio/mpeg" {
				t.Errorf("result = %+v for %d bytes, want them all as audio/mpeg", res, out.Len())
			}
			doc, err := waxlabel.Parse(context.Background(), waxlabel.BytesSource(out.Bytes()))
			if err != nil {
				t.Fatal(err)
			}
			for k, want := range map[tag.Key][]string{
				tag.Artist:    {"DJ Stub"},
				tag.Title:     {tc.title},
				tag.SourceURL: {url},
				tag.SourceID:  {"vid-1"},
			} {
				if got, _ := doc.Get(k); !slices.Equal(got, want) {
					t.Errorf("%s = %q, want %q", k, got, want)
				}
			}
		})
	}
}

// A manifest the stub cannot read fails classed as the source's, as the
// real bridge's failures are, so a sync can tell it from the catalog's.
func TestAnUnreadableManifestIsTheSources(t *testing.T) {
	t.Parallel()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "gone", http.StatusServiceUnavailable)
	}))
	t.Cleanup(srv.Close)
	p := New(srv.URL)
	if _, err := p.Enumerate(context.Background(), source.Request{URL: srv.URL + "/playlist/x"}); waxerr.CodeOf(err) != waxerr.CodeIO {
		t.Errorf("enumerate failed with %v (class %q), want io", err, waxerr.CodeOf(err))
	}
	if _, err := p.Resolve(context.Background(), source.Request{URL: srv.URL + "/playlist/x"}); waxerr.CodeOf(err) != waxerr.CodeIO {
		t.Errorf("resolve failed with %v (class %q), want io", err, waxerr.CodeOf(err))
	}
}

// manifestServer serves doc as every manifest.
func manifestServer(t *testing.T, doc string) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(doc))
	}))
	t.Cleanup(srv.Close)
	return srv
}

// A manifest's refuse flag is the stub's private list: the check before
// queuing, the listing and the snapshot all refuse it with that reason.
func TestARefusingManifestRefusesEverywhere(t *testing.T) {
	t.Parallel()
	srv := manifestServer(t, `{"id":"PLprivate","title":"Stub Private","refuse":"playlist-unavailable","entries":[{"id":"vid-private","title":"Hidden"}]}`)
	p := New(srv.URL)
	ctx := context.Background()
	link := srv.URL + "/playlist-private"
	refused := func(what string, err error) {
		t.Helper()
		var r *syncsource.Refusal
		if !errors.As(err, &r) || r.Reason != "playlist-unavailable" {
			t.Errorf("%s = %v, want the manifest's refusal", what, err)
		}
	}
	target, err := p.Probe(ctx, link, false)
	refused("probe", err)
	if target.Shape != syncsource.ShapePlaylist {
		t.Errorf("probe shape = %q, want a playlist", target.Shape)
	}
	_, err = p.Enumerate(ctx, source.Request{URL: link})
	refused("enumerate", err)
	_, err = p.PlaylistSnapshot(ctx, link, syncsource.SnapshotOptions{})
	refused("snapshot", err)
}

// The stub reads its own shapes off the path, and a link to another host
// is not its to read.
func TestProbeShapes(t *testing.T) {
	t.Parallel()
	srv := manifestServer(t, `{"id":"PLstub","title":"Stub Tapes","entries":[]}`)
	p := New(srv.URL)
	ctx := context.Background()
	if got, err := p.Probe(ctx, srv.URL+"/playlist", false); err != nil || got != (syncsource.AcquireTarget{Shape: syncsource.ShapePlaylist, Title: "Stub Tapes"}) {
		t.Errorf("a list = %+v, %v; want the playlist titled from its manifest", got, err)
	}
	if got, err := p.Probe(ctx, srv.URL+"/audio/vid-1", true); err != nil || got.Shape != syncsource.ShapeVideo {
		t.Errorf("an entry = %+v, %v; want a video", got, err)
	}
	var r *syncsource.Refusal
	if _, err := p.Probe(ctx, "https://example.com/playlist", false); !errors.As(err, &r) || r.Reason != syncsource.ReasonUnsupportedURL {
		t.Errorf("a foreign link = %v, want an unsupported-url refusal", err)
	}
}

// The stub reports the bytes it serves as it reads them, against the size
// the server gave, then the tag pass as processing; a listing reports its
// one page.
func TestTheStubReportsWhatItServes(t *testing.T) {
	t.Parallel()
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{Codec: fixtures.CodecMP3, Duration: 200 * time.Millisecond})
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("/audio/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "audio/mpeg")
		http.ServeContent(w, r, "a.mp3", time.Time{}, bytes.NewReader(raw))
	})
	mux.HandleFunc("/playlist", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"id":"pl","title":"List","entries":[{"id":"a","title":"A"},{"id":"b","title":"B"}]}`))
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	p := New(srv.URL)

	var events []syncsource.FetchEvent
	var out bytes.Buffer
	if _, err := p.FetchWith(context.Background(), source.FetchRequest{URL: srv.URL + "/audio/a"}, &out,
		syncsource.FetchOptions{OnEvent: func(e syncsource.FetchEvent) { events = append(events, e) }}); err != nil {
		t.Fatalf("FetchWith: %v", err)
	}
	size := int64(len(raw))
	var last syncsource.FetchEvent
	downloads := 0
	for _, e := range events {
		if e.Phase == syncsource.PhaseDownloading {
			downloads++
			if e.Total != size || e.Bytes < last.Bytes {
				t.Errorf("download event %+v after %+v, want bytes rising against %d", e, last, size)
			}
			last = e
		}
	}
	if downloads == 0 || last.Bytes != size {
		t.Fatalf("download events %+v, want them to reach all %d bytes", events, size)
	}
	if events[len(events)-1].Phase != syncsource.PhaseProcessing {
		t.Errorf("last event %+v, want the tag pass as processing", events[len(events)-1])
	}

	var pages []int
	if _, err := p.EnumerateOnce(context.Background(), source.Request{URL: srv.URL + "/playlist"},
		syncsource.EnumerateOptions{Progress: syncsource.ListProgress{OnPage: func(n int) { pages = append(pages, n) }}}); err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(pages, []int{2}) {
		t.Errorf("pages = %v, want the one page of two", pages)
	}
}

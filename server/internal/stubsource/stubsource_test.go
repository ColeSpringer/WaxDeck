package stubsource

import (
	"bytes"
	"context"
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

package providers

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/colespringer/waxbin/enrich"
)

func TestDiscogsAnswersGenresAndCoverUnderTheNameGate(t *testing.T) {
	t.Parallel()
	data := testPNG(t)
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/database/search":
			// The header, never the query string: a token in the URL
			// would ride into logged transport errors.
			if got := r.Header.Get("Authorization"); got != "Discogs token=dg-token" {
				t.Errorf("Authorization = %q", got)
			}
			if got := r.URL.Query().Get("token"); got != "" {
				t.Errorf("token rode the query string: %q", got)
			}
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"results":[
				{"title":"Daft Punk - Discovery Live Bootleg","cover_image":"https://%s/wrong.png",
					"genre":["Electronic"],"style":["House"]},
				{"title":"daft  punk - Discovery","cover_image":"https://%s/cover.png",
					"genre":["Electronic"],"style":["House","French House"]}]}`, r.Host, r.Host)
		case "/cover.png":
			w.Header().Set("Content-Type", "image/png")
			w.Write(data)
		case "/wrong.png":
			t.Error("the near-miss hit's picture was fetched")
			w.WriteHeader(http.StatusNotFound)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()
	d := NewDiscogs(DiscogsConfig{
		BaseURL: srv.URL, Token: "dg-token", HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})

	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetReleaseGroup, Title: "Discovery", Artist: "Daft Punk",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || cand.Cover == nil {
		t.Fatalf("candidate = %+v, want the matched master's cover", cand)
	}
	want := []string{"Electronic", "House", "French House"}
	if len(cand.Genres) != len(want) {
		t.Fatalf("genres = %v, want genre then styles", cand.Genres)
	}
	for i, g := range want {
		if cand.Genres[i] != g {
			t.Errorf("genres[%d] = %q, want %q", i, cand.Genres[i], g)
		}
	}
}

// TestDiscogsScopedGenresAskSkipsTheImage: the genre want reads only
// cand.Genres, so a scoped ask must not download the cover it would
// discard - on a genre-less library that is one cover-sized fetch per
// item saved.
func TestDiscogsScopedGenresAskSkipsTheImage(t *testing.T) {
	t.Parallel()
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/database/search":
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"results":[
				{"title":"Daft Punk - Discovery","cover_image":"https://%s/cover.png",
					"genre":["Electronic"],"style":["House"]}]}`, r.Host)
		case "/cover.png":
			t.Error("a genres-scoped ask fetched the cover image")
			w.WriteHeader(http.StatusNotFound)
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()
	d := NewDiscogs(DiscogsConfig{
		BaseURL: srv.URL, Token: "dg-token", HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})

	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetReleaseGroup, Title: "Discovery", Artist: "Daft Punk",
		Want: enrich.CapGenres,
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || len(cand.Genres) != 2 {
		t.Fatalf("scoped candidate = %+v, want the genres", cand)
	}
	if cand.Cover != nil {
		t.Error("a genres-scoped candidate carries a cover")
	}
}

func TestDiscogsWithoutATokenIsSilent(t *testing.T) {
	t.Parallel()
	d := NewDiscogs(DiscogsConfig{BaseURL: "https://never-dialed.invalid"})
	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetReleaseGroup, Title: "Discovery",
	})
	if cand != nil || err != nil {
		t.Errorf("tokenless Enrich = %+v, %v; want a silent miss", cand, err)
	}
}

// TestDiscogsKeepsGenresWhenTheImageFails pins two things at once: the
// (N) disambiguator Discogs appends to same-named artists does not cost
// the match, and an unreachable cover_image does not cost the matched
// genres - the genre want reads only those, and Discogs is the one
// provider that had them.
func TestDiscogsKeepsGenresWhenTheImageFails(t *testing.T) {
	t.Parallel()
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/database/search":
			w.Header().Set("Content-Type", "application/json")
			fmt.Fprintf(w, `{"results":[
				{"title":"Nirvana (2) - Nevermind","cover_image":"https://%s/gone.png",
					"genre":["Rock"],"style":["Grunge"]}]}`, r.Host)
		default:
			// The image host refuses, as Discogs hotlinks routinely do.
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	defer srv.Close()
	d := NewDiscogs(DiscogsConfig{
		BaseURL: srv.URL, Token: "dg-token", HTTPClient: srv.Client(), MinInterval: time.Nanosecond,
	})

	cand, err := d.Enrich(context.Background(), enrich.Request{
		Type: enrich.TargetReleaseGroup, Title: "Nevermind", Artist: "Nirvana",
	})
	if err != nil {
		t.Fatal(err)
	}
	if cand == nil || len(cand.Genres) != 2 {
		t.Fatalf("candidate = %+v, want the genres despite the dead image", cand)
	}
	if cand.Cover != nil {
		t.Errorf("candidate carries a cover from a failed fetch")
	}
}

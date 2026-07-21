package providers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"sync/atomic"
	"testing"
	"time"
)

const mbHomeworkJSON = `{
  "id": "rel-1",
  "title": "Homework",
  "date": "1997-01-20",
  "country": "FR",
  "barcode": "724384260921",
  "artist-credit": [{"name": "Daft Punk", "joinphrase": ""}],
  "release-group": {"id": "rg-1", "first-release-date": "1997-01-17", "secondary-types": []},
  "label-info": [{"catalog-number": "V-42609", "label": {"name": "Virgin"}}],
  "media": [
    {"tracks": [
      {"position": 1, "title": "Daftendirekt", "length": 164000,
       "recording": {"id": "rec-1", "length": 163000},
       "artist-credit": [{"name": "Daft Punk", "joinphrase": ""}]},
      {"position": 2, "title": "WDPK 83.7 FM", "length": null,
       "recording": {"id": "rec-2", "length": 28000},
       "artist-credit": [{"name": "Daft Punk", "joinphrase": ""}]}
    ]},
    {"tracks": [
      {"position": 1, "title": "Music Sounds Better", "length": 200000,
       "recording": {"id": "rec-3", "length": 200000},
       "artist-credit": [{"name": "Stardust", "joinphrase": ""}]}
    ]}
  ]
}`

const mbCompilationJSON = `{
  "id": "rel-va",
  "title": "Big Hits 2001",
  "date": "",
  "artist-credit": [{"name": "Various Artists", "joinphrase": ""}],
  "release-group": {"id": "rg-va", "first-release-date": "2001-05-01", "secondary-types": ["Compilation"]},
  "media": [
    {"tracks": [
      {"position": 1, "title": "Song A", "length": 100000,
       "recording": {"id": "rec-a", "length": 100000},
       "artist-credit": [{"name": "Artist A", "joinphrase": ""}]}
    ]}
  ]
}`

// newMBServer routes the release lookup and search endpoints over canned
// fixtures and counts requests per path prefix.
func newMBServer(t *testing.T, searchJSON string, lookupCount, searchCount *atomic.Int64) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		switch r.URL.Path {
		case "/release/rel-1":
			lookupCount.Add(1)
			w.Write([]byte(mbHomeworkJSON))
		case "/release/rel-va":
			lookupCount.Add(1)
			w.Write([]byte(mbCompilationJSON))
		case "/release":
			searchCount.Add(1)
			w.Write([]byte(searchJSON))
		default:
			lookupCount.Add(1)
			w.WriteHeader(http.StatusNotFound)
			w.Write([]byte(`{"error": "Not Found"}`))
		}
	}))
}

func testMB(srv *httptest.Server, interval time.Duration) *MusicBrainz {
	return NewMusicBrainz(MusicBrainzConfig{
		BaseURL:     srv.URL,
		HTTPClient:  srv.Client(),
		MinInterval: interval,
	})
}

func TestMusicBrainzReleaseByMBIDMapping(t *testing.T) {
	var lookups, searches atomic.Int64
	srv := newMBServer(t, `{"releases": []}`, &lookups, &searches)
	defer srv.Close()

	rel, err := testMB(srv, time.Nanosecond).ReleaseByMBID(context.Background(), "rel-1")
	if err != nil {
		t.Fatal(err)
	}
	if rel == nil {
		t.Fatal("nil release")
	}
	if rel.MBID != "rel-1" || rel.Title != "Homework" || rel.Artist != "Daft Punk" {
		t.Fatalf("identity fields wrong: %+v", rel)
	}
	if rel.ReleaseGroupMBID != "rg-1" {
		t.Fatalf("ReleaseGroupMBID = %q, want rg-1", rel.ReleaseGroupMBID)
	}
	if rel.Year != 1997 {
		t.Fatalf("Year = %d, want 1997", rel.Year)
	}
	if rel.Media != 2 {
		t.Fatalf("Media = %d, want 2", rel.Media)
	}
	if rel.Country != "FR" || rel.Barcode != "724384260921" {
		t.Fatalf("edition fields wrong: %+v", rel)
	}
	if rel.Label != "Virgin" || rel.CatalogNumber != "V-42609" {
		t.Fatalf("label fields wrong: Label=%q CatalogNumber=%q", rel.Label, rel.CatalogNumber)
	}
	if rel.Compilation {
		t.Fatal("Compilation = true, want false")
	}
	if len(rel.Tracks) != 3 {
		t.Fatalf("len(Tracks) = %d, want 3", len(rel.Tracks))
	}
	t0 := rel.Tracks[0]
	if t0.Disc != 1 || t0.Position != 1 || t0.Title != "Daftendirekt" || t0.RecordingMBID != "rec-1" {
		t.Fatalf("track 0 wrong: %+v", t0)
	}
	if t0.DurationSec != 164 {
		t.Fatalf("track 0 DurationSec = %v, want 164 (track length preferred)", t0.DurationSec)
	}
	if t0.Artist != "" {
		t.Fatalf("track 0 Artist = %q, want empty (same as release artist)", t0.Artist)
	}
	if rel.Tracks[1].DurationSec != 28 {
		t.Fatalf("track 1 DurationSec = %v, want 28 (recording length fallback)", rel.Tracks[1].DurationSec)
	}
	t2 := rel.Tracks[2]
	if t2.Disc != 2 || t2.Position != 1 {
		t.Fatalf("track 2 disc/position wrong: %+v", t2)
	}
	if t2.Artist != "Stardust" {
		t.Fatalf("track 2 Artist = %q, want Stardust (differs from release artist)", t2.Artist)
	}
}

func TestMusicBrainzCompilationDetection(t *testing.T) {
	var lookups, searches atomic.Int64
	srv := newMBServer(t, `{"releases": []}`, &lookups, &searches)
	defer srv.Close()

	rel, err := testMB(srv, time.Nanosecond).ReleaseByMBID(context.Background(), "rel-va")
	if err != nil {
		t.Fatal(err)
	}
	if !rel.Compilation {
		t.Fatal("Compilation = false, want true")
	}
	if rel.Year != 2001 {
		t.Fatalf("Year = %d, want 2001 (release-group first-release-date fallback)", rel.Year)
	}
	if rel.Tracks[0].Artist != "Artist A" {
		t.Fatalf("track Artist = %q, want Artist A", rel.Tracks[0].Artist)
	}
}

func TestMusicBrainzReleaseByMBIDNotFound(t *testing.T) {
	var lookups, searches atomic.Int64
	srv := newMBServer(t, `{"releases": []}`, &lookups, &searches)
	defer srv.Close()

	rel, err := testMB(srv, time.Nanosecond).ReleaseByMBID(context.Background(), "rel-missing")
	if err != nil {
		t.Fatalf("404 must be a clean miss, got %v", err)
	}
	if rel != nil {
		t.Fatalf("want nil release, got %+v", rel)
	}
}

func TestMusicBrainzReleasesByGroup(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/release" {
			t.Errorf("path = %q, want /release", r.URL.Path)
		}
		if got := r.URL.Query().Get("release-group"); got != "rg-1" {
			t.Errorf("release-group = %q, want rg-1", got)
		}
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"releases": [` + mbHomeworkJSON + `]}`))
	}))
	defer srv.Close()

	rels, err := testMB(srv, time.Nanosecond).ReleasesByGroup(context.Background(), "rg-1")
	if err != nil {
		t.Fatal(err)
	}
	if len(rels) != 1 {
		t.Fatalf("len = %d, want 1", len(rels))
	}
	if rels[0].ReleaseGroupMBID != "rg-1" {
		t.Fatalf("ReleaseGroupMBID = %q, want rg-1 (from the requested group)", rels[0].ReleaseGroupMBID)
	}
	if len(rels[0].Tracks) != 3 {
		t.Fatalf("len(Tracks) = %d, want 3 (browse includes recordings)", len(rels[0].Tracks))
	}
}

func TestMusicBrainzSearchHydratesTracklists(t *testing.T) {
	var lookups, searches atomic.Int64
	// The search result carries ids only, no recordings; one id 404s and
	// must be skipped.
	srv := newMBServer(t, `{"releases": [{"id": "rel-1"}, {"id": "rel-gone"}]}`, &lookups, &searches)
	defer srv.Close()

	rels, err := testMB(srv, time.Nanosecond).SearchReleases(context.Background(), "Daft Punk", "Homework", 16)
	if err != nil {
		t.Fatal(err)
	}
	if searches.Load() != 1 {
		t.Fatalf("search requests = %d, want 1", searches.Load())
	}
	if lookups.Load() != 2 {
		t.Fatalf("lookup requests = %d, want 2 (one per search hit)", lookups.Load())
	}
	if len(rels) != 1 {
		t.Fatalf("len = %d, want 1 (404 hit skipped)", len(rels))
	}
	if len(rels[0].Tracks) != 3 {
		t.Fatalf("len(Tracks) = %d, want 3 (hydrated by release lookup)", len(rels[0].Tracks))
	}
}

func TestMusicBrainzSearchLuceneEscaping(t *testing.T) {
	var gotQuery atomic.Value
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotQuery.Store(r.URL.Query().Get("query"))
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"releases": []}`))
	}))
	defer srv.Close()

	_, err := testMB(srv, time.Nanosecond).SearchReleases(context.Background(), `AC/DC`, `Best "Of": Volume\1`, 10)
	if err != nil {
		t.Fatal(err)
	}
	want := `release:"Best \"Of\": Volume\\1" AND artist:"AC/DC"`
	if got, _ := gotQuery.Load().(string); got != want {
		t.Fatalf("query = %q, want %q", got, want)
	}
}

func TestMusicBrainzSearchOmitsEmptyArtist(t *testing.T) {
	var gotQuery atomic.Value
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotQuery.Store(r.URL.Query().Get("query"))
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"releases": []}`))
	}))
	defer srv.Close()

	if _, err := testMB(srv, time.Nanosecond).SearchReleases(context.Background(), "", "Homework", 0); err != nil {
		t.Fatal(err)
	}
	if got, _ := gotQuery.Load().(string); got != `release:"Homework"` {
		t.Fatalf("query = %q, want release clause only", got)
	}
}

func TestMusicBrainzSearchBadRequestIsCleanMiss(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
	}))
	defer srv.Close()

	rels, err := testMB(srv, time.Nanosecond).SearchReleases(context.Background(), "a", "b", 0)
	if err != nil {
		t.Fatalf("400 must be a clean miss, got %v", err)
	}
	if rels != nil {
		t.Fatalf("want no releases, got %d", len(rels))
	}
}

func TestMusicBrainzPacing(t *testing.T) {
	var lookups, searches atomic.Int64
	srv := newMBServer(t, `{"releases": []}`, &lookups, &searches)
	defer srv.Close()

	mb := testMB(srv, 50*time.Millisecond)
	start := time.Now()
	if _, err := mb.ReleaseByMBID(context.Background(), "rel-1"); err != nil {
		t.Fatal(err)
	}
	if _, err := mb.ReleaseByMBID(context.Background(), "rel-va"); err != nil {
		t.Fatal(err)
	}
	if elapsed := time.Since(start); elapsed < 50*time.Millisecond {
		t.Fatalf("two paced calls took %v, want >= 50ms", elapsed)
	}
}

func TestMusicBrainzCaching(t *testing.T) {
	var lookups, searches atomic.Int64
	srv := newMBServer(t, `{"releases": []}`, &lookups, &searches)
	defer srv.Close()

	mb := testMB(srv, time.Nanosecond)
	first, err := mb.ReleaseByMBID(context.Background(), "rel-1")
	if err != nil {
		t.Fatal(err)
	}
	second, err := mb.ReleaseByMBID(context.Background(), "rel-1")
	if err != nil {
		t.Fatal(err)
	}
	if lookups.Load() != 1 {
		t.Fatalf("server requests = %d, want 1 (second call served from cache)", lookups.Load())
	}
	if first.Title != second.Title || len(first.Tracks) != len(second.Tracks) {
		t.Fatal("cached response decoded differently")
	}
}

func TestMusicBrainzFingerprintUnsupported(t *testing.T) {
	mb := NewMusicBrainz(MusicBrainzConfig{})
	if _, err := mb.LookupFingerprint(context.Background(), matchFingerprint()); err == nil {
		t.Fatal("want error: bare MusicBrainz must not claim fingerprint lookup")
	}
}

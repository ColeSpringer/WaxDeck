package providers

import (
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
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
		if inc := r.URL.Query().Get("inc"); !strings.Contains(inc, "release-groups") {
			t.Errorf("inc = %q, want release-groups included (secondary types carry Compilation)", inc)
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

// TestMusicBrainzBrowseMarksTypedCompilation: an artist-credited
// compilation carries no "Various Artists" credit, so only the release
// group's secondary types can mark it.
func TestMusicBrainzBrowseMarksTypedCompilation(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"releases": [{
			"id": "rel-hits",
			"title": "The Essential",
			"artist-credit": [{"name": "Artist A"}],
			"release-group": {"id": "rg-1", "secondary-types": ["Compilation"]},
			"media": [{"tracks": [{"title": "One", "position": 1, "length": 180000, "recording": {"id": "rec-1"}}]}]
		}]}`))
	}))
	defer srv.Close()

	rels, err := testMB(srv, time.Nanosecond).ReleasesByGroup(context.Background(), "rg-1")
	if err != nil {
		t.Fatal(err)
	}
	if len(rels) != 1 || !rels[0].Compilation {
		t.Fatalf("typed compilation must browse in marked, got %+v", rels)
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

// mbRecordingSearchBody is a real recording-search response, captured
// verbatim: `recording:"Take On Me" AND artist:"a-ha"`, limit 3,
// 2026-08-17. Real because the shape is the whole question - the ranking
// below is only affordable if the search index embeds each release's
// group inline, which it does, types included.
//
// It is also the reported bug in one body. The first recording's release
// list opens with two compilations, then the single, then another
// compilation; the album is fifth. Walking that order and stopping at
// four asked the archive about three greatest-hits sleeves and never
// reached "Hunting High and Low".
func mbRecordingSearchBody(t *testing.T) []byte {
	t.Helper()
	body, err := os.ReadFile(filepath.Join("testdata", "musicbrainz-recording-search.json"))
	if err != nil {
		t.Fatal(err)
	}
	return body
}

func TestMusicBrainzCoverReleasesPreferTheAlbum(t *testing.T) {
	t.Parallel()
	var gotQuery, gotLimit atomic.Value
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/recording" {
			t.Errorf("path = %q, want /recording", r.URL.Path)
		}
		gotQuery.Store(r.URL.Query().Get("query"))
		gotLimit.Store(r.URL.Query().Get("limit"))
		w.Header().Set("Content-Type", "application/json")
		w.Write(mbRecordingSearchBody(t))
	}))
	defer srv.Close()

	ids, err := testMB(srv, time.Nanosecond).
		ReleaseMBIDsForRecording(context.Background(), "a-ha", "Take On Me")
	if err != nil {
		t.Fatal(err)
	}
	if got, _ := gotQuery.Load().(string); got != `recording:"Take On Me" AND artist:"a-ha"` {
		t.Fatalf("query = %q", got)
	}
	// The four "Hunting High and Low" releases, then the two "Take On Me"
	// singles. Every compilation the index ranked ahead of them is behind
	// them, and the album the old walk never reached is asked first.
	want := []string{
		"6d617149-023d-48b7-bf31-abbec68569b0",
		"201d7200-630d-480d-b06e-fe60fa12bea5",
		"efb13cf9-7bd2-418e-be2b-b1906c77f955",
		"7278957c-d2db-45ac-8950-8f07663a79a1",
		"a26f933f-7fce-4117-aea7-b9644a3dda61",
		"13815348-ea05-49a5-8ab3-599e062d4493",
	}
	if !slices.Equal(ids, want) {
		t.Fatalf("release order =\n %q\nwant\n %q", ids, want)
	}
}

// The ranking is by kind, and the search order breaks ties - so between
// two releases of the same kind the better-matching recording still
// wins, which is the only ordering signal the index gives.
func TestMusicBrainzCoverReleaseRanking(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		rg   *mbReleaseGroup
		want int
	}{
		{"an album", &mbReleaseGroup{PrimaryType: "Album"}, 0},
		{"a single", &mbReleaseGroup{PrimaryType: "Single"}, 1},
		{"an EP ranks with the rest", &mbReleaseGroup{PrimaryType: "EP"}, 2},
		{"no group at all", nil, 2},
		{
			"a compilation album is behind every album",
			&mbReleaseGroup{PrimaryType: "Album", SecondaryTypes: []string{"Compilation"}},
			3,
		},
		{
			// Ranked, not dropped: a release with a cover is still a cover.
			"a live compilation is still reachable",
			&mbReleaseGroup{PrimaryType: "Other", SecondaryTypes: []string{"Live", "Compilation"}},
			5,
		},
		{"casing is the server's to choose", &mbReleaseGroup{PrimaryType: "album"}, 0},
	}
	for _, tc := range cases {
		if got := coverReleaseRank(tc.rg); got != tc.want {
			t.Errorf("%s: rank = %d, want %d", tc.name, got, tc.want)
		}
	}
}

// The ranking sees the whole body, not a prefix of it. A song on dozens
// of compilations would otherwise fill any cut with them and leave the
// album behind it unranked - the original bug, dropped by exactly the
// ordering this exists to distrust.
func TestMusicBrainzCoverReleasesRankTheWholeBody(t *testing.T) {
	t.Parallel()
	var body strings.Builder
	body.WriteString(`{"recordings": [{"releases": [`)
	for i := range 60 {
		if i > 0 {
			body.WriteString(",")
		}
		fmt.Fprintf(&body, `{"id": "comp-%d", "release-group": `+
			`{"primary-type": "Album", "secondary-types": ["Compilation"]}}`, i)
	}
	body.WriteString(`,{"id": "the-album", "release-group": {"primary-type": "Album"}}`)
	body.WriteString(`]}]}`)

	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(body.String()))
	}))
	defer srv.Close()

	ids, err := testMB(srv, time.Nanosecond).
		ReleaseMBIDsForRecording(context.Background(), "Artist", "Song")
	if err != nil {
		t.Fatal(err)
	}
	if len(ids) != maxCoverReleases {
		t.Fatalf("len(ids) = %d, want the walk's cap %d", len(ids), maxCoverReleases)
	}
	if ids[0] != "the-album" {
		t.Fatalf("ids[0] = %q, want the album from the far end of the body", ids[0])
	}
}

// The ranking crosses recordings on purpose. A title-and-artist search
// returns the same artist performing the same song several times over
// (every probe of the real service does), and the album is routinely on
// a later hit than the compilations - so ranking each recording's
// releases separately would leave the reported bug half fixed.
//
// The cost is the case this pins in reverse: search order breaks ties,
// so a later recording wins only against a worse *kind* of release,
// never against an equal one.
func TestMusicBrainzCoverReleasesRankAcrossRecordings(t *testing.T) {
	t.Parallel()
	body := `{"recordings": [
	  {"releases": [
	    {"id": "hit1-comp", "release-group": {"primary-type": "Album", "secondary-types": ["Compilation"]}},
	    {"id": "hit1-album", "release-group": {"primary-type": "Album"}}
	  ]},
	  {"releases": [
	    {"id": "hit2-album", "release-group": {"primary-type": "Album"}},
	    {"id": "hit2-single", "release-group": {"primary-type": "Single"}}
	  ]}
	]}`
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(body))
	}))
	defer srv.Close()

	ids, err := testMB(srv, time.Nanosecond).
		ReleaseMBIDsForRecording(context.Background(), "Artist", "Song")
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"hit1-album", "hit2-album", "hit2-single", "hit1-comp"}
	if !slices.Equal(ids, want) {
		t.Fatalf("release order =\n %q\nwant\n %q", ids, want)
	}
}

func TestMusicBrainzCoverReleasesCleanMiss(t *testing.T) {
	t.Parallel()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Write([]byte(`{"recordings": []}`))
	}))
	defer srv.Close()

	mb := testMB(srv, time.Nanosecond)
	ids, err := mb.ReleaseMBIDsForRecording(context.Background(), "Nobody", "Nothing")
	if err != nil || len(ids) != 0 {
		t.Fatalf("empty search = (%q, %v), want no ids and no error", ids, err)
	}
	// A title with nothing in it is not worth a request at all.
	if ids, err := mb.ReleaseMBIDsForRecording(context.Background(), "Artist", "  "); err != nil || ids != nil {
		t.Fatalf("blank title = (%q, %v), want nothing", ids, err)
	}
}

func TestMusicBrainzFingerprintUnsupported(t *testing.T) {
	mb := NewMusicBrainz(MusicBrainzConfig{})
	if _, err := mb.LookupFingerprint(context.Background(), matchFingerprint()); err == nil {
		t.Fatal("want error: bare MusicBrainz must not claim fingerprint lookup")
	}
}

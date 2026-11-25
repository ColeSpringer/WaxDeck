package providers

import (
	"bytes"
	"context"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
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

// A recording search keeps releases from several recordings, not the first
// five of the lead hit: a popular song's lead recording sits on dozens of
// releases, and a candidate list that never names another recording cannot
// tell the song from a near namesake. The request count stays one search plus
// one lookup per kept release.
func TestMusicBrainzRecordingSearchSpansRecordings(t *testing.T) {
	t.Parallel()
	var searches, lookups atomic.Int64
	var gotLimit atomic.Value
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/recording" {
			searches.Add(1)
			gotLimit.Store(r.URL.Query().Get("limit"))
			w.Write(mbRecordingSearchBody(t))
			return
		}
		lookups.Add(1)
		id := strings.TrimPrefix(r.URL.Path, "/release/")
		fmt.Fprintf(w, `{"id": %q, "title": "T", "media": [{"tracks": [{"position": 1, "title": "Take On Me", "recording": {"id": "rec"}}]}]}`, id)
	}))
	defer srv.Close()

	res, err := testMB(srv, time.Nanosecond).SearchRecordings(context.Background(), "a-ha", "Take On Me", "", "")
	if err != nil {
		t.Fatal(err)
	}
	var ids []string
	for _, r := range res.Releases {
		ids = append(ids, r.MBID[:8])
	}
	// The lead recording's two albums (ranked past the compilations the index
	// lists first), then one release of each further recording, then the lead's
	// next album.
	want := []string{"6d617149", "201d7200", "620400bc", "9e29c374", "efb13cf9"}
	if !slices.Equal(ids, want) {
		t.Fatalf("releases = %q, want %q", ids, want)
	}
	if searches.Load() != 1 || lookups.Load() != int64(len(want)) {
		t.Fatalf("requests: %d searches, %d lookups; want 1 and %d", searches.Load(), lookups.Load(), len(want))
	}
	// Every listed recording comes back from the same body, hydrated or not,
	// and the lead's untaken releases say the search was capped.
	if !res.Capped {
		t.Fatal("capped = false, want true: the lead recording lists 34 releases")
	}
	if len(res.Listed) != 3 {
		t.Fatalf("listed = %+v, want the three recordings", res.Listed)
	}
	lead, other := res.Listed[0], res.Listed[1]
	if lead.MBID != "41a84b8b-5bc7-4266-82f5-4d2e6e0f84e6" || lead.Title != "Take On Me" || lead.DurationSec != 288.84 || lead.Artist != "a\u2010ha" {
		t.Fatalf("lead listed = %+v", lead)
	}
	if other.MBID != "2aa37a8b-e90f-4d6f-8075-46a0c2d21470" || other.Title != "Take on Me" || other.DurationSec != 0 {
		t.Fatalf("second listed = %+v, want no length", other)
	}
	// One request lists a full page, so the margin sees every recording the
	// page holds; the body was captured at a page of three of 95 hits, all
	// scoring 100, so it says more were counted than listed.
	if got, _ := gotLimit.Load().(string); got != "100" {
		t.Fatalf("limit = %q, want a page of 100", got)
	}
	for _, l := range res.Listed {
		if l.Score != 100 {
			t.Fatalf("listed %s score = %d, want 100", l.MBID, l.Score)
		}
	}
	if !res.Unlisted {
		t.Fatal("unlisted = false, want true: the search counted 95 hits and listed three")
	}
}

// mbSongPage is a recording search page shaped like a real one for a plain
// title: ten takes titled "Song", one release each, then the remix the upload
// names, scored below them.
func mbSongPage() string {
	var b strings.Builder
	b.WriteString(`{"count": 11, "recordings": [`)
	for i := range 10 {
		fmt.Fprintf(&b, `{"id": "plain-%d", "score": 100, "title": "Song", "length": 200000,
			"artist-credit": [{"name": "Band"}], "releases": [{"id": "p%d"}]},`, i, i)
	}
	b.WriteString(`{"id": "remix", "score": 90, "title": "Song (X remix)", "length": 240000,
		"artist-credit": [{"name": "Band"}], "releases": [{"id": "x1"}, {"id": "x2"}]}]}`)
	return b.String()
}

// The search asks for the song as a phrase, whatever the upload named, and
// hydrates the recording titled as the upload first: listed eleventh, the
// remix is past every hit the spread would otherwise reach.
func TestMusicBrainzRecordingSearchHydratesTheNamedRecording(t *testing.T) {
	t.Parallel()
	var query atomic.Value
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/recording" {
			query.Store(r.URL.Query().Get("query"))
			w.Write([]byte(mbSongPage()))
			return
		}
		id := strings.TrimPrefix(r.URL.Path, "/release/")
		fmt.Fprintf(w, `{"id": %q, "title": "T", "media": [{"tracks": [{"position": 1, "title": "Song", "recording": {"id": "rec"}}]}]}`, id)
	}))
	defer srv.Close()

	for _, c := range []struct {
		named, query string
		want         []string
	}{
		{"Song (X Remix)", `(recording:"Song" OR recording:"Song (X Remix)"^3) AND artist:"Band"`, []string{"x1", "x2", "p0", "p1", "p2"}},
		{"", `recording:"Song" AND artist:"Band"`, []string{"p0", "p1", "p2", "p3", "p4"}},
	} {
		res, err := testMB(srv, time.Nanosecond).SearchRecordings(context.Background(), "Band", "Song", c.named, "")
		if err != nil {
			t.Fatal(err)
		}
		if got, _ := query.Load().(string); got != c.query {
			t.Fatalf("named %q: query = %s, want %s", c.named, got, c.query)
		}
		var ids []string
		for _, r := range res.Releases {
			ids = append(ids, r.MBID)
		}
		if !slices.Equal(ids, c.want) {
			t.Fatalf("named %q: hydrated %q, want %q", c.named, ids, c.want)
		}
		if len(res.Listed) != 11 || res.Listed[10].Title != "Song (X remix)" || res.Listed[10].DurationSec != 240 {
			t.Fatalf("named %q: listed %+v, want all eleven", c.named, res.Listed)
		}
	}
}

// A popular song has more plain-titled recordings than a page lists, so the
// recording an upload names by a group ("Song (X Remix)") can sit past the
// page of the song's phrase. The one search asks for the title as named as
// well, boosted, so that recording ranks on the page; a search naming nothing
// more than the song sends the phrase alone. Still one search and at most
// five lookups.
func TestMusicBrainzRecordingSearchAsksForTheNamedTitleToo(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		artist, title, named, want string
	}{
		{"Band", "Song", "Song (X Remix)", `(recording:"Song" OR recording:"Song (X Remix)"^3) AND artist:"Band"`},
		{"", "Song", "Song (Live at X)", `(recording:"Song" OR recording:"Song (Live at X)"^3)`},
		{"Band", `Say "Hi"`, `Say "Hi" (Demo)`, `(recording:"Say \"Hi\"" OR recording:"Say \"Hi\" (Demo)"^3) AND artist:"Band"`},
		{"Band", `Back\Slash`, `Back\Slash (Demo)`, `(recording:"Back\\Slash" OR recording:"Back\\Slash (Demo)"^3) AND artist:"Band"`},
		{"Band", "Song", "", `recording:"Song" AND artist:"Band"`},
		{"", "Song", "", `recording:"Song"`},
	} {
		var searches, lookups atomic.Int64
		var query atomic.Value
		srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			w.Header().Set("Content-Type", "application/json")
			if r.URL.Path == "/recording" {
				searches.Add(1)
				query.Store(r.URL.Query().Get("query"))
				w.Write([]byte(mbSongPage()))
				return
			}
			lookups.Add(1)
			id := strings.TrimPrefix(r.URL.Path, "/release/")
			fmt.Fprintf(w, `{"id": %q, "title": "T", "media": [{"tracks": [{"position": 1, "title": "Song", "recording": {"id": "rec"}}]}]}`, id)
		}))
		res, err := testMB(srv, time.Nanosecond).SearchRecordings(context.Background(), c.artist, c.title, c.named, "")
		srv.Close()
		if err != nil {
			t.Fatal(err)
		}
		if got, _ := query.Load().(string); got != c.want {
			t.Errorf("(%q, %q, %q): query = %s, want %s", c.artist, c.title, c.named, got, c.want)
		}
		if searches.Load() != 1 || lookups.Load() != 5 || len(res.Releases) != 5 {
			t.Errorf("(%q, %q, %q): %d searches, %d lookups, %d releases; want 1, 5 and 5", c.artist, c.title, c.named, searches.Load(), lookups.Load(), len(res.Releases))
		}
	}
}

// A page of a hundred hits is megabytes as MusicBrainz sends it (every hit
// lists its releases in full), and the cache keeps a search for days: it
// holds the listing reduced to what is read from it, not the body.
func TestMusicBrainzRecordingSearchCachesTheReducedListing(t *testing.T) {
	t.Parallel()
	raw := mbRecordingSearchBody(t)
	var searches atomic.Int64
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/recording" {
			searches.Add(1)
			w.Write(raw)
			return
		}
		id := strings.TrimPrefix(r.URL.Path, "/release/")
		fmt.Fprintf(w, `{"id": %q, "title": "T", "media": [{"tracks": [{"position": 1, "title": "Take On Me", "recording": {"id": "rec"}}]}]}`, id)
	}))
	defer srv.Close()

	mb := testMB(srv, time.Nanosecond)
	first, err := mb.SearchRecordings(context.Background(), "a-ha", "Take On Me", "", "")
	if err != nil {
		t.Fatal(err)
	}
	var cached []byte
	for key, e := range mb.core.cache {
		if strings.Contains(key, "/recording?") {
			cached = e.body
		}
	}
	// 60 KB for three recordings on 36 releases; reduced, each recording
	// keeps its id, title, credit, length, score and the few release ids a
	// spread can reach.
	if len(cached) == 0 || len(cached) > 1024 {
		t.Fatalf("cached search entry is %d bytes of a %d byte body, want the reduced listing (under 1 KiB)", len(cached), len(raw))
	}
	if bytes.Contains(cached, []byte("release-group")) || bytes.Contains(cached, []byte("artist-credit")) {
		t.Fatalf("cached entry still holds the body's own shape: %s", cached)
	}
	second, err := mb.SearchRecordings(context.Background(), "a-ha", "Take On Me", "", "")
	if err != nil {
		t.Fatal(err)
	}
	if searches.Load() != 1 {
		t.Fatalf("searches = %d, want the second answered from the cache", searches.Load())
	}
	if !reflect.DeepEqual(first, second) {
		t.Fatalf("the cached listing answered differently:\nfirst  %+v\nsecond %+v", first, second)
	}
	if !second.Capped || !second.Unlisted || len(second.Listed) != 3 || len(second.Releases) != 5 {
		t.Fatalf("from the cache: capped %v unlisted %v listed %d releases %d", second.Capped, second.Unlisted, len(second.Listed), len(second.Releases))
	}
}

// A unit naming an album its release search found nothing for (a
// compilation, credited to Various Artists) names it to the recording
// search, which hydrates the release titled so first however far down the
// listing ranks it: compilations rank last. The listing is cached per album
// named, each keeping only what that album reads.
func TestMusicBrainzRecordingSearchHydratesTheNamedAlbumFirst(t *testing.T) {
	t.Parallel()
	var b strings.Builder
	b.WriteString(`{"count": 2, "recordings": [{"id": "lead", "score": 100, "title": "Song", "length": 200000,
		"artist-credit": [{"name": "Band"}], "releases": [`)
	for i := range 8 {
		fmt.Fprintf(&b, `{"id": "comp-%d", "title": "Comp %d", "release-group": {"primary-type": "Album", "secondary-types": ["Compilation"]}},`, i, i)
	}
	b.WriteString(`{"id": "sunset", "title": "Sunset Anthems", "release-group": {"primary-type": "Album", "secondary-types": ["Compilation"]}},
		{"id": "single", "title": "Song", "release-group": {"primary-type": "Single"}},
		{"id": "album", "title": "Album", "release-group": {"primary-type": "Album"}}]},
		{"id": "live", "score": 90, "title": "Song", "length": 260000, "artist-credit": [{"name": "Band"}],
		"releases": [{"id": "live-1", "title": "Live at X", "release-group": {"primary-type": "Album", "secondary-types": ["Live"]}}]}]}`)
	page := b.String()
	var searches atomic.Int64
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/recording" {
			searches.Add(1)
			w.Write([]byte(page))
			return
		}
		id := strings.TrimPrefix(r.URL.Path, "/release/")
		fmt.Fprintf(w, `{"id": %q, "title": "T", "media": [{"tracks": [{"position": 1, "title": "Song", "recording": {"id": "rec"}}]}]}`, id)
	}))
	defer srv.Close()

	mb := testMB(srv, time.Nanosecond)
	for _, c := range []struct {
		album string
		want  []string
	}{
		{"Sunset Anthems (Remastered)", []string{"sunset", "album", "single", "live-1", "comp-0"}},
		{"", []string{"album", "single", "live-1", "comp-0", "comp-1"}},
		{"Comp 3", []string{"comp-3", "album", "single", "live-1", "comp-0"}},
		{"Sunset Anthems", []string{"sunset", "album", "single", "live-1", "comp-0"}},
	} {
		res, err := mb.SearchRecordings(context.Background(), "Band", "Song", "", c.album)
		if err != nil {
			t.Fatal(err)
		}
		var ids []string
		for _, r := range res.Releases {
			ids = append(ids, r.MBID)
		}
		if !slices.Equal(ids, c.want) {
			t.Errorf("album %q: hydrated %q, want %q", c.album, ids, c.want)
		}
	}
	// "Sunset Anthems" and its remaster note are one album: three searches.
	if searches.Load() != 3 {
		t.Fatalf("searches = %d, want one per album named", searches.Load())
	}
}

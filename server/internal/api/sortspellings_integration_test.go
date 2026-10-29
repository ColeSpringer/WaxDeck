package api

import (
	"encoding/json"
	"io"
	"net/url"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// The summary, the detail and the search hit say what the service knows
// of an item's sort order, its totals and an exact name, and say nothing
// where it knows none.
func TestTheMappersCarryTheSortFieldsAndOmitWhatIsAbsent(t *testing.T) {
	t.Parallel()
	full := service.ItemSummary{
		PID: "tr-1", MediaType: "music", Title: "The Zebra Song", SortKey: "zebra song",
		ArtistSort: "Stripes, The", ArtistSortKey: "stripes, the",
	}
	if got := summaryJSON(full); got.SortKey == nil || *got.SortKey != "zebra song" ||
		got.ArtistSort == nil || *got.ArtistSort != "Stripes, The" ||
		got.ArtistSortKey == nil || *got.ArtistSortKey != "stripes, the" {
		t.Errorf("summary = key %v artist sort %v artist key %v, want all three", got.SortKey, got.ArtistSort, got.ArtistSortKey)
	}
	if got := summaryJSON(service.ItemSummary{PID: "tr-2", MediaType: "music", Title: "Bare"}); got.SortKey != nil ||
		got.ArtistSort != nil || got.ArtistSortKey != nil {
		t.Errorf("a summary with none = key %v artist sort %v artist key %v, want all absent", got.SortKey, got.ArtistSort, got.ArtistSortKey)
	}

	counted := itemJSON(service.ItemDetail{ItemSummary: full, TrackTotal: 12, DiscTotal: 2, PartTotal: 5})
	if counted.TrackTotal == nil || *counted.TrackTotal != 12 || counted.DiscTotal == nil || *counted.DiscTotal != 2 ||
		counted.PartTotal == nil || *counted.PartTotal != 5 {
		t.Errorf("detail totals = %v %v %v, want 12, 2 and 5", counted.TrackTotal, counted.DiscTotal, counted.PartTotal)
	}
	if counted.SortKey == nil || *counted.SortKey != "zebra song" || counted.ArtistSort == nil ||
		counted.ArtistSortKey == nil || *counted.ArtistSortKey != "stripes, the" {
		t.Errorf("detail = key %v artist sort %v artist key %v, want the summary's", counted.SortKey, counted.ArtistSort, counted.ArtistSortKey)
	}
	if bare := itemJSON(service.ItemDetail{ItemSummary: service.ItemSummary{PID: "tr-2", MediaType: "music", Title: "Bare"}}); bare.TrackTotal != nil ||
		bare.DiscTotal != nil || bare.PartTotal != nil {
		t.Errorf("detail with none = %v %v %v, want all absent", bare.TrackTotal, bare.DiscTotal, bare.PartTotal)
	}

	ep := service.EpisodeSummary{ItemSummary: service.ItemSummary{PID: "ep-1", MediaType: "podcast", Title: "The Drift 001", SortKey: "drift 0000000001"}}
	if got := episodeSummaryJSON(ep); got.SortKey == nil || *got.SortKey != "drift 0000000001" {
		t.Errorf("episode = key %v, want its title's", got.SortKey)
	}

	hits := searchHitsJSON([]service.SearchHit{
		{PID: "ar-1", Kind: "artist", Title: "Moon", Exact: true},
		{PID: "ar-2", Kind: "artist", Title: "Moonlight Band"},
	})
	if hits[0].Exact == nil || !*hits[0].Exact || hits[1].Exact != nil {
		t.Errorf("hits = %v %v, want the first exact and the second silent", hits[0].Exact, hits[1].Exact)
	}
}

// Over the wire: a listing and a detail carry the sort key, the artist's
// sort spelling and the totals a file states, and a search leads with
// the artist or album named as the query. What is absent is not sent.
func TestTheWireCarriesTheSortKeysTotalsAndExactHits(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	if _, err := fixtures.Generate(filepath.Join(h.library, "spelled"), fixtures.Spec{
		Name: "zebra", Codec: fixtures.CodecFLAC, Duration: 6 * time.Second,
		Tags: map[string]string{
			"TITLE": "The Zebra Song", "ARTIST": "The Stripes", "ARTISTSORT": "Stripes, The", "ALBUM": "Savanna",
			"TRACKNUMBER": "3", "TRACKTOTAL": "12", "DISCNUMBER": "1", "DISCTOTAL": "2",
		},
	}); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	zebra, alpha := h.itemTitled(t, h.token, "The Zebra Song"), h.itemTitled(t, h.token, "Alpha Song")
	if zebra.SortKey == nil || *zebra.SortKey != "zebra song" || zebra.ArtistSort == nil || *zebra.ArtistSort != "Stripes, The" ||
		zebra.ArtistSortKey == nil || *zebra.ArtistSortKey != "stripes, the" {
		t.Errorf("zebra = key %v artist sort %v artist key %v, want %q, %q and %q",
			zebra.SortKey, zebra.ArtistSort, zebra.ArtistSortKey, "zebra song", "Stripes, The", "stripes, the")
	}
	if alpha.SortKey == nil || *alpha.SortKey != "alpha song" || alpha.ArtistSort != nil ||
		alpha.ArtistSortKey == nil || *alpha.ArtistSortKey != "fixture artist" {
		t.Errorf("alpha = key %v artist sort %v artist key %v, want its keys and no artist sort", alpha.SortKey, alpha.ArtistSort, alpha.ArtistSortKey)
	}

	raw := func(path string) map[string]any {
		t.Helper()
		resp := get(t, h.ts, path, h.token)
		defer resp.Body.Close()
		body, err := io.ReadAll(resp.Body)
		if err != nil {
			t.Fatal(err)
		}
		var out map[string]any
		if err := json.Unmarshal(body, &out); err != nil {
			t.Fatalf("%s: %v", path, err)
		}
		return out
	}
	detail := raw("/api/v1/items/" + zebra.Pid)
	if detail["trackNumber"] != float64(3) || detail["trackTotal"] != float64(12) ||
		detail["discNumber"] != float64(1) || detail["discTotal"] != float64(2) {
		t.Errorf("zebra detail = %v, want track 3 of 12 and disc 1 of 2", detail)
	}
	if _, ok := detail["partTotal"]; ok {
		t.Errorf("a track's detail names a part total: %v", detail["partTotal"])
	}
	bare := raw("/api/v1/items/" + alpha.Pid)
	for _, key := range []string{"trackTotal", "discTotal", "partTotal", "artistSort"} {
		if v, ok := bare[key]; ok {
			t.Errorf("a file stating no %s still sends %v", key, v)
		}
	}

	search := func(q string) SearchResults {
		t.Helper()
		return decode[SearchResults](t, get(t, h.ts, "/api/v1/library/search?q="+url.QueryEscape(q), h.token))
	}
	isExact := func(h SearchHit) bool { return h.Exact != nil && *h.Exact }
	res := search("fixture artist")
	if len(res.Artists) != 1 || !isExact(res.Artists[0]) {
		t.Errorf("fixture artist: artists = %+v, want the one named exactly", res.Artists)
	}
	for _, album := range res.Albums {
		if isExact(album) {
			t.Errorf("fixture artist: album %q is exact", album.Title)
		}
	}
	res = search("Fixture Album")
	if len(res.Albums) != 1 || !isExact(res.Albums[0]) {
		t.Errorf("Fixture Album: albums = %+v, want the one named exactly", res.Albums)
	}
	res = search("Fixture")
	for _, group := range [][]SearchHit{res.Artists, res.Albums, res.Tracks} {
		for _, hit := range group {
			if isExact(hit) {
				t.Errorf("Fixture: %s %q is exact for a partial name", hit.Kind, hit.Title)
			}
		}
	}
	body := raw("/api/v1/library/search?q=" + url.QueryEscape("Fixture"))
	for _, group := range []string{"artists", "albums", "tracks"} {
		for _, hit := range body[group].([]any) {
			if v, ok := hit.(map[string]any)["exact"]; ok {
				t.Errorf("Fixture: a %s hit sends exact %v when it is not", group, v)
			}
		}
	}
}

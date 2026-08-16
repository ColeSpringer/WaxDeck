package api

import (
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// facetPage reads one page of a browse dimension.
func facetPage(t *testing.T, h *harness, query string) FacetPage {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/library/facets"+query, h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("facets%s status = %d", query, resp.StatusCode)
	}
	return decode[FacetPage](t, resp)
}

// TestFacetedBrowseOverHTTP drives the two halves of the browse surface
// end to end: a dimension enumerates, and its buckets drill through
// listItems to exactly the items they counted. The demo library is one
// artist, so a second root supplies the several buckets paging needs.
func TestFacetedBrowseOverHTTP(t *testing.T) {
	t.Parallel()
	extra := t.TempDir()
	guest := func(name, title, artist string, d time.Duration) fixtures.Spec {
		return fixtures.Spec{
			Name: name, Codec: fixtures.CodecFLAC, Duration: d,
			Tags: map[string]string{"TITLE": title, "ARTIST": artist, "ALBUM": "Guest Album"},
		}
	}
	if _, err := fixtures.Generate(extra,
		guest("echo", "Echo Song", "Second Artist", 4*time.Second),
		guest("foxtrot", "Foxtrot Song", "Third Artist", 4500*time.Millisecond),
	); err != nil {
		t.Fatalf("generating the second root: %v", err)
	}
	h := newHarness(t, service.Root{Name: "guests", Path: extra})

	page := facetPage(t, h, "?dimension=artist")
	if len(page.Buckets) == 0 {
		t.Fatal("the artist dimension enumerated nothing")
	}
	if page.Dimension != "artist" {
		t.Fatalf("page dimension = %q", page.Dimension)
	}
	total := 0
	for _, b := range page.Buckets {
		total += b.Count
		got := h.items(t, "?facet=artist&facetKey="+b.Key)
		if len(got.Items) != b.Count {
			t.Fatalf("artist bucket %q counts %d but opens %d items", b.Label, b.Count, len(got.Items))
		}
		// An artist bucket is a real catalog entity, so it carries a pid a
		// client can navigate to.
		if b.EntityPid == nil || *b.EntityPid == "" {
			t.Fatalf("artist bucket %q carries no entityPid", b.Label)
		}
	}
	if total != 6 {
		t.Fatalf("the artist dimension covers %d items; the two roots hold 6", total)
	}
	if len(page.Buckets) < 2 {
		t.Fatalf("the artist dimension has %d buckets; paging needs several", len(page.Buckets))
	}

	// The demo fixtures carry no year, so every item is in the unknown
	// bucket: an empty key, and drillable.
	years := facetPage(t, h, "?dimension=year")
	if len(years.Buckets) != 1 {
		t.Fatalf("year buckets = %+v, want the single unknown bucket", years.Buckets)
	}
	unknown := years.Buckets[0]
	if unknown.Key != "" || unknown.Unknown == nil || !*unknown.Unknown {
		t.Fatalf("the year bucket is %+v, want the unknown one", unknown)
	}
	if got := h.items(t, "?facet=year&facetKey="); len(got.Items) != unknown.Count {
		t.Fatalf("the unknown year bucket counts %d but opens %d", unknown.Count, len(got.Items))
	}

	// Paging is a window over the whole enumeration; walking it one
	// bucket at a time must reproduce it exactly.
	first := facetPage(t, h, "?dimension=artist&limit=1")
	if len(first.Buckets) != 1 || first.NextCursor == nil {
		t.Fatalf("a one-bucket page = %+v with cursor %v", first.Buckets, first.NextCursor)
	}
	seen := []string{first.Buckets[0].Key}
	cursor := *first.NextCursor
	for range page.Buckets {
		next := facetPage(t, h, "?dimension=artist&limit=1&cursor="+cursor)
		seen = append(seen, next.Buckets[0].Key)
		if next.NextCursor == nil {
			break
		}
		cursor = *next.NextCursor
	}
	if len(seen) != len(page.Buckets) {
		t.Fatalf("paged %d buckets, want %d", len(seen), len(page.Buckets))
	}
	for i, b := range page.Buckets {
		if seen[i] != b.Key {
			t.Fatalf("bucket %d paged as %q, want %q", i, seen[i], b.Key)
		}
	}

	// The A-to-Z order the index screen's alphabet rail scrolls: the same
	// buckets, arranged by label, paging through the same keyset.
	byLabel := facetPage(t, h, "?dimension=artist&sort=label")
	if len(byLabel.Buckets) != len(page.Buckets) {
		t.Fatalf("label order has %d buckets, count order %d", len(byLabel.Buckets), len(page.Buckets))
	}
	for i := 1; i < len(byLabel.Buckets); i++ {
		if strings.ToLower(byLabel.Buckets[i-1].Label) > strings.ToLower(byLabel.Buckets[i].Label) {
			t.Fatalf("label order is not alphabetical: %+v", byLabel.Buckets)
		}
	}
	labelFirst := facetPage(t, h, "?dimension=artist&sort=label&limit=1")
	if labelFirst.NextCursor == nil {
		t.Fatal("a one-bucket label page carries no cursor")
	}
	labelNext := facetPage(t, h, "?dimension=artist&sort=label&limit=1&cursor="+*labelFirst.NextCursor)
	if len(labelNext.Buckets) != 1 || labelNext.Buckets[0].Key != byLabel.Buckets[1].Key {
		t.Fatalf("the second label page is %+v, want %+v", labelNext.Buckets, byLabel.Buckets[1])
	}

	// Fail-closed on both halves: an unknown dimension is a bad request
	// wherever it appears, never a silently unfiltered listing. A cursor
	// carried across the sort toggle is the same kind of error: the two
	// orders interleave differently, so honouring it would skip buckets.
	resp := get(t, h.ts, "/api/v1/library/facets?dimension=artists", h.token)
	wantStatus(t, resp, 400, "unknown dimension")
	resp = get(t, h.ts, "/api/v1/library/facets?dimension=artist&sort=popularity", h.token)
	wantStatus(t, resp, 400, "unknown sort")
	resp = get(t, h.ts, "/api/v1/library/facets?dimension=artist&cursor="+*labelFirst.NextCursor, h.token)
	wantStatus(t, resp, 400, "a label cursor under the default order")
	resp = get(t, h.ts, "/api/v1/library/items?facet=artists&facetKey=x", h.token)
	wantStatus(t, resp, 400, "unknown facet filter")
	resp = get(t, h.ts, "/api/v1/library/facets?dimension=artist&cursor=nonsense", h.token)
	wantStatus(t, resp, 400, "malformed cursor")

	// And it is an authenticated surface like every other library read.
	resp = get(t, h.ts, "/api/v1/library/facets?dimension=artist", "")
	wantStatus(t, resp, 401, "unauthenticated enumeration")
}

// TestFacetBucketsCarryRailLetters: the alphabet rail's rows come off
// the wire, because the server owns the fold that ordered the buckets
// and a client deriving its own could only agree by accident. The
// fixture labels are ASCII, so the letter is checkable against the
// label here; what it pins is that every real bucket has one, in either
// order, and that the unknown bucket does not.
func TestFacetBucketsCarryRailLetters(t *testing.T) {
	t.Parallel()
	// A second root, as the browse test does: the demo library is one
	// artist, and one bucket per query would prove nothing about a rail.
	extra := t.TempDir()
	if _, err := fixtures.Generate(extra,
		fixtures.Spec{
			Name: "echo", Codec: fixtures.CodecFLAC, Duration: 4 * time.Second,
			Tags: map[string]string{"TITLE": "Echo Song", "ARTIST": "Second Artist", "ALBUM": "Guest Album"},
		},
		fixtures.Spec{
			Name: "foxtrot", Codec: fixtures.CodecFLAC, Duration: 4500 * time.Millisecond,
			Tags: map[string]string{"TITLE": "Foxtrot Song", "ARTIST": "Third Artist", "ALBUM": "Guest Album"},
		},
	); err != nil {
		t.Fatalf("generating the second root: %v", err)
	}
	h := newHarness(t, service.Root{Name: "guests", Path: extra})

	for _, q := range []string{"?dimension=artist&sort=label", "?dimension=artist"} {
		page := facetPage(t, h, q)
		if len(page.Buckets) < 2 {
			t.Fatalf("facets%s enumerated %d buckets; a rail needs several", q, len(page.Buckets))
		}
		for _, b := range page.Buckets {
			// artist has an unknown bucket, and it carries no rail row.
			if b.Unknown != nil && *b.Unknown {
				if b.Letter != nil {
					t.Errorf("facets%s: the unknown bucket files under %q, want none", q, *b.Letter)
				}
				continue
			}
			if b.Letter == nil {
				t.Errorf("facets%s: bucket %q carries no letter", q, b.Label)
				continue
			}
			// The fixture labels are ASCII, so the row is checkable against
			// the label here; the fold's own cases are pinned in service.
			if want := strings.ToUpper(string([]rune(b.Label)[0])); *b.Letter != want {
				t.Errorf("facets%s: bucket %q files under %q, want %q", q, b.Label, *b.Letter, want)
			}
		}
	}

	// The unknown bucket has no rail row: it sorts last whatever its
	// sentinel spells, and the rail cannot seek it.
	years := facetPage(t, h, "?dimension=year")
	for _, b := range years.Buckets {
		if b.Unknown != nil && *b.Unknown && b.Letter != nil {
			t.Errorf("the unknown year bucket files under %q, want no rail row", *b.Letter)
		}
	}
}

// TestItemEntityHandlesOverHTTP checks that a list row names the same
// entities the facet dimensions do. A client groups an artist's tracks
// into albums and links each one to its own screen, and it can only do
// that if the pid on the row is the pid the bucket carries: display text
// collides, and an album title is not a location.
func TestItemEntityHandlesOverHTTP(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	byArtist := map[string]string{}
	for _, b := range facetPage(t, h, "?dimension=artist").Buckets {
		if b.EntityPid == nil {
			t.Fatalf("artist bucket %q carries no entityPid", b.Label)
		}
		byArtist[b.Label] = *b.EntityPid
	}
	byAlbum := map[string]string{}
	for _, b := range facetPage(t, h, "?dimension=album").Buckets {
		if b.EntityPid == nil {
			t.Fatalf("album bucket %q carries no entityPid", b.Label)
		}
		byAlbum[b.Label] = *b.EntityPid
	}

	page := h.items(t, "?mediaType=music")
	if len(page.Items) == 0 {
		t.Fatal("the demo library listed no music")
	}
	for _, it := range page.Items {
		if it.Artist == nil || it.ArtistPid == nil {
			t.Fatalf("item %q has artist %v and artistPid %v", it.Title, it.Artist, it.ArtistPid)
		}
		if want := byArtist[*it.Artist]; *it.ArtistPid != want {
			t.Fatalf("item %q names artist %q, the dimension names %q", it.Title, *it.ArtistPid, want)
		}
		if it.Album == nil || it.AlbumPid == nil {
			t.Fatalf("item %q has album %v and albumPid %v", it.Title, it.Album, it.AlbumPid)
		}
		if want := byAlbum[*it.Album]; *it.AlbumPid != want {
			t.Fatalf("item %q names album %q, the dimension names %q", it.Title, *it.AlbumPid, want)
		}
		// The handle drills its own bucket: the contract states a bucket
		// key is its entity pid without the type prefix, which is what
		// lets one location name the entity and filter the listing.
		key := strings.TrimPrefix(*it.AlbumPid, "al-")
		drilled := h.items(t, "?facet=album&facetKey="+key)
		found := false
		for _, member := range drilled.Items {
			found = found || member.Pid == it.Pid
		}
		if !found {
			t.Fatalf("item %q is not in the album its albumPid names", it.Title)
		}
	}
}

// TestGenreTreeAdminOverHTTP covers the vocabulary surface: reading the
// shipped default, refusing a tree that could not resolve one way,
// storing one, and clearing back to the default.
func TestGenreTreeAdminOverHTTP(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	resp := get(t, h.ts, "/api/v1/admin/genre-tree", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("genre-tree status = %d", resp.StatusCode)
	}
	shipped := decode[GenreTree](t, resp)
	if shipped.Source != "default" {
		t.Fatalf("a fresh instance reports source %q", shipped.Source)
	}
	if len(shipped.Genres) < 50 {
		t.Fatalf("the shipped tree holds %d genres; it is meant to be broad", len(shipped.Genres))
	}

	resp = h.putJSON(t, "/api/v1/admin/genre-tree", map[string]any{
		"genres": []map[string]any{
			{"name": "Hip Hop", "aliases": []string{"Rap"}},
			{"name": "Grime", "aliases": []string{"rap"}},
		},
	})
	wantStatus(t, resp, 400, "an alias claimed by two genres")

	resp = h.putJSON(t, "/api/v1/admin/genre-tree", map[string]any{
		"genres": []map[string]any{
			{"name": "Metal"},
			{"name": "Thrash Metal", "parent": "Metal", "aliases": []string{"Thrash"}},
		},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("storing a vocabulary = %d", resp.StatusCode)
	}
	stored := decode[GenreTree](t, resp)
	if stored.Source != "custom" || len(stored.Genres) != 2 {
		t.Fatalf("stored tree = %+v", stored)
	}

	resp = h.putJSON(t, "/api/v1/admin/genre-tree", map[string]any{"genres": []map[string]any{}})
	if resp.StatusCode != 200 {
		t.Fatalf("clearing = %d", resp.StatusCode)
	}
	if back := decode[GenreTree](t, resp); back.Source != "default" || len(back.Genres) != len(shipped.Genres) {
		t.Fatalf("clearing left %s with %d genres, want the shipped %d",
			back.Source, len(back.Genres), len(shipped.Genres))
	}

	// A full pass queues as a tool task rather than running inline.
	resp = h.postJSON(t, "/api/v1/admin/genre-normalize", map[string]any{"dryRun": true})
	if resp.StatusCode != 202 {
		t.Fatalf("genre-normalize status = %d, want 202", resp.StatusCode)
	}
	if task := decode[ToolTask](t, resp); task.Type != "genre-normalize" {
		t.Fatalf("queued task type = %q", task.Type)
	}

	// The vocabulary is server configuration, so it is administrators
	// only on every verb.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "listener", "password": "long-enough-pw",
	})
	wantStatus(t, resp, 201, "create non-admin user")
	userToken := loginAs(t, h.ts, "listener", "long-enough-pw").Token
	wantStatus(t, get(t, h.ts, "/api/v1/admin/genre-tree", userToken), 403, "non-admin read")
	wantStatus(t, reqAs(t, h, "PUT", "/api/v1/admin/genre-tree", userToken,
		map[string]any{"genres": []map[string]any{}}), 403, "non-admin write")
	wantStatus(t, reqAs(t, h, "POST", "/api/v1/admin/genre-normalize", userToken,
		map[string]any{}), 403, "non-admin normalize")
}

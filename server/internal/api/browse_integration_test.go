package api

import (
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

	// Fail-closed on both halves: an unknown dimension is a bad request
	// wherever it appears, never a silently unfiltered listing.
	resp := get(t, h.ts, "/api/v1/library/facets?dimension=artists", h.token)
	wantStatus(t, resp, 400, "unknown dimension")
	resp = get(t, h.ts, "/api/v1/library/items?facet=artists&facetKey=x", h.token)
	wantStatus(t, resp, 400, "unknown facet filter")
	resp = get(t, h.ts, "/api/v1/library/facets?dimension=artist&cursor=nonsense", h.token)
	wantStatus(t, resp, 400, "malformed cursor")

	// And it is an authenticated surface like every other library read.
	resp = get(t, h.ts, "/api/v1/library/facets?dimension=artist", "")
	wantStatus(t, resp, 401, "unauthenticated enumeration")
}

// TestGenreTreeAdminOverHTTP covers the vocabulary surface: reading the
// shipped default, refusing a tree that could not resolve one way,
// storing one, and clearing back to the default.
func TestGenreTreeAdminOverHTTP(t *testing.T) {
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

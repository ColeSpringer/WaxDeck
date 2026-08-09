package api

import (
	"context"
	"fmt"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// TestTrashedItemsLeaveTheListings is ADR-0048's regression: deleting to
// trash archives an item, and a listing never offers an archived one.
//
// Polled rather than read once, because deleting is a catalog write the
// listing reads back through the change feed, and the bug this replaces
// was reproduced by polling for twenty seconds and never seeing the item
// go. The facet count comes with it: a bucket whose drill and count
// disagree is the failure TestFacetDimensionsDrillToTheirCount exists
// for, and archiving is a new way to reach it.
func TestTrashedItemsLeaveTheListings(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	page := h.items(t, "?mediaType=music")
	if len(page.Items) < 2 {
		t.Fatalf("need at least 2 items, have %d", len(page.Items))
	}
	doomed := page.Items[0]

	// The bucket the item sits in, so its count can be watched across the
	// delete. Read before, because after the delete the dimension may not
	// enumerate the bucket at all.
	before := facetCountFor(t, h, "artist", deref(doomed.Artist))
	if before == 0 {
		t.Fatalf("no artist bucket for %q before the delete", deref(doomed.Artist))
	}

	resp := h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{doomed.Pid}, "mode": "trash",
	})
	wantStatus(t, resp, 200, "delete to trash")

	deadline := time.Now().Add(30 * time.Second)
	for {
		listed := false
		for _, it := range h.items(t, "?mediaType=music").Items {
			if it.Pid == doomed.Pid {
				listed = true
			}
		}
		if !listed && facetCountFor(t, h, "artist", deref(doomed.Artist)) == before-1 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("trashed item %s still listed=%v, artist count %d (was %d)",
				doomed.Pid, listed, facetCountFor(t, h, "artist", deref(doomed.Artist)), before)
		}
		time.Sleep(100 * time.Millisecond)
	}

	// Browse answers the same, and it is a different query path: items
	// pages through QueryPage, browse through the catalog's discovery
	// lists with the filter pushed in.
	resp = get(t, h.ts, "/api/v1/library/browse?list=alphabetical&mediaType=music", h.token)
	for _, it := range decode[ItemPage](t, resp).Items {
		if it.Pid == doomed.Pid {
			t.Errorf("trashed item %s is still in the alphabetical browse", doomed.Pid)
		}
	}

	// Search too, which cannot push a predicate into FTS and filters its
	// hits afterwards instead.
	resp = get(t, h.ts, "/api/v1/library/search?q="+url.QueryEscape(doomed.Title), h.token)
	for _, hit := range decode[SearchResults](t, resp).Tracks {
		if hit.Pid == doomed.Pid {
			t.Errorf("trashed item %s is still a search hit", doomed.Pid)
		}
	}

	// The trash is where it does still answer, and restoring puts it back
	// in the listing by the ordinary scan path.
	entries := decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries
	if len(entries) != 1 {
		t.Fatalf("trash entries = %d, want 1", len(entries))
	}
	resp = h.postJSON(t, "/api/v1/admin/trash/"+entries[0].Id+"/restore", nil)
	wantStatus(t, resp, 204, "restore")

	deadline = time.Now().Add(30 * time.Second)
	for {
		for _, it := range h.items(t, "?mediaType=music").Items {
			if it.Pid == doomed.Pid {
				return
			}
		}
		if time.Now().After(deadline) {
			t.Fatalf("restored item %s never came back to the listing", doomed.Pid)
		}
		time.Sleep(100 * time.Millisecond)
	}
}

// facetCountFor answers one artist bucket's count, or 0 when the
// dimension no longer enumerates it.
func facetCountFor(t *testing.T, h *harness, dimension, label string) int {
	t.Helper()
	page := facetPage(t, h, "?dimension="+dimension+"&limit=200")
	for _, b := range page.Buckets {
		if b.Label == label {
			return b.Count
		}
	}
	return 0
}

// TestTrashRetentionAndPurge covers the age-based trash retention surface:
// the retention-days setting round-trips, the periodic sweep applies the
// age filter (recent entries survive) and refuses to empty everything when
// disabled, and a single entry purges through the new endpoint.
func TestTrashRetentionAndPurge(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	ctx := context.Background()

	// The retention setting defaults to off and round-trips through PUT.
	resp := get(t, h.ts, "/api/v1/admin/settings", h.token)
	st := decode[AdminSettings](t, resp)
	if st.TrashRetentionDays == nil || *st.TrashRetentionDays != 0 {
		t.Fatalf("default trashRetentionDays = %v, want 0", st.TrashRetentionDays)
	}
	resp = h.putJSON(t, "/api/v1/admin/settings", map[string]any{
		"signupEnabled":      st.SignupEnabled,
		"readOnly":           st.ReadOnly,
		"backupKeepCount":    st.BackupKeepCount,
		"backupKeepBytes":    st.BackupKeepBytes,
		"trashRetentionDays": 30,
	})
	if resp.StatusCode != 200 {
		t.Fatalf("put settings status = %d, want 200", resp.StatusCode)
	}
	if got := decode[AdminSettings](t, resp).TrashRetentionDays; got == nil || *got != 30 {
		t.Fatalf("saved trashRetentionDays = %v, want 30", got)
	}

	// A window large enough to overflow the day-to-duration conversion is
	// rejected, rather than silently disabling (or over-running) the sweep.
	resp = h.putJSON(t, "/api/v1/admin/settings", map[string]any{
		"signupEnabled":      st.SignupEnabled,
		"readOnly":           st.ReadOnly,
		"backupKeepCount":    st.BackupKeepCount,
		"backupKeepBytes":    st.BackupKeepBytes,
		"trashRetentionDays": 200000,
	})
	wantStatus(t, resp, 400, "overflow retention rejected")

	// Delete two items to the trash so the journal has entries to work on.
	page := h.items(t, "")
	if len(page.Items) < 2 {
		t.Fatalf("need at least 2 items, have %d", len(page.Items))
	}
	resp = h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{page.Items[0].Pid, page.Items[1].Pid}, "mode": "trash",
	})
	wantStatus(t, resp, 200, "delete to trash")
	entries := decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries
	if len(entries) != 2 {
		t.Fatalf("trash entries = %d, want 2", len(entries))
	}

	// The 30-day policy purges nothing: both entries were just trashed, well
	// inside the window, so the age filter keeps them.
	if rep, err := h.svc.SweepTrashRetention(ctx); err != nil || rep.Purged != 0 {
		t.Fatalf("30-day sweep = %+v, %v; want no purge of recent entries", rep, err)
	}

	// The safety guard: a zero-age purge is a no-op rather than an
	// empty-everything, so a disabled policy can never wipe the journal.
	if rep, err := h.svc.PurgeTrashOlderThan(ctx, 0); err != nil || rep.Purged != 0 {
		t.Fatalf("zero-age purge = %+v, %v; want no-op", rep, err)
	}
	if n := len(decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries); n != 2 {
		t.Fatalf("trash after no-op sweeps = %d, want 2 (guard failed)", n)
	}

	// Purge one entry through the new endpoint: 200 with reclaimed bytes,
	// and it leaves the journal. Re-purging the same id is a clean 404.
	one := entries[0].Id
	resp = reqAs(t, h, "DELETE", "/api/v1/admin/trash/"+one, h.token, nil)
	if got := decode[TrashPurgeResult](t, resp); got.ReclaimedBytes <= 0 {
		t.Fatalf("purge reclaimed = %d, want > 0", got.ReclaimedBytes)
	}
	if n := len(decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries); n != 1 {
		t.Fatalf("trash after purge = %d, want 1", n)
	}
	resp = reqAs(t, h, "DELETE", "/api/v1/admin/trash/"+one, h.token, nil)
	wantStatus(t, resp, 404, "re-purge")

	// The age-scoped sweep does purge when the window catches an entry: the
	// remaining entry was trashed in the past, so a one-nanosecond window
	// (older than now) reclaims it.
	if rep, err := h.svc.PurgeTrashOlderThan(ctx, time.Nanosecond); err != nil || rep.Purged != 1 {
		t.Fatalf("nanosecond-age purge = %+v, %v; want 1 purged", rep, err)
	}
	if n := len(decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries); n != 0 {
		t.Fatalf("trash after age purge = %d, want 0", n)
	}
}

// A trashed item must not cost a search result its place.
//
// ADR-0048's state rule rides the query now, as SearchOptions.States, so
// archived rows never enter the ranking and never consume a slot. This
// is the case that proves it, and it is the one the deleted widening
// pass existed for: an album deleted in one go matches its own name
// best, so its archived rows would otherwise take the top of the ranking
// and empty a group outright. One pass has to fill the page.
func TestSearchFillsItsGroupsAroundTrashedHits(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	// Eight tracks sharing a term, five of them then trashed. The
	// survivors outnumber the page size, so a full page is the only
	// honest answer whatever the trash holds.
	const term = "Widening"
	for i := range 8 {
		if _, err := fixtures.Generate(h.library, fixtures.Spec{
			Name:  fmt.Sprintf("widen-%02d", i),
			Codec: fixtures.CodecMP3,
			// A distinct length each, so eight files are eight essences:
			// identical audio would dedupe to one item.
			Duration: time.Duration(1200+100*i) * time.Millisecond,
			Tags: map[string]string{
				"TITLE":  fmt.Sprintf("%s %02d", term, i),
				"ARTIST": "Widen Artist", "ALBUM": "Widen Album",
			},
		}); err != nil {
			t.Fatalf("generating fixture %d: %v", i, err)
		}
	}
	h.rescanAndWait(t)

	matches := map[string]string{}
	for _, it := range h.items(t, "?mediaType=music").Items {
		if strings.HasPrefix(it.Title, term) {
			matches[it.Title] = it.Pid
		}
	}
	if len(matches) != 8 {
		t.Fatalf("scanned %d %s tracks, want 8", len(matches), term)
	}
	doomed := make([]string, 0, 5)
	for i := range 5 {
		doomed = append(doomed, matches[fmt.Sprintf("%s %02d", term, i)])
	}
	resp := h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": doomed, "mode": "trash",
	})
	wantStatus(t, resp, 200, "delete to trash")

	trashed := map[string]bool{}
	for _, pid := range doomed {
		trashed[pid] = true
	}
	// Polled for the same reason the listing assertions above are: the
	// delete is a catalog write the search path reads back.
	deadline := time.Now().Add(30 * time.Second)
	for {
		hits := decode[SearchResults](t, get(t,
			h.ts, "/api/v1/library/search?q="+term+"&limit=3", h.token)).Tracks
		live := true
		for _, hit := range hits {
			if trashed[hit.Pid] {
				live = false
			}
		}
		// Three survivors are left over after the five that went, so a
		// page of three is what the caller asked for and can have. Never
		// more than three either: the contract caps a group at the limit.
		if live && len(hits) == 3 {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("search for %s returned %d hits (trashed among them: %v), want 3 live",
				term, len(hits), !live)
		}
		time.Sleep(100 * time.Millisecond)
	}
}

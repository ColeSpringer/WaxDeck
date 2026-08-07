package api

import (
	"io"
	"net/url"
	"strings"
	"testing"
	"time"
)

// musicRule builds the wire rule the smart playlist tests share:
// mediaType is music AND rating gte 80, sorted by title, capped.
func musicRatingRule(limit int) map[string]any {
	return map[string]any{
		"root": map[string]any{
			"type": "all",
			"nodes": []any{
				map[string]any{"type": "condition", "field": "mediaType", "op": "is", "value": "music"},
				map[string]any{"type": "condition", "field": "rating", "op": "gte", "value": "80"},
			},
		},
		"sorts": []any{map[string]any{"field": "title"}},
		"limit": limit,
	}
}

// playlistItems fetches one page of a playlist's members as a token.
func playlistItems(t *testing.T, h *harness, token, pid string) []PlaylistEntry {
	t.Helper()
	resp := reqAs(t, h, "GET", "/api/v1/playlists/"+pid+"/items", token, nil)
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("playlist items status = %d (%s)", resp.StatusCode, body)
	}
	return decode[PlaylistItemsPage](t, resp).Entries
}

func entryPids(entries []PlaylistEntry) []string {
	out := make([]string, 0, len(entries))
	for _, e := range entries {
		out = append(out, e.Item.Pid)
	}
	return out
}

func samePids(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

func TestPlaylistStaticLifecycle(t *testing.T) {
	h := newHarness(t)
	items := h.items(t, "")
	if len(items.Items) != 4 {
		t.Fatalf("fixture library has %d items, want 4", len(items.Items))
	}
	a, b, c, d := items.Items[0].Pid, items.Items[1].Pid, items.Items[2].Pid, items.Items[3].Pid

	resp := h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Road Trip", "kind": "static", "itemPids": []string{a, b, c},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create status = %d", resp.StatusCode)
	}
	pl := decode[Playlist](t, resp)
	if !strings.HasPrefix(pl.Pid, "pl-") || pl.Kind != "static" || pl.Visibility != "private" || !pl.IsOwner {
		t.Fatalf("created playlist = %+v", pl)
	}
	if pl.ItemCount == nil || *pl.ItemCount != 3 {
		t.Fatalf("created itemCount = %v, want 3", pl.ItemCount)
	}

	// The listing carries the stored count for static playlists.
	page := decode[PlaylistPage](t, get(t, h.ts, "/api/v1/playlists", h.token))
	if len(page.Playlists) != 1 || page.Playlists[0].Pid != pl.Pid {
		t.Fatalf("listing = %+v", page.Playlists)
	}
	if page.Playlists[0].ItemCount == nil || *page.Playlists[0].ItemCount != 3 {
		t.Fatalf("listing itemCount = %v, want 3", page.Playlists[0].ItemCount)
	}

	det := decode[Playlist](t, get(t, h.ts, "/api/v1/playlists/"+pl.Pid, h.token))
	if det.ItemCount == nil || *det.ItemCount != 3 {
		t.Fatalf("detail itemCount = %v, want 3", det.ItemCount)
	}

	// Members list in stored order with stored positions.
	entries := playlistItems(t, h, h.token, pl.Pid)
	if !samePids(entryPids(entries), []string{a, b, c}) {
		t.Fatalf("member pids = %v, want %v", entryPids(entries), []string{a, b, c})
	}
	for i, e := range entries {
		if e.Position == nil || *e.Position != i {
			t.Fatalf("entry %d position = %v, want %d", i, e.Position, i)
		}
	}

	// Append.
	resp = h.postJSON(t, "/api/v1/playlists/"+pl.Pid+"/items", map[string]any{"itemPids": []string{d}})
	if resp.StatusCode != 204 {
		t.Fatalf("append status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	entries = playlistItems(t, h, h.token, pl.Pid)
	if !samePids(entryPids(entries), []string{a, b, c, d}) || *entries[3].Position != 3 {
		t.Fatalf("post-append members = %v", entryPids(entries))
	}

	// Replace is the reorder primitive.
	resp = h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/items", map[string]any{"itemPids": []string{d, c, b, a}})
	if resp.StatusCode != 204 {
		t.Fatalf("replace status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	entries = playlistItems(t, h, h.token, pl.Pid)
	if !samePids(entryPids(entries), []string{d, c, b, a}) {
		t.Fatalf("post-replace members = %v, want reversed", entryPids(entries))
	}
	for i, e := range entries {
		if e.Position == nil || *e.Position != i {
			t.Fatalf("post-replace entry %d position = %v", i, e.Position)
		}
	}

	// Remove by stored position.
	resp = h.deleteReq(t, "/api/v1/playlists/"+pl.Pid+"/items/1")
	if resp.StatusCode != 204 {
		t.Fatalf("remove-at status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	entries = playlistItems(t, h, h.token, pl.Pid)
	if !samePids(entryPids(entries), []string{d, b, a}) {
		t.Fatalf("post-remove members = %v, want %v", entryPids(entries), []string{d, b, a})
	}

	// A replace built from a stale updatedAt answers the conflict.
	det = decode[Playlist](t, get(t, h.ts, "/api/v1/playlists/"+pl.Pid, h.token))
	stale := det.UpdatedAt.Add(-time.Hour)
	resp = h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/items", map[string]any{
		"itemPids": []string{a}, "baseUpdatedAt": stale.Format(time.RFC3339Nano),
	})
	if resp.StatusCode != 409 {
		t.Fatalf("stale replace status = %d, want 409", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "conflict" {
		t.Fatalf("stale replace code = %q, want conflict", e.Code)
	}
	// And the fresh one applies.
	resp = h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/items", map[string]any{
		"itemPids": []string{a, b}, "baseUpdatedAt": det.UpdatedAt.Format(time.RFC3339Nano),
	})
	if resp.StatusCode != 204 {
		t.Fatalf("fresh replace status = %d", resp.StatusCode)
	}
	resp.Body.Close()

	// containsItem restricts the listing to static playlists holding the
	// item; smart playlists never appear in a filtered listing.
	resp = h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Others", "kind": "static", "itemPids": []string{c},
	})
	other := decode[Playlist](t, resp)
	resp = h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Smart Too", "kind": "smart", "rule": musicRatingRule(0),
	})
	if resp.StatusCode != 201 {
		t.Fatalf("smart create status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	page = decode[PlaylistPage](t, get(t, h.ts, "/api/v1/playlists?containsItem="+url.QueryEscape(c), h.token))
	if len(page.Playlists) != 1 || page.Playlists[0].Pid != other.Pid {
		t.Fatalf("containsItem listing = %+v, want just %s", page.Playlists, other.Pid)
	}

	// Delete, then the pid stops resolving.
	resp = h.deleteReq(t, "/api/v1/playlists/"+pl.Pid)
	if resp.StatusCode != 204 {
		t.Fatalf("delete status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	resp = get(t, h.ts, "/api/v1/playlists/"+pl.Pid, h.token)
	if resp.StatusCode != 404 {
		t.Fatalf("deleted playlist status = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestPlaylistSmartPerUserEvaluation(t *testing.T) {
	h := newHarness(t)
	items := h.items(t, "")
	first, second := items.Items[0].Pid, items.Items[1].Pid

	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)

	// The admin's private smart playlist starts empty.
	resp = h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Bangers", "kind": "smart", "rule": musicRatingRule(10),
	})
	if resp.StatusCode != 201 {
		t.Fatalf("smart create status = %d", resp.StatusCode)
	}
	adminList := decode[Playlist](t, resp)
	if adminList.Rule == nil || adminList.ItemCount == nil || *adminList.ItemCount != 0 {
		t.Fatalf("fresh smart playlist = %+v, want a rule and zero members", adminList)
	}
	if len(playlistItems(t, h, h.token, adminList.Pid)) != 0 {
		t.Fatal("fresh smart playlist has members")
	}

	// The admin's rating pulls the item in for the admin.
	resp = h.putJSON(t, "/api/v1/items/"+first+"/rating", map[string]any{"rating": 90})
	if resp.StatusCode != 200 {
		t.Fatalf("rating status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	entries := playlistItems(t, h, h.token, adminList.Pid)
	if !samePids(entryPids(entries), []string{first}) {
		t.Fatalf("admin smart members = %v, want %v", entryPids(entries), []string{first})
	}
	if entries[0].Position != nil {
		t.Fatal("smart playlist entries must not carry stored positions")
	}
	det := decode[Playlist](t, get(t, h.ts, "/api/v1/playlists/"+adminList.Pid, h.token))
	if det.ItemCount == nil || *det.ItemCount != 1 {
		t.Fatalf("smart detail itemCount = %v, want 1", det.ItemCount)
	}

	// Sam's own smart playlist over the same rule follows sam's ratings.
	resp = reqAs(t, h, "PUT", "/api/v1/items/"+second+"/rating", sam.Token, map[string]any{"rating": 85})
	resp.Body.Close()
	resp = reqAs(t, h, "POST", "/api/v1/playlists", sam.Token, map[string]any{
		"name": "Sam Bangers", "kind": "smart", "rule": musicRatingRule(10),
	})
	if resp.StatusCode != 201 {
		t.Fatalf("sam smart create status = %d", resp.StatusCode)
	}
	samList := decode[Playlist](t, resp)
	if got := entryPids(playlistItems(t, h, sam.Token, samList.Pid)); !samePids(got, []string{second}) {
		t.Fatalf("sam smart members = %v, want %v", got, []string{second})
	}

	// A shared smart playlist evaluates as its OWNER for every reader.
	resp = h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Household Bangers", "kind": "smart", "visibility": "shared", "rule": musicRatingRule(10),
	})
	shared := decode[Playlist](t, resp)
	if got := entryPids(playlistItems(t, h, sam.Token, shared.Pid)); !samePids(got, []string{first}) {
		t.Fatalf("shared smart members for sam = %v, want the owner's %v", got, []string{first})
	}

	// The admin's private playlist does not exist for sam.
	resp = reqAs(t, h, "GET", "/api/v1/playlists/"+adminList.Pid, sam.Token, nil)
	if resp.StatusCode != 404 {
		t.Fatalf("private playlist status for sam = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()
	resp = reqAs(t, h, "GET", "/api/v1/playlists/"+adminList.Pid+"/items", sam.Token, nil)
	if resp.StatusCode != 404 {
		t.Fatalf("private playlist items status for sam = %d, want 404", resp.StatusCode)
	}
	resp.Body.Close()

	// The shared one is readable but never writable by a non-owner.
	resp = reqAs(t, h, "GET", "/api/v1/playlists/"+shared.Pid, sam.Token, nil)
	if resp.StatusCode != 200 {
		t.Fatalf("shared playlist status for sam = %d, want 200", resp.StatusCode)
	}
	if got := decode[Playlist](t, resp); got.IsOwner {
		t.Fatal("shared playlist reads as owned by a non-owner")
	}
	name := "Hijacked"
	resp = reqAs(t, h, "PATCH", "/api/v1/playlists/"+shared.Pid, sam.Token, map[string]any{"name": name})
	if resp.StatusCode != 403 {
		t.Fatalf("non-owner rename status = %d, want 403", resp.StatusCode)
	}
	resp.Body.Close()
	resp = reqAs(t, h, "DELETE", "/api/v1/playlists/"+shared.Pid, sam.Token, nil)
	if resp.StatusCode != 403 {
		t.Fatalf("non-owner delete status = %d, want 403", resp.StatusCode)
	}
	resp.Body.Close()

	// The same boundary on a shared static playlist's member writes.
	resp = h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Shared Static", "kind": "static", "visibility": "shared", "itemPids": []string{first},
	})
	sharedStatic := decode[Playlist](t, resp)
	resp = reqAs(t, h, "POST", "/api/v1/playlists/"+sharedStatic.Pid+"/items", sam.Token, map[string]any{"itemPids": []string{second}})
	if resp.StatusCode != 403 {
		t.Fatalf("non-owner append status = %d, want 403", resp.StatusCode)
	}
	resp.Body.Close()
	resp = reqAs(t, h, "PUT", "/api/v1/playlists/"+sharedStatic.Pid+"/items", sam.Token, map[string]any{"itemPids": []string{second}})
	if resp.StatusCode != 403 {
		t.Fatalf("non-owner replace status = %d, want 403", resp.StatusCode)
	}
	resp.Body.Close()
	resp = reqAs(t, h, "DELETE", "/api/v1/playlists/"+sharedStatic.Pid+"/items/0", sam.Token, nil)
	if resp.StatusCode != 403 {
		t.Fatalf("non-owner remove-at status = %d, want 403", resp.StatusCode)
	}
	resp.Body.Close()
}

func TestPlaylistRuleValidation(t *testing.T) {
	h := newHarness(t)

	deepNot := map[string]any{"type": "condition", "field": "title", "op": "is", "value": "x"}
	for range 11 {
		deepNot = map[string]any{"type": "not", "node": deepNot}
	}

	cases := []struct {
		name string
		root map[string]any
	}{
		{"unknown field", map[string]any{"type": "condition", "field": "wat", "op": "is", "value": "x"}},
		{"unknown op", map[string]any{"type": "condition", "field": "title", "op": "frobs", "value": "x"}},
		{"op invalid for kind", map[string]any{"type": "condition", "field": "title", "op": "gte", "value": "5"}},
		{"inTheRange with one value", map[string]any{"type": "condition", "field": "rating", "op": "inTheRange", "values": []string{"10"}}},
		{"unknown node type", map[string]any{"type": "xor"}},
		{"nesting past the depth cap", deepNot},
	}
	for _, tc := range cases {
		resp := h.postJSON(t, "/api/v1/playlists", map[string]any{
			"name": "Broken", "kind": "smart", "rule": map[string]any{"root": tc.root},
		})
		if resp.StatusCode != 400 {
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			t.Fatalf("%s: status = %d, want 400 (%s)", tc.name, resp.StatusCode, body)
		}
		if e := decode[Error](t, resp); e.Code != "invalid-request" {
			t.Fatalf("%s: code = %q, want invalid-request", tc.name, e.Code)
		}
	}
}

func TestPlaylistRuleUpdateInPlace(t *testing.T) {
	h := newHarness(t)

	resp := h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Rotation", "kind": "smart", "rule": map[string]any{
			"root": map[string]any{"type": "condition", "field": "mediaType", "op": "is", "value": "music"},
		},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create status = %d", resp.StatusCode)
	}
	pl := decode[Playlist](t, resp)

	// A cursor minted before the edit observes it as one event.
	mint := decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server", h.token))

	resp = h.patchJSON(t, "/api/v1/playlists/"+pl.Pid, map[string]any{"rule": musicRatingRule(5)})
	if resp.StatusCode != 200 {
		t.Fatalf("rule update status = %d", resp.StatusCode)
	}
	upd := decode[Playlist](t, resp)
	if upd.Pid != pl.Pid {
		t.Fatalf("rule update changed the pid %s -> %s; the rule now updates in place", pl.Pid, upd.Pid)
	}
	if upd.PreviousPid != nil {
		t.Fatalf("previousPid = %v, want nil (the reissue seam is retired)", *upd.PreviousPid)
	}
	if upd.Rule == nil || upd.Rule.Limit == nil || *upd.Rule.Limit != 5 {
		t.Fatalf("updated rule = %+v, want the new rule with limit 5", upd.Rule)
	}

	// The pid still resolves and carries the new rule.
	resp = get(t, h.ts, "/api/v1/playlists/"+pl.Pid, h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("updated pid status = %d, want 200", resp.StatusCode)
	}
	got := decode[Playlist](t, resp)
	if got.Rule == nil || got.Rule.Limit == nil || *got.Rule.Limit != 5 {
		t.Fatalf("reread rule = %+v, want limit 5", got.Rule)
	}

	// The caller's server delta carries exactly one playlist event: the
	// stable pid, hydrated with its current state, no previousPid.
	delta := decode[ServerSyncPage](t, get(t, h.ts, "/api/v1/sync/server?since="+mint.NextSince, h.token))
	var events int
	for _, ev := range delta.Events {
		if ev.Kind != "playlist" || ev.Pid == nil || *ev.Pid != pl.Pid {
			continue
		}
		events++
		if ev.Playlist == nil {
			t.Fatalf("in-place edit event carries no playlist: %+v", ev)
		}
		if ev.Playlist.PreviousPid != nil {
			t.Fatalf("in-place edit event carries previousPid %v", *ev.Playlist.PreviousPid)
		}
	}
	if events != 1 {
		t.Fatalf("playlist events for the stable pid = %d, want 1 (events %+v)", events, delta.Events)
	}
}

// TestPlaylistRelativeAndLimitModes pins the wire contract for the
// relative-date operators and limit modes the rule setter unlocked:
// each round-trips through create and detail read, and the guarded
// combinations answer invalid-request.
func TestPlaylistRelativeAndLimitModes(t *testing.T) {
	h := newHarness(t)

	// A relative-date rule with a random draw round-trips: the day
	// window comes back as the same day count, the mode as random.
	resp := h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Fresh shuffle", "kind": "smart",
		"rule": map[string]any{
			"root": map[string]any{
				"type": "condition", "field": "addedAt", "op": "inTheLast", "value": "30",
			},
			"limit": 25, "limitMode": "random",
		},
	})
	if resp.StatusCode != 201 {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("create status = %d (%s)", resp.StatusCode, body)
	}
	pl := decode[Playlist](t, resp)
	got := decode[Playlist](t, get(t, h.ts, "/api/v1/playlists/"+pl.Pid, h.token))
	if got.Rule == nil {
		t.Fatal("smart playlist read back without a rule")
	}
	if got.Rule.LimitMode == nil || *got.Rule.LimitMode != "random" {
		t.Fatalf("limitMode = %v, want random", got.Rule.LimitMode)
	}
	if got.Rule.Limit == nil || *got.Rule.Limit != 25 {
		t.Fatalf("limit = %v, want 25", got.Rule.Limit)
	}
	root := got.Rule.Root
	if root.Op == nil || *root.Op != "inTheLast" || root.Value == nil || *root.Value != "30" {
		t.Fatalf("relative condition read back as op=%v value=%v, want inTheLast/30", root.Op, root.Value)
	}

	// A minutes budget round-trips its mode.
	resp = h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "An hour", "kind": "smart",
		"rule": map[string]any{
			"root":  map[string]any{"type": "condition", "field": "mediaType", "op": "is", "value": "music"},
			"limit": 60, "limitMode": "minutes",
		},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("minutes create status = %d", resp.StatusCode)
	}
	mins := decode[Playlist](t, resp)
	minsGot := decode[Playlist](t, get(t, h.ts, "/api/v1/playlists/"+mins.Pid, h.token))
	if minsGot.Rule == nil || minsGot.Rule.LimitMode == nil || *minsGot.Rule.LimitMode != "minutes" {
		t.Fatalf("minutes mode did not round-trip: %+v", minsGot.Rule)
	}

	// Guarded combinations answer invalid-request, not a 500.
	bad := []map[string]any{
		{ // random cannot take a sort order
			"root":  map[string]any{"type": "condition", "field": "mediaType", "op": "is", "value": "music"},
			"limit": 5, "limitMode": "random",
			"sorts": []any{map[string]any{"field": "title"}},
		},
		{ // a seed needs a non-count mode
			"root":      map[string]any{"type": "condition", "field": "mediaType", "op": "is", "value": "music"},
			"limitSeed": 7,
		},
		{ // relative operators apply only to date fields
			"root": map[string]any{"type": "condition", "field": "title", "op": "inTheLast", "value": "30"},
		},
		{ // a budget mode needs a positive limit
			"root":  map[string]any{"type": "condition", "field": "mediaType", "op": "is", "value": "music"},
			"limit": 0, "limitMode": "megabytes",
		},
	}
	for i, rule := range bad {
		resp := h.postJSON(t, "/api/v1/playlists", map[string]any{
			"name": "bad", "kind": "smart", "rule": rule,
		})
		if resp.StatusCode != 400 {
			body, _ := io.ReadAll(resp.Body)
			t.Fatalf("bad rule %d status = %d, want 400 (%s)", i, resp.StatusCode, body)
		}
		resp.Body.Close()
	}
}

func TestPlaylistPreviewAndRuleFields(t *testing.T) {
	h := newHarness(t)

	// Preview honors the rule's own limit on items while the total
	// ignores it.
	resp := h.postJSON(t, "/api/v1/playlists/preview", map[string]any{
		"root":  map[string]any{"type": "condition", "field": "mediaType", "op": "is", "value": "music"},
		"sorts": []any{map[string]any{"field": "title"}},
		"limit": 2,
	})
	if resp.StatusCode != 200 {
		t.Fatalf("preview status = %d", resp.StatusCode)
	}
	prev := decode[PlaylistPreview](t, resp)
	if len(prev.Items) != 2 || prev.Total != 4 {
		t.Fatalf("preview = %d items total %d, want 2 items total 4", len(prev.Items), prev.Total)
	}
	if prev.Items[0].Title != "Alpha Song" || prev.Items[1].Title != "Bravo Song" {
		t.Fatalf("preview order = %q, %q", prev.Items[0].Title, prev.Items[1].Title)
	}

	// The vocabulary drives rule editors; pin a few load-bearing rows.
	rf := decode[RuleFields](t, get(t, h.ts, "/api/v1/playlists/rule-fields", h.token))
	byName := map[string]RuleField{}
	for _, f := range rf.Fields {
		byName[f.Name] = f
	}
	rating, ok := byName["rating"]
	if !ok || rating.Kind != "number" || !rating.UserState || !rating.Sortable {
		t.Fatalf("rating field = %+v, want a sortable user-state number", rating)
	}
	hasGte := false
	for _, op := range rating.Ops {
		if op == "gte" {
			hasGte = true
		}
	}
	if !hasGte {
		t.Fatalf("rating ops = %v, want gte included", rating.Ops)
	}
	mt, ok := byName["mediaType"]
	if !ok || mt.Kind != "mediaType" || len(mt.Ops) != 2 || mt.Ops[0] != "is" || mt.Ops[1] != "isNot" {
		t.Fatalf("mediaType field = %+v, want is/isNot only", mt)
	}
	title, ok := byName["title"]
	if !ok || title.Kind != "text" || title.UserState {
		t.Fatalf("title field = %+v, want catalog text", title)
	}

	// The album release-identity fields: catalog text, never sortable
	// (they are identifiers, not orderings), and each has to actually
	// evaluate. A vocabulary row naming an engine field the query
	// grammar does not know would advertise a rule the editor can build
	// and the server then refuses.
	for _, name := range []string{
		"albumBarcode", "albumLabel", "albumCatalogNumber",
		"albumMedia", "albumCountry",
	} {
		f, ok := byName[name]
		if !ok {
			t.Errorf("%s missing from the rule vocabulary", name)
			continue
		}
		if f.Kind != "text" || f.UserState || f.Sortable {
			t.Errorf("%s = %+v, want unsortable catalog text", name, f)
		}
		resp := h.postJSON(t, "/api/v1/playlists/preview", map[string]any{
			"root": map[string]any{
				"type": "condition", "field": name, "op": "contains", "value": "zzz-no-match",
			},
		})
		wantStatus(t, resp, 200, "preview on "+name)
	}
}

func TestPlaylistM3uRoundTrip(t *testing.T) {
	h := newHarness(t)
	items := h.items(t, "")
	var pids []string
	for _, it := range items.Items {
		pids = append(pids, it.Pid)
	}

	resp := h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Exported", "kind": "static", "itemPids": pids,
	})
	pl := decode[Playlist](t, resp)

	resp = get(t, h.ts, "/api/v1/playlists/"+pl.Pid+"/m3u", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("export status = %d", resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); !strings.Contains(ct, "mpegurl") {
		t.Fatalf("export content type = %q", ct)
	}
	doc, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.Contains(string(doc), "alpha.flac") {
		t.Fatalf("export lacks a member path: %s", doc)
	}

	resp = h.postJSON(t, "/api/v1/playlists/m3u", map[string]any{
		"name": "Imported", "content": string(doc),
	})
	if resp.StatusCode != 201 {
		t.Fatalf("import status = %d", resp.StatusCode)
	}
	res := decode[M3uImportResult](t, resp)
	if res.Matched != len(pids) || res.Unmatched != 0 {
		t.Fatalf("import = matched %d unmatched %d, want %d/0", res.Matched, res.Unmatched, len(pids))
	}
	got := entryPids(playlistItems(t, h, h.token, res.Playlist.Pid))
	if !samePids(got, pids) {
		t.Fatalf("imported members = %v, want %v", got, pids)
	}
}

func TestPlaylistReplaceBasePrecisionTolerance(t *testing.T) {
	h := newHarness(t)
	items := h.items(t, "?mediaType=music")
	a, b := items.Items[0].Pid, items.Items[1].Pid
	resp := h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Precision", "kind": "static", "itemPids": []string{a, b},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create status = %d", resp.StatusCode)
	}
	pl := decode[Playlist](t, resp)

	// A Dart client's DateTime keeps microseconds and JavaScript's
	// keeps milliseconds; echoing the read timestamp back through
	// either must still satisfy the lost-update guard against the
	// stored nanoseconds.
	for _, grain := range []time.Duration{time.Microsecond, time.Millisecond} {
		det := decode[Playlist](t, get(t, h.ts, "/api/v1/playlists/"+pl.Pid, h.token))
		base := det.UpdatedAt.Truncate(grain)
		resp = h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/items", map[string]any{
			"itemPids": []string{b, a}, "baseUpdatedAt": base.Format(time.RFC3339Nano),
		})
		if resp.StatusCode != 204 {
			body := decode[Error](t, resp)
			t.Fatalf("replace with %s-grain base = %d (%s), want 204", grain, resp.StatusCode, body.Message)
		}
		resp.Body.Close()
	}
}

func TestPlaylistReplaceRefusesUnsubscribedMembers(t *testing.T) {
	h := newPodcastHarness(t)
	feed := newFeedServer(t, 2)
	resp := h.postJSON(t, "/api/v1/podcasts", map[string]any{"url": feed.feedURL()})
	if resp.StatusCode != 201 {
		t.Fatalf("subscribe status = %d", resp.StatusCode)
	}
	sub := decode[Subscription](t, resp)
	eps := decode[EpisodePage](t, get(t, h.ts, "/api/v1/podcasts/"+sub.Show.Pid+"/episodes", h.token))
	if len(eps.Items) == 0 {
		t.Fatal("no episodes cataloged")
	}
	episode := eps.Items[0].Pid
	track := h.items(t, "?mediaType=music").Items[0].Pid

	resp = h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Mixed", "kind": "static", "itemPids": []string{track, episode},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create status = %d", resp.StatusCode)
	}
	pl := decode[Playlist](t, resp)

	// Unsubscribing hides the episode from the member listing; a
	// replace built from that filtered view must refuse rather than
	// silently drop the stored member. The caller here has full
	// library visibility, which must not skip the guard.
	resp = h.deleteReq(t, "/api/v1/podcasts/"+sub.Show.Pid)
	if resp.StatusCode != 204 {
		t.Fatalf("unsubscribe status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	visible := playlistItems(t, h, h.token, pl.Pid)
	if len(visible) != 1 {
		t.Fatalf("visible members after unsubscribe = %d, want the track only", len(visible))
	}
	resp = h.putJSON(t, "/api/v1/playlists/"+pl.Pid+"/items", map[string]any{
		"itemPids": []string{track},
	})
	if resp.StatusCode != 409 {
		t.Fatalf("replace status = %d, want 409", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "conflict" || !strings.Contains(e.Message, "subscribed") {
		t.Fatalf("replace error = %+v, want the subscription refusal", e)
	}
}

// A smart playlist drops trashed members, except when its rule asks
// about state itself (ADR-0048). `state` is a documented rule field the
// contract exposes through /playlists/rule-fields, so the blanket
// predicate every other listing gets would quietly make `state is
// archived` answer nothing.
func TestSmartPlaylistStateRuleSeesArchivedItems(t *testing.T) {
	h := newHarness(t)
	items := h.items(t, "?mediaType=music")
	if len(items.Items) < 2 {
		t.Fatalf("need at least 2 music items, have %d", len(items.Items))
	}
	doomed := items.Items[0].Pid

	everything := map[string]any{
		"root":  map[string]any{"type": "condition", "field": "mediaType", "op": "is", "value": "music"},
		"sorts": []any{map[string]any{"field": "title"}},
	}
	onlyTrashed := map[string]any{
		"root": map[string]any{
			"type": "all",
			"nodes": []any{
				map[string]any{"type": "condition", "field": "mediaType", "op": "is", "value": "music"},
				map[string]any{"type": "condition", "field": "state", "op": "is", "value": "archived"},
			},
		},
		"sorts": []any{map[string]any{"field": "title"}},
	}

	resp := h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "All Music", "kind": "smart", "rule": everything,
	})
	if resp.StatusCode != 201 {
		t.Fatalf("plain smart create status = %d", resp.StatusCode)
	}
	plain := decode[Playlist](t, resp)
	resp = h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Deleted Music", "kind": "smart", "rule": onlyTrashed,
	})
	if resp.StatusCode != 201 {
		t.Fatalf("state-rule smart create status = %d", resp.StatusCode)
	}
	stateRule := decode[Playlist](t, resp)

	before := len(playlistItems(t, h, h.token, plain.Pid))
	if before == 0 {
		t.Fatal("the plain smart playlist matched nothing to begin with")
	}
	if n := len(playlistItems(t, h, h.token, stateRule.Pid)); n != 0 {
		t.Fatalf("state-rule members before any delete = %d, want 0", n)
	}

	resp = h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
		"pids": []string{doomed}, "mode": "trash",
	})
	wantStatus(t, resp, 200, "delete to trash")

	deadline := time.Now().Add(30 * time.Second)
	for {
		plainPids := entryPids(playlistItems(t, h, h.token, plain.Pid))
		statePids := entryPids(playlistItems(t, h, h.token, stateRule.Pid))
		if len(plainPids) == before-1 && samePids(statePids, []string{doomed}) {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("plain members = %v (want %d, without %s); state-rule members = %v (want just %s)",
				plainPids, before-1, doomed, statePids, doomed)
		}
		time.Sleep(100 * time.Millisecond)
	}

	// The count on the playlist row agrees with the members it hands
	// back, on both rules.
	for _, pl := range []Playlist{plain, stateRule} {
		det := decode[Playlist](t, get(t, h.ts, "/api/v1/playlists/"+pl.Pid, h.token))
		want := len(playlistItems(t, h, h.token, pl.Pid))
		if det.ItemCount == nil || *det.ItemCount != want {
			t.Errorf("%s itemCount = %v, want %d", pl.Name, det.ItemCount, want)
		}
	}

	// The editor still shows what its author wrote: the predicate rides
	// the evaluation, never the stored rule.
	det := decode[Playlist](t, get(t, h.ts, "/api/v1/playlists/"+plain.Pid, h.token))
	if det.Rule == nil || det.Rule.Root.Field == nil || *det.Rule.Root.Field != "mediaType" {
		t.Fatalf("stored rule came back rewritten: %+v", det.Rule)
	}
}

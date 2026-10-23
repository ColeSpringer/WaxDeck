package api

import (
	"context"
	"io"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/db"
)

// A deleted member's shared playlists go to the administrator who deleted
// them with their entries, and the record says how many went where.
func TestDeletingAMemberHandsTheirSharedPlaylistToTheAdministrator(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pids := []string{}
	for _, it := range h.items(t, "?mediaType=music").Items[:2] {
		pids = append(pids, it.Pid)
	}
	sam := decodeStatus[UserAccount](t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "sam", "password": testPassword,
	}), 201, "create sam")
	samToken := loginAs(t, h.ts, "sam", testPassword).Token
	makePlaylist := func(name, visibility string) Playlist {
		t.Helper()
		return decodeStatus[Playlist](t, reqAs(t, h, "POST", "/api/v1/playlists", samToken, map[string]any{
			"name": name, "kind": "static", "visibility": visibility, "itemPids": pids,
		}), 201, "create "+name)
	}
	shared := makePlaylist("Road trip", "shared")
	private := makePlaylist("Guilty pleasures", "private")

	wantStatus(t, h.deleteReq(t, "/api/v1/users/"+sam.Id), 204, "delete sam")

	// The administrator owns the shared one now: same entries, theirs to
	// edit, listed under their name.
	got := decodeStatus[Playlist](t, get(t, h.ts, "/api/v1/playlists/"+shared.Pid, h.token), 200, "read it")
	if !got.IsOwner || got.OwnerName != "admin" || got.Visibility != "shared" {
		t.Errorf("playlist = %+v, want the administrator's and still shared", got)
	}
	entries := decodeStatus[PlaylistItemsPage](t, get(t, h.ts, "/api/v1/playlists/"+shared.Pid+"/items", h.token), 200, "its entries").Entries
	if len(entries) != len(pids) {
		t.Errorf("entries = %d, want its %d kept", len(entries), len(pids))
	}
	wantStatus(t, h.patchJSON(t, "/api/v1/playlists/"+shared.Pid, map[string]any{"name": "Road trip (kept)"}),
		200, "the administrator renames it")
	wantStatus(t, get(t, h.ts, "/api/v1/playlists/"+private.Pid, h.token), 404, "the private one")

	// The record: who deleted whom, and what happened to the playlists.
	events := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=user.delete", h.token)).Events
	if len(events) != 1 || events[0].TargetName == nil || *events[0].TargetName != "sam" {
		t.Fatalf("user.delete entries = %+v, want one about sam", events)
	}
	d := *events[0].Detail
	// The private one and the starter every account is seeded with.
	if d["playlistsTransferred"] != float64(1) || d["playlistsDeleted"] != float64(2) || d["transferredTo"] != "admin" {
		t.Errorf("detail = %v, want 1 handed to admin and 2 deleted", d)
	}
}

// The other answers are the caller's to choose, and a bad one is refused
// before the account or its playlists are touched.
func TestDeletingAMemberTakesTheCallersChoiceOfWhatBecomesOfTheirPlaylists(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pids := []string{h.items(t, "?mediaType=music").Items[0].Pid}
	create := func(name string) (UserAccount, string) {
		t.Helper()
		acct := decodeStatus[UserAccount](t, h.postJSON(t, "/api/v1/users", map[string]any{
			"username": name, "password": testPassword,
		}), 201, "create "+name)
		return acct, loginAs(t, h.ts, name, testPassword).Token
	}
	share := func(token, name string) Playlist {
		t.Helper()
		return decodeStatus[Playlist](t, reqAs(t, h, "POST", "/api/v1/playlists", token, map[string]any{
			"name": name, "kind": "static", "visibility": "shared", "itemPids": pids,
		}), 201, "create "+name)
	}
	sam, samToken := create("sam")
	pat, patToken := create("pat")
	lists := share(samToken, "Sam's mix")

	// Refused: nothing changes.
	for name, query := range map[string]string{
		"an unknown answer":         "?playlists=keep",
		"a recipient with delete":   "?playlists=delete&transferTo=" + pat.Id,
		"a recipient who is absent": "?transferTo=us-01JZX5N8QW3F4V9T2B7KDNOBODY",
		"the account itself":        "?transferTo=" + sam.Id,
	} {
		resp := h.deleteReq(t, "/api/v1/users/"+sam.Id+query)
		if resp.StatusCode != 400 {
			t.Errorf("%s: status = %d, want 400", name, resp.StatusCode)
		} else if e := decode[Error](t, resp); e.Code != "invalid-request" {
			t.Errorf("%s: code = %q, want invalid-request", name, e.Code)
		}
	}
	wantStatus(t, get(t, h.ts, "/api/v1/users/"+sam.Id, h.token), 200, "sam after the refusals")
	if got := decodeStatus[Playlist](t, get(t, h.ts, "/api/v1/playlists/"+lists.Pid, patToken), 200, "the mix"); got.IsOwner {
		t.Errorf("a refused deletion moved the playlist: %+v", got)
	}

	// Handed to another member rather than to the administrator.
	wantStatus(t, h.deleteReq(t, "/api/v1/users/"+sam.Id+"?transferTo="+pat.Id), 204, "delete sam to pat")
	got := decodeStatus[Playlist](t, get(t, h.ts, "/api/v1/playlists/"+lists.Pid, patToken), 200, "the mix")
	if !got.IsOwner || got.OwnerName != "pat" {
		t.Errorf("playlist = %+v, want pat's", got)
	}

	// Deleted outright.
	kit, kitToken := create("kit")
	gone := share(kitToken, "Kit's mix")
	wantStatus(t, h.deleteReq(t, "/api/v1/users/"+kit.Id+"?playlists=delete"), 204, "delete kit with the playlists")
	wantStatus(t, get(t, h.ts, "/api/v1/playlists/"+gone.Pid, h.token), 404, "kit's mix")
	events := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=user.delete", h.token)).Events
	if len(events) != 2 {
		t.Fatalf("user.delete entries = %d, want 2", len(events))
	}
	d := *events[0].Detail
	if d["playlistsTransferred"] != float64(0) || d["playlistsDeleted"] != float64(2) {
		t.Errorf("detail = %v, want nothing handed over and kit's two deleted", d)
	}
	if _, has := d["transferredTo"]; has {
		t.Errorf("detail names a recipient although nothing moved: %v", d)
	}
}

// A shared smart playlist over the member's own stars would show every
// reader the administrator's stars once the administrator owns it, so it
// arrives as a fixed list of what it held. The public link the member made
// on it is the member's and ends with the account. The record says one
// list went over that way and one link ended.
func TestDeletingAMemberHandsOverAListOverTheirStarsAsAFixedList(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	tracks := h.items(t, "?mediaType=music").Items
	sam := decodeStatus[UserAccount](t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "sam", "password": testPassword,
	}), 201, "create sam")
	samToken := loginAs(t, h.ts, "sam", testPassword).Token
	for _, it := range tracks[:2] {
		wantStatus(t, reqAs(t, h, "PUT", "/api/v1/items/"+it.Pid+"/star", samToken, map[string]any{"starred": true}),
			200, "sam stars "+it.Pid)
	}
	// The administrator's own star is on a track sam's list never held.
	wantStatus(t, h.putJSON(t, "/api/v1/items/"+tracks[3].Pid+"/star", map[string]any{"starred": true}),
		200, "the administrator stars one")
	list := decodeStatus[Playlist](t, reqAs(t, h, "POST", "/api/v1/playlists", samToken, map[string]any{
		"name": "Starred", "kind": "smart", "visibility": "shared",
		"rule": map[string]any{"root": map[string]any{
			"type": "condition", "field": "starred", "op": "is", "value": "true",
		}},
	}), 201, "create the list")
	before := playlistItems(t, h, samToken, list.Pid)
	if len(before) != 2 {
		t.Fatalf("sam's list holds %d entries, want his two stars", len(before))
	}
	link := decodeStatus[Share](t, reqAs(t, h, "POST", "/api/v1/shares", samToken, map[string]any{"pid": list.Pid}),
		201, "share the list")

	wantStatus(t, h.deleteReq(t, "/api/v1/users/"+sam.Id), 204, "delete sam")

	wantStatus(t, get(t, h.ts, "/api/v1/playlists/"+list.Pid, h.token), 404, "the smart list after the handover")
	page := decodeStatus[PlaylistPage](t, get(t, h.ts, "/api/v1/playlists", h.token), 200, "the administrator's playlists")
	var fixed *Playlist
	for i, pl := range page.Playlists {
		if pl.Name == "Starred" {
			fixed = &page.Playlists[i]
		}
	}
	if fixed == nil || fixed.Kind != "static" || fixed.Visibility != "shared" || !fixed.IsOwner {
		t.Fatalf("handed-over list = %+v, want the administrator's shared fixed list", fixed)
	}
	after := playlistItems(t, h, h.token, fixed.Pid)
	if len(after) != len(before) || after[0].Item.Pid != before[0].Item.Pid || after[1].Item.Pid != before[1].Item.Pid {
		t.Errorf("entries = %+v, want sam's %+v", after, before)
	}
	resp := get(t, h.ts, link.Url, "")
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 404 || strings.Contains(string(body), "Starred") {
		t.Errorf("the member's public link = %d %.200s, want it ended", resp.StatusCode, body)
	}

	events := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=user.delete", h.token)).Events
	if len(events) != 1 {
		t.Fatalf("user.delete entries = %+v, want one", events)
	}
	if d := *events[0].Detail; d["playlistsTransferred"] != float64(1) || d["playlistsFixed"] != float64(1) || d["linksEnded"] != float64(1) {
		t.Errorf("detail = %v, want one handed over, as a fixed list, and one link ended", d)
	}
}

// A deletion that deletes the member's playlists removes the fixed copy an
// earlier attempt left of one of them, and its entry names the copy, as the
// entry of the attempt that left it did. The state a stopped attempt leaves
// is made here by hand: the record, and a list that carries the marker.
func TestADeletionReportsTheCopyAnEarlierAttemptLeft(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	sam := decodeStatus[UserAccount](t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "sam", "password": testPassword,
	}), 201, "create sam")
	samToken := loginAs(t, h.ts, "sam", testPassword).Token
	list := decodeStatus[Playlist](t, reqAs(t, h, "POST", "/api/v1/playlists", samToken, map[string]any{
		"name": "Starred", "kind": "smart", "visibility": "shared",
		"rule": map[string]any{"root": map[string]any{
			"type": "condition", "field": "starred", "op": "is", "value": "true",
		}},
	}), 201, "create the list")
	source := strings.TrimPrefix(list.Pid, "pl-")
	adminID := decodeStatus[SessionInfo](t, get(t, h.ts, "/api/v1/auth/session", h.token), 200, "the session").User.Id
	left := decodeStatus[Playlist](t, h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Starred [handover " + source + "]", "kind": "static", "visibility": "shared",
	}), 201, "create the copy")
	if err := h.store.PutPlaylistHandover(context.Background(), db.PlaylistHandover{
		SourcePID: source, CopyPID: strings.TrimPrefix(left.Pid, "pl-"), UserID: sam.Id, TakerID: adminID,
	}); err != nil {
		t.Fatal(err)
	}

	wantStatus(t, h.deleteReq(t, "/api/v1/users/"+sam.Id+"?playlists=delete"), 204, "delete sam with the playlists")

	wantStatus(t, get(t, h.ts, "/api/v1/playlists/"+left.Pid, h.token), 404, "the copy the earlier attempt left")
	events := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=user.delete", h.token)).Events
	if len(events) != 1 {
		t.Fatalf("user.delete entries = %+v, want one", events)
	}
	d := *events[0].Detail
	if !jsonEqual(d["fixedCopiesRemoved"], []string{left.Pid}) {
		t.Errorf("detail = %v, want the copy %s named as removed", d, left.Pid)
	}
	if _, has := d["fixedCopiesKept"]; has {
		t.Errorf("detail = %v, want no copy named as kept", d)
	}
}

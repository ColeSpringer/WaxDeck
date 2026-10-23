package service

import (
	"bytes"
	"context"
	"errors"
	"reflect"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// ownedNamed is the one playlist a catalog user owns under a name.
func ownedNamed(t *testing.T, ctx context.Context, svc *Library, catalogPID, name string) *model.Playlist {
	t.Helper()
	all, err := svc.lib.Playlists().List(ctx, model.PID(catalogPID))
	if err != nil {
		t.Fatalf("listing playlists: %v", err)
	}
	var found []*model.Playlist
	for _, pl := range all {
		if string(pl.OwnerPID) == catalogPID && pl.Name == name {
			found = append(found, pl)
		}
	}
	if len(found) != 1 {
		t.Fatalf("catalog user %s owns %d playlists named %q, want one", catalogPID, len(found), name)
	}
	return found[0]
}

// shareOf makes a public link to a playlist and answers its bare id.
func shareOf(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, playlist string) string {
	t.Helper()
	sh, err := svc.CreateShare(ctx, uc, playlist, 0, false, 0)
	if err != nil {
		t.Fatalf("sharing %s: %v", playlist, err)
	}
	_, id, _ := parseAPIPID(sh.ID)
	return string(id)
}

func itemPIDsOf(items []ItemSummary) []string {
	out := make([]string, 0, len(items))
	for _, it := range items {
		out = append(out, it.PID)
	}
	return out
}

// A shared smart playlist over a member's own stars, ratings or plays
// shows its reader what that member holds, so handing it over as it
// stands would show them the administrator's stars under the old name.
// It goes over as a fixed list of the tracks it held, and a reader's pin
// of the old one finds the new one. The member's public link is the
// member's and goes with the account.
func TestDeletingAnAccountHandsOverAListThatFollowsTheirStarsAsAFixedList(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	_, reader := playlistMember(t, ctx, svc, "reader")

	for _, pid := range pids[:2] {
		if _, err := svc.SetStar(ctx, samCtx, pid, true, nil); err != nil {
			t.Fatal(err)
		}
	}
	// The administrator's own star sits on a track sam's list never held.
	if _, err := svc.SetStar(ctx, admin, pids[3], true, nil); err != nil {
		t.Fatal(err)
	}
	list := smartPlaylist(t, ctx, svc, samCtx, "Sam's favourites", "shared", SmartRule{
		Root: RuleNode{Type: "condition", Field: "starred", Op: "is", Value: "true"},
	})
	before := memberPIDs(t, ctx, svc, reader, list)
	if len(before) != 2 {
		t.Fatalf("the reader sees %v before the handover, want sam's two stars", before)
	}
	link := shareOf(t, ctx, svc, samCtx, list)
	if _, err := svc.PutPrefs(ctx, reader, Prefs{Pinned: []string{list}}); err != nil {
		t.Fatal(err)
	}
	since, err := svc.MintServerCursor(ctx)
	if err != nil {
		t.Fatal(err)
	}

	got, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{})
	if err != nil {
		t.Fatal(err)
	}
	if got.PlaylistsTransferred != 1 {
		t.Fatalf("result = %+v, want the one shared playlist handed over", got)
	}

	// The smart list is gone and a static one of the same name, owner
	// visibility and entries is the administrator's.
	if catalogHas(ctx, svc, list) {
		t.Error("the smart playlist survived its handover")
	}
	kept := ownedNamed(t, ctx, svc, admin.CatalogPID, "Sam's favourites")
	if kept.Kind != model.PlaylistStatic || kept.Visibility != model.VisibilityShared {
		t.Errorf("handed-over playlist = %s and %s, want a shared static list", kept.Kind, kept.Visibility)
	}
	handed := apiPID(PrefixPlaylist, kept.PID)
	if after := memberPIDs(t, ctx, svc, reader, handed); !slices.Equal(after, before) {
		t.Errorf("the reader sees %v after the handover, want the %v it held for sam", after, before)
	}

	// The link was the member's, and ended with the account: it is not the
	// administrator's to serve, and nothing of the new list answers to it.
	if got.LinksEnded != 1 {
		t.Errorf("result = %+v, want the member's one link counted as ended", got)
	}
	if _, err := svc.ResolveShare(ctx, link); KindOf(err) != KindNotFound {
		t.Errorf("the member's link after the deletion = %v, want not found", err)
	}
	if _, err := svc.db.ShareByID(ctx, link); !errors.Is(err, wdb.ErrNotFound) {
		t.Errorf("the member's link row after the deletion = %v, want it gone with the account", err)
	}

	// A reader's pin follows to the new list.
	prefs, err := svc.Prefs(ctx, reader)
	if err != nil || !slices.Equal(prefs.Pinned, []string{handed}) {
		t.Errorf("the reader's pins = %v (%v), want [%s]", prefs.Pinned, err, handed)
	}

	// Their stream hears the old list go and the new one arrive.
	delta, err := svc.SyncServerDelta(ctx, reader, since, 100)
	if err != nil {
		t.Fatal(err)
	}
	var oldGone, newSeen bool
	for _, e := range delta.Events {
		if e.Kind != eventPlaylist {
			continue
		}
		switch e.PID {
		case list:
			oldGone = e.Playlist == nil
		case handed:
			newSeen = e.Playlist != nil && e.Playlist.Kind == "static"
		}
	}
	if !oldGone || !newSeen {
		t.Errorf("the reader's stream: old playlist gone = %v, new playlist seen = %v, want both", oldGone, newSeen)
	}
}

// A shared smart playlist that reads only the catalog means the same to
// every account, so it goes over as the rule it is. The member's link on
// it ends with the member.
func TestDeletingAnAccountHandsOverACatalogOnlySmartListUnchanged(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	_, reader := playlistMember(t, ctx, svc, "reader")

	list := smartPlaylist(t, ctx, svc, samCtx, "All the music", "shared", SmartRule{Root: allMusic()})
	before := memberPIDs(t, ctx, svc, reader, list)
	if len(before) != len(pids) {
		t.Fatalf("the reader sees %d before the handover, want %d", len(before), len(pids))
	}
	link := shareOf(t, ctx, svc, samCtx, list)

	if _, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{}); err != nil {
		t.Fatal(err)
	}

	kept := ownedNamed(t, ctx, svc, admin.CatalogPID, "All the music")
	if string(kept.PID) == "" || apiPID(PrefixPlaylist, kept.PID) != list {
		t.Errorf("handed-over playlist = %s, want the same pid %s", apiPID(PrefixPlaylist, kept.PID), list)
	}
	if kept.Kind != model.PlaylistSmart || kept.Rule == nil {
		t.Errorf("handed-over playlist is %s with rule %v, want it still smart", kept.Kind, kept.Rule)
	}
	if after := memberPIDs(t, ctx, svc, reader, list); !slices.Equal(after, before) {
		t.Errorf("the reader sees %v after the handover, want %v", after, before)
	}
	if _, err := svc.ResolveShare(ctx, link); KindOf(err) != KindNotFound {
		t.Errorf("the member's link after the deletion = %v, want not found", err)
	}
}

// A deleted member's public links end with the account, on a playlist
// that is handed over as on anything else they shared, and the entry for
// the deletion counts them: the ones that were serving, not one the member
// had pulled.
func TestADeletedMembersPublicLinksEndWithTheAccount(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)[:2]
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	list := playlistAs(t, ctx, svc, samCtx, "Road trip", "shared", pids)
	link := shareOf(t, ctx, svc, samCtx, list)
	// A link the member pulled stays pulled.
	revoked := shareOf(t, ctx, svc, samCtx, list)
	if err := svc.RevokeShare(ctx, samCtx, "sh-"+revoked); err != nil {
		t.Fatal(err)
	}
	// A link to something that is not a playlist ends the same way.
	other := shareOf(t, ctx, svc, samCtx, pids[0])
	// One that has run out was not serving either.
	expired, err := svc.CreateShare(ctx, samCtx, pids[1], time.Hour, false, 0)
	if err != nil {
		t.Fatal(err)
	}
	_, expiredID, _ := parseAPIPID(expired.ID)
	if _, err := svc.db.Writer().ExecContext(ctx,
		`UPDATE shares SET expires_at_ns = 1 WHERE id = ?`, string(expiredID)); err != nil {
		t.Fatal(err)
	}

	got, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{})
	if err != nil {
		t.Fatal(err)
	}

	if got.PlaylistsTransferred != 1 || got.LinksEnded != 2 {
		t.Errorf("result = %+v, want the playlist handed over and the two serving links ended", got)
	}
	for name, id := range map[string]string{
		"the handed-over playlist's link": link, "a pulled link": revoked, "a track's link": other, "an expired link": string(expiredID),
	} {
		if _, err := svc.ResolveShare(ctx, id); KindOf(err) != KindNotFound {
			t.Errorf("%s after the deletion = %v, want not found", name, err)
		}
		if _, err := svc.db.ShareByID(ctx, id); !errors.Is(err, wdb.ErrNotFound) {
			t.Errorf("%s: its row after the deletion = %v, want it gone with the account", name, err)
		}
	}
	// The playlist itself is the administrator's, whose own reach it is
	// served under from now on.
	if pl, err := svc.PlaylistByPID(ctx, admin, list); err != nil || !pl.IsOwner {
		t.Errorf("the handed-over playlist = %+v (%v), want the administrator's", pl, err)
	}
}

// A link answers for what its member could reach: a restricted member's
// link on a list of the whole catalog served nothing before the deletion,
// and the administrator, who reaches everything, does not take it over.
func TestAHandedOverListDoesNotServeWhatItsMemberCouldNotReach(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	sam, err := svc.CreateAccount(ctx, AccountCreate{Username: "sam", Password: "correct-horse", AccessMode: "granted"})
	if err != nil {
		t.Fatal(err)
	}
	samCtx, err := svc.UserCtx(ctx, sam.User)
	if err != nil {
		t.Fatal(err)
	}
	list := smartPlaylist(t, ctx, svc, samCtx, "Everything", "shared", SmartRule{Root: allMusic()})
	link := shareOf(t, ctx, svc, samCtx, list)
	if _, err := svc.ResolveShare(ctx, link); KindOf(err) != KindNotFound {
		t.Fatalf("the link before the deletion = %v, want it to serve nothing", err)
	}

	if _, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{}); err != nil {
		t.Fatal(err)
	}

	if pub, err := svc.ResolveShare(ctx, link); KindOf(err) != KindNotFound {
		t.Errorf("the link after the deletion = %v (%+v), want it to serve nothing still", err, pub)
	}
	if pl, err := svc.PlaylistByPID(ctx, admin, list); err != nil || pl.Kind != "smart" || !pl.IsOwner {
		t.Errorf("the handed-over playlist = %+v (%v), want the administrator's smart list", pl, err)
	}
}

// A link is never moved to another account, not even while a deletion is
// stopped half-way and the playlist has already changed hands.
func TestAHandoverLeavesTheLinksWhereTheyAre(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)[:2]
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	first := playlistAs(t, ctx, svc, samCtx, "First", "shared", pids)
	second := playlistAs(t, ctx, svc, samCtx, "Second", "shared", pids)
	links := map[string]string{first: shareOf(t, ctx, svc, samCtx, first), second: shareOf(t, ctx, svc, samCtx, second)}
	starts := 0
	svc.handoverHook = func(stage string, _ *model.Playlist) error {
		if stage == "start" {
			starts++
			if starts == 2 {
				return errors.New("the catalog went away")
			}
		}
		return nil
	}

	got, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{})
	if err == nil || got.PlaylistsTransferred != 1 {
		t.Fatalf("the stopped deletion = %+v (%v), want one list handed over and an error", got, err)
	}

	for playlist, link := range links {
		row, err := svc.db.ShareByID(ctx, link)
		if err != nil || row.UserID != sam.User.ID || row.TargetPID != playlist {
			t.Errorf("the link on %s = %+v (%v), want it still sam's, on the same list", playlist, row, err)
		}
		if _, err := svc.ResolveShare(ctx, link); KindOf(err) != KindNotFound {
			t.Errorf("the link on %s while sam is disabled = %v, want not found", playlist, err)
		}
	}
}

// A shared smart list over a private playlist of the member's loses its
// source when the account goes, so it goes over as the tracks it held
// rather than as a rule that would match nothing.
func TestDeletingAnAccountFreezesAListThatNamesAPlaylistThatGoes(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	_, reader := playlistMember(t, ctx, svc, "reader")
	source := playlistAs(t, ctx, svc, samCtx, "Source", "private", pids[:2])
	list := smartPlaylist(t, ctx, svc, samCtx, "From the source", "shared", SmartRule{
		Root: RuleNode{Type: "condition", Field: "playlist", Op: "is", Value: source},
	})
	before := memberPIDs(t, ctx, svc, reader, list)
	if len(before) != 2 {
		t.Fatalf("the reader sees %v before the handover, want the source's two tracks", before)
	}

	if _, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{}); err != nil {
		t.Fatal(err)
	}

	if catalogHas(ctx, svc, source) {
		t.Error("the private source survived")
	}
	kept := ownedNamed(t, ctx, svc, admin.CatalogPID, "From the source")
	if kept.Kind != model.PlaylistStatic {
		t.Errorf("handed-over playlist is %s, want a fixed list", kept.Kind)
	}
	if after := memberPIDs(t, ctx, svc, reader, apiPID(PrefixPlaylist, kept.PID)); !slices.Equal(after, before) {
		t.Errorf("the reader sees %v after the handover, want %v", after, before)
	}
}

// An uploaded cover is the member's choice of picture for the list, and
// goes to the new list with it; a generated one is drawn again from the
// same tracks.
func TestDeletingAnAccountCarriesTheCoverOfAFrozenList(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	if _, err := svc.SetStar(ctx, samCtx, pids[0], true, nil); err != nil {
		t.Fatal(err)
	}
	list := smartPlaylist(t, ctx, svc, samCtx, "Pictured", "shared", SmartRule{
		Root: RuleNode{Type: "condition", Field: "starred", Op: "is", Value: "true"},
	})
	custom := coverPNG(t, 200)
	if _, err := svc.SetEntityArtwork(ctx, samCtx, "playlist", list, "", custom, false); err != nil {
		t.Fatal(err)
	}

	if _, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{}); err != nil {
		t.Fatal(err)
	}

	kept := ownedNamed(t, ctx, svc, admin.CatalogPID, "Pictured")
	handed := apiPID(PrefixPlaylist, kept.PID)
	if got := playlistArt(t, ctx, svc, admin, handed); !bytes.Equal(got.Bytes, custom) {
		t.Error("the uploaded cover did not go with the list")
	}
	rec, err := svc.db.PlaylistCoverFor(ctx, string(kept.PID))
	if err != nil || rec.Origin != wdb.CoverCustom {
		t.Errorf("cover provenance = %+v (%v), want it recorded as an upload", rec, err)
	}
	if _, err := svc.db.PlaylistCoverFor(ctx, string(mustBare(t, list))); err == nil {
		t.Error("the old list's cover provenance was left behind")
	}
}

func mustBare(t *testing.T, apiPID string) model.PID {
	t.Helper()
	_, bare, ok := parseAPIPID(apiPID)
	if !ok {
		t.Fatalf("not a pid: %q", apiPID)
	}
	return bare
}

// An order by the member's ratings decides which tracks a limit keeps, so
// a list that only sorts on them reads the member's state as surely as
// one that filters on it.
func TestDeletingAnAccountFixesAListThatOnlyOrdersByTheirRatings(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	_, reader := playlistMember(t, ctx, svc, "reader")
	rate := func(uc *UserCtx, pid string, stars int) {
		t.Helper()
		if _, err := svc.SetRating(ctx, uc, pid, &stars, nil); err != nil {
			t.Fatal(err)
		}
	}
	rate(samCtx, pids[2], 100)
	rate(samCtx, pids[1], 80)
	// The administrator rates another track highest of all.
	rate(admin, pids[0], 100)
	list := smartPlaylist(t, ctx, svc, samCtx, "Sam's best", "shared", SmartRule{
		Root:  allMusic(),
		Sorts: []RuleSort{{Field: "rating", Desc: true}},
		Limit: 2,
	})
	before := memberPIDs(t, ctx, svc, reader, list)
	if !slices.Equal(before, []string{pids[2], pids[1]}) {
		t.Fatalf("the reader sees %v before the handover, want sam's two best %v", before, []string{pids[2], pids[1]})
	}

	got, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{})
	if err != nil {
		t.Fatal(err)
	}
	if got.PlaylistsFixed != 1 {
		t.Errorf("result = %+v, want the list counted as handed over fixed", got)
	}
	kept := ownedNamed(t, ctx, svc, admin.CatalogPID, "Sam's best")
	if after := memberPIDs(t, ctx, svc, reader, apiPID(PrefixPlaylist, kept.PID)); !slices.Equal(after, before) {
		t.Errorf("the reader sees %v after the handover, want %v", after, before)
	}
}

// The detection reads the rule the way the engine does: any depth and
// polarity, a sort as well as a condition, whichever spelling the rule
// holds, and nothing that is only the catalog.
func TestRuleReadsUserState(t *testing.T) {
	t.Parallel()
	is := func(field string) query.Cond { return query.Cond{Field: field, Op: query.OpIs, Value: int64(1)} }
	for name, tc := range map[string]struct {
		q    query.Query
		want bool
	}{
		"nothing at all":       {query.Query{}, false},
		"a catalog field":      {query.Query{Where: is("title")}, false},
		"a custom tag":         {query.Query{Where: is("tag.mood")}, false},
		"an alias of a field":  {query.Query{Where: is("created_at")}, false},
		"a catalog sort":       {query.Query{Where: is("title"), Sorts: []query.Sort{{Field: "year"}}}, false},
		"a playlist condition": {query.Query{Where: is("playlist_pid")}, false},
		"starred":              {query.Query{Where: is("starred")}, true},
		"starred at":           {query.Query{Where: is("starred_at")}, true},
		"rating":               {query.Query{Where: is("rating")}, true},
		"play count":           {query.Query{Where: is("play_count")}, true},
		"played":               {query.Query{Where: is("played")}, true},
		"finished":             {query.Query{Where: is("finished")}, true},
		"last played":          {query.Query{Where: is("last_played")}, true},
		"position":             {query.Query{Where: is("position_ms")}, true},
		"last progress":        {query.Query{Where: is("last_progress")}, true},
		"under an and, or and not": {query.Query{Where: query.And{Nodes: []query.Node{
			is("title"), query.Or{Nodes: []query.Node{is("year"), query.Not{Node: is("rating")}}},
		}}}, true},
		"only in a sort": {query.Query{Where: is("title"), Sorts: []query.Sort{{Field: "play_count", Desc: true}}}, true},
	} {
		if got := ruleReadsUserState(tc.q); got != tc.want {
			t.Errorf("%s: ruleReadsUserState = %v, want %v", name, got, tc.want)
		}
	}
}

// The rule vocabulary and the detection are two lists of one thing; this
// is what keeps a field added to one from being missed by the other.
func TestEveryUserStateFieldOfTheVocabularyIsDetected(t *testing.T) {
	t.Parallel()
	for _, spec := range ruleFieldSpecs {
		q := query.Query{Where: query.Cond{Field: spec.engine, Op: query.OpIs, Value: int64(1)}}
		if got := ruleReadsUserState(q); got != spec.userState {
			t.Errorf("field %s: detected = %v, vocabulary says user state = %v", spec.api, got, spec.userState)
		}
	}
}

// A rule from another tool can name a playlist a different way; the
// private playlists that go with the account are matched by pid however
// the value arrives.
func TestRuleNamesPlaylistIn(t *testing.T) {
	t.Parallel()
	gone := map[model.PID]bool{"01JZX5N8QW3F4V9T2B7KDAAAAA": true}
	named := func(v any) query.Query {
		return query.Query{Where: query.Cond{Field: "playlist_pid", Op: query.OpIs, Value: v}}
	}
	for name, tc := range map[string]struct {
		q    query.Query
		want bool
	}{
		"a pid read back as text":  {named("01JZX5N8QW3F4V9T2B7KDAAAAA"), true},
		"a pid built in memory":    {named(model.PID("01JZX5N8QW3F4V9T2B7KDAAAAA")), true},
		"a pid in the other case":  {named("01jzx5n8qw3f4v9t2b7kdaaaaa"), true},
		"a playlist that stays":    {named("01JZX5N8QW3F4V9T2B7KDBBBBB"), false},
		"another field with a pid": {query.Query{Where: query.Cond{Field: "title", Op: query.OpIs, Value: "01JZX5N8QW3F4V9T2B7KDAAAAA"}}, false},
		"no condition":             {query.Query{}, false},
	} {
		if got := ruleNamesPlaylistIn(tc.q, gone); got != tc.want {
			t.Errorf("%s: ruleNamesPlaylistIn = %v, want %v", name, got, tc.want)
		}
	}
}

// Handing a list over as a fixed one is all or nothing. A failure at the
// last step leaves the old list where it was, with its link and its pin,
// and no copy of it; the retry then does it once.
func TestAHandoverThatFailsLeavesTheOldListAndItsReferences(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	_, reader := playlistMember(t, ctx, svc, "reader")
	if _, err := svc.SetStar(ctx, samCtx, pids[0], true, nil); err != nil {
		t.Fatal(err)
	}
	list := smartPlaylist(t, ctx, svc, samCtx, "Sam's favourites", "shared", SmartRule{
		Root: RuleNode{Type: "condition", Field: "starred", Op: "is", Value: "true"},
	})
	link := shareOf(t, ctx, svc, samCtx, list)
	if _, err := svc.PutPrefs(ctx, reader, Prefs{Pinned: []string{list}}); err != nil {
		t.Fatal(err)
	}
	failing := errors.New("the catalog went away")
	svc.handoverHook = func(stage string, _ *model.Playlist) error {
		if stage == "swap" {
			return failing
		}
		return nil
	}

	got, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{})
	if !errors.Is(err, failing) {
		t.Fatalf("err = %v, want the failure", err)
	}
	if got.PlaylistsTransferred != 0 || got.PlaylistsFixed != 0 || !got.Disabled {
		t.Errorf("result = %+v, want nothing handed over and the account disabled", got)
	}
	acct, err := svc.Account(ctx, sam.User.ID)
	if err != nil || !acct.User.Disabled {
		t.Fatalf("the account after the failure = %+v (%v), want it there and disabled", acct, err)
	}
	pl, err := svc.lib.Playlists().Get(ctx, mustBare(t, list))
	if err != nil || pl.Kind != model.PlaylistSmart || string(pl.OwnerPID) != sam.User.WaxbinUserPID {
		t.Errorf("the old list = %+v (%v), want it still sam's smart list", pl, err)
	}
	if owned := ownedBy(t, ctx, svc, admin.CatalogPID); slices.Contains(owned, "Sam's favourites") {
		t.Errorf("the administrator was left a copy: %v", owned)
	}
	row, err := svc.db.ShareByID(ctx, link)
	if err != nil || row.UserID != sam.User.ID || row.TargetPID != list {
		t.Errorf("the link = %+v (%v), want it untouched on sam's list", row, err)
	}
	if prefs, err := svc.Prefs(ctx, reader); err != nil || !slices.Equal(prefs.Pinned, []string{list}) {
		t.Errorf("the reader's pins = %v (%v), want the old list", prefs.Pinned, err)
	}

	svc.handoverHook = nil
	got, err = svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{})
	if err != nil {
		t.Fatalf("the retry: %v", err)
	}
	if got.PlaylistsFixed != 1 || got.Disabled {
		t.Errorf("the retry = %+v, want the one fixed list and no second disabling", got)
	}
	handed := ownedNamed(t, ctx, svc, admin.CatalogPID, "Sam's favourites")
	if _, err := svc.ResolveShare(ctx, link); KindOf(err) != KindNotFound {
		t.Errorf("the member's link after the retry = %v, want it ended with the account", err)
	}
	if prefs, _ := svc.Prefs(ctx, reader); !slices.Equal(prefs.Pinned, []string{apiPID(PrefixPlaylist, handed.PID)}) {
		t.Errorf("the reader's pins after the retry = %v, want the fixed list", prefs.Pinned)
	}
}

// The account is out of play before any of its playlists is touched, so
// it can make no new ones while they are settled, and a deletion that
// stops part-way says what it had done and leaves an account a retry can
// finish.
func TestADeletionThatStopsPartWayLeavesADisabledAccountAndSaysWhatWasDone(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)[:2]
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	playlistAs(t, ctx, svc, samCtx, "First", "shared", pids)
	playlistAs(t, ctx, svc, samCtx, "Second", "shared", pids)
	private := playlistAs(t, ctx, svc, samCtx, "Private", "private", pids)

	var disabledAtStart []bool
	starts := 0
	svc.handoverHook = func(stage string, _ *model.Playlist) error {
		if stage != "start" {
			return nil
		}
		starts++
		acct, err := svc.Account(ctx, sam.User.ID)
		disabledAtStart = append(disabledAtStart, err == nil && acct.User.Disabled)
		if starts == 2 {
			return errors.New("the catalog went away")
		}
		return nil
	}
	got, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{})
	if err == nil {
		t.Fatal("the deletion went through a failing step")
	}
	if !slices.Equal(disabledAtStart, []bool{true, true}) {
		t.Errorf("the account was disabled at each handover = %v, want it disabled before the first", disabledAtStart)
	}
	if got.PlaylistsTransferred != 1 || got.PlaylistsDeleted != 0 || got.TransferredTo != "admin" || !got.Disabled {
		t.Errorf("result = %+v, want the one list handed over, none deleted, and the account disabled", got)
	}
	if !catalogHas(ctx, svc, private) {
		t.Error("a private playlist was deleted before the shared ones were settled")
	}

	svc.handoverHook = nil
	got, err = svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{})
	if err != nil {
		t.Fatalf("the retry: %v", err)
	}
	if got.PlaylistsTransferred != 1 || got.Disabled {
		t.Errorf("the retry = %+v, want the one list left to hand over", got)
	}
	if catalogHas(ctx, svc, private) {
		t.Error("the retry left the private playlist")
	}
	if _, err := svc.Account(ctx, sam.User.ID); KindOf(err) != KindNotFound {
		t.Errorf("the account after the retry = %v, want it gone", err)
	}
}

// The refusal for the last administrator comes before anything of the
// account's or the actor's is touched.
func TestDeletingTheLastOtherAdministratorChangesNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)[:1]
	other, err := svc.CreateAccount(ctx, AccountCreate{Username: "second", Password: "correct-horse", Roles: []string{"admin"}})
	if err != nil {
		t.Fatal(err)
	}
	otherCtx, err := svc.UserCtx(ctx, other.User)
	if err != nil {
		t.Fatal(err)
	}
	theirs := playlistAs(t, ctx, svc, otherCtx, "Theirs", "shared", pids)
	mine := playlistAs(t, ctx, svc, admin, "Mine", "shared", pids)
	// The acting administrator is demoted while the request is in flight:
	// the other account is now the only one left.
	if _, err := svc.UpdateAccount(ctx, admin.ID, AccountUpdate{Roles: []string{"user"}}); err != nil {
		t.Fatal(err)
	}

	got, err := svc.DeleteAccount(ctx, admin, other.User.ID, AccountDeletion{})
	if KindOf(err) != KindConflict {
		t.Fatalf("err = %v, want a conflict", err)
	}
	if !reflect.DeepEqual(got, AccountDeleted{}) {
		t.Errorf("result = %+v, want nothing done", got)
	}
	acct, err := svc.Account(ctx, other.User.ID)
	if err != nil || acct.User.Disabled {
		t.Errorf("the other administrator = %+v (%v), want them there and enabled", acct, err)
	}
	for _, kept := range []string{theirs, mine} {
		if pl, err := svc.lib.Playlists().Get(ctx, mustBare(t, kept)); err != nil || pl.Visibility != model.VisibilityShared {
			t.Errorf("playlist %s = %+v (%v), want it untouched", kept, pl, err)
		}
	}
	if owned := ownedBy(t, ctx, svc, other.User.WaxbinUserPID); !slices.Contains(owned, "Theirs") {
		t.Errorf("the refused account owns %v, want its playlist kept", owned)
	}
}

// A playlist someone deleted between the listing and the settling has
// nothing left to settle, and does not stop the account going.
func TestAPlaylistDeletedWhileTheAccountIsSettledDoesNotStopTheDeletion(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)[:2]
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	gone := playlistAs(t, ctx, svc, samCtx, "Gone", "shared", pids)
	goneToo := playlistAs(t, ctx, svc, samCtx, "Gone too", "private", pids)
	kept := playlistAs(t, ctx, svc, samCtx, "Kept", "shared", pids)

	victim, err := svc.db.UserByID(ctx, sam.User.ID)
	if err != nil {
		t.Fatal(err)
	}
	taker, err := svc.db.UserByID(ctx, admin.ID)
	if err != nil {
		t.Fatal(err)
	}
	owned, err := svc.ownedPlaylists(ctx, victim)
	if err != nil {
		t.Fatal(err)
	}
	// The administrator deletes one, and the member's own delete lands on
	// the other, after the listing.
	if err := svc.DeletePlaylist(ctx, admin, gone); err != nil {
		t.Fatal(err)
	}
	if err := svc.DeletePlaylist(ctx, samCtx, goneToo); err != nil {
		t.Fatal(err)
	}

	got, err := svc.settlePlaylists(ctx, victim, owned, taker)
	if err != nil {
		t.Fatalf("settling with two playlists already gone: %v", err)
	}
	if got.PlaylistsTransferred != 1 {
		t.Errorf("result = %+v, want only the one that was still there handed over", got)
	}
	if pl, err := svc.PlaylistByPID(ctx, admin, kept); err != nil || !pl.IsOwner {
		t.Errorf("the playlist that stayed = %+v (%v), want it the administrator's", pl, err)
	}
}

// An account the catalog has no user for cannot own playlists, which is
// found out before anything is changed rather than as a not-found halfway.
func TestAccountDeletionRefusesARecipientTheCatalogHasNoUserFor(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, admin)[:1]
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	pat, _ := playlistMember(t, ctx, svc, "pat")
	roadTrip := playlistAs(t, ctx, svc, samCtx, "Road trip", "shared", pids)
	svc.catalogUsersMu.Lock()
	svc.catalogUsers = map[string]model.PID{pat.User.ID: "01JZX5N8QW3F4V9T2B7KDXXXXX"}
	svc.catalogUsersMu.Unlock()

	got, err := svc.DeleteAccount(ctx, admin, sam.User.ID, AccountDeletion{TransferTo: pat.User.ID})
	if KindOf(err) != KindInvalid {
		t.Fatalf("err = %v (kind %q), want invalid", err, KindOf(err))
	}
	if !reflect.DeepEqual(got, AccountDeleted{}) {
		t.Errorf("result = %+v, want nothing done", got)
	}
	acct, err := svc.Account(ctx, sam.User.ID)
	if err != nil || acct.User.Disabled {
		t.Errorf("the account = %+v (%v), want it there and enabled", acct, err)
	}
	if pl, err := svc.PlaylistByPID(ctx, samCtx, roadTrip); err != nil || !pl.IsOwner {
		t.Errorf("the playlist = %+v (%v), want it untouched", pl, err)
	}
}

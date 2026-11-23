package service

import (
	"context"
	"errors"
	"slices"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/oklog/ulid/v2"
)

// catalogCursorNow is the cursor a client's pull is handed once the feed
// holds still: where a returning client stands.
func catalogCursorNow(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) string {
	t.Helper()
	quietChanges(t, svc)
	feedCaughtUp(t, ctx, svc)
	page, err := svc.SyncCatalogSnapshot(ctx, uc, "", 1)
	if err != nil || page.NextSince == "" {
		t.Fatalf("the snapshot handed no cursor: %+v (%v)", page, err)
	}
	return page.NextSince
}

// changesSince is what a subscribe presenting the cursor is told:
// whether it names anything, and the cursor it is handed to present next.
func changesSince(t *testing.T, svc *Library, userID, cursor string) (pids []string, unnamed bool, since string) {
	t.Helper()
	pids, unnamed, _, _, _, pos := svc.CatalogChangesSince(userID, cursor)
	since, _, _ = svc.CatalogFrameFor(userID, pos, nil)
	return pids, unnamed, since
}

// A client that subscribes behind a change is told its name, by the
// rules a live frame names it by: a track's cover names the track and
// its album, an album's names the album and its tracks. One at the head
// is told nothing, and the cursor each answer hands on is at the head.
func TestASubscribeBehindAChangeIsToldItsName(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	track, bare := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	view, err := svc.lib.Get(ctx, bare)
	if err != nil || view.AlbumPID == "" {
		t.Fatalf("the fixture track has no album: %+v (%v)", view, err)
	}
	album := apiPID(PrefixAlbum, view.AlbumPID)
	tracks, err := svc.lib.Query(ctx, visibleItems().Where("album_pid", query.OpIs, string(view.AlbumPID)).Build(), "")
	if err != nil || len(tracks) < 2 {
		t.Fatalf("the fixture album has %d tracks (%v), want several", len(tracks), err)
	}

	before := catalogCursorNow(t, ctx, svc, uc)
	if pids, unnamed, _ := changesSince(t, svc, uc.ID, before); unnamed || len(pids) != 0 {
		t.Fatalf("at the head: %v (unnamed %v), want nothing named and nothing unnamed", pids, unnamed)
	}
	if _, err := svc.Editor.SetItemArtwork(ctx, uc, track, "front", coverPNG(t, 40), false, false); err != nil {
		t.Fatal(err)
	}
	pids, unnamed, after := changesSince(t, svc, uc.ID, before)
	if unnamed || !slices.Equal(pids, sortedPIDs(album, track)) {
		t.Fatalf("behind a track's cover: %v (unnamed %v), want the track %s and its album %s", pids, unnamed, track, album)
	}
	if pids, unnamed, _ := changesSince(t, svc, uc.ID, after); unnamed || len(pids) != 0 {
		t.Fatalf("presenting the cursor that answer handed on: %v (unnamed %v), want nothing", pids, unnamed)
	}

	before = catalogCursorNow(t, ctx, svc, uc)
	if _, err := svc.Editor.SetEntityArtwork(ctx, uc, "album", album, "front", coverPNG(t, 60), false); err != nil {
		t.Fatal(err)
	}
	pids, unnamed, _ = changesSince(t, svc, uc.ID, before)
	if unnamed || !slices.Contains(pids, album) {
		t.Fatalf("behind an album's cover: %v (unnamed %v), want the album %s", pids, unnamed, album)
	}
	for _, tr := range tracks {
		if !slices.Contains(pids, itemAPIPID(tr)) {
			t.Fatalf("behind an album's cover: %v, want its track %s beside it", pids, itemAPIPID(tr))
		}
	}
}

// standInLog is a change log of rows after a cursor's own, read a page
// at a time as the facade reads it, counting the rows it handed out.
type standInLog struct {
	rows   []model.Change
	page   int
	handed int
}

func (s *standInLog) changes(_ context.Context, since int64) ([]model.Change, error) {
	var out []model.Change
	for _, ch := range s.rows {
		if ch.Seq > since && len(out) < s.page {
			out = append(out, ch)
		}
	}
	s.handed += len(out)
	return out, nil
}

// standInBehind builds a log that stands on a row the cursor names and
// then holds the rows given, numbered after it.
func standInBehind(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, rows []model.Change) (*standInLog, string) {
	t.Helper()
	return standInBehindAt(t, ctx, svc, uc, 1_000, rows)
}

// standInBehindAt is standInBehind with the cursor's row logged at ts.
func standInBehindAt(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, ts int64, rows []model.Change) (*standInLog, string) {
	t.Helper()
	epoch, err := svc.Grants.grantEpoch(ctx, uc.ID)
	if err != nil {
		t.Fatal(err)
	}
	const at = 1 << 30
	log := &standInLog{page: 10, rows: []model.Change{{Seq: at, TS: ts, EntityType: "genre"}}}
	for i, ch := range rows {
		ch.Seq, ch.TS = at+int64(i)+1, ts+int64(i)+1
		log.rows = append(log.rows, ch)
	}
	return log, encodeCatalogCursor(feedGen(svc), epoch, at, ts)
}

// A client behind more entities than a frame names is told they went
// unnamed, and the walk stops at the one past the bound: no more of the
// log is read, and nothing is read for the names it will not send. One
// behind exactly a frame's worth is told every one.
func TestASubscribeBehindMoreThanAFrameNamesIsUnnamed(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	quietChanges(t, svc)
	noReads := func(context.Context, []model.PID) ([]*model.ItemView, error) {
		t.Error("the walk read items it had no names for")
		return nil, nil
	}
	noMembers := func(context.Context, []model.PID, []model.PID) ([]*model.ItemView, error) {
		t.Error("the walk read members it had no names for")
		return nil, nil
	}
	artists := func(n int) []model.Change {
		out := make([]model.Change, n)
		for i := range out {
			out[i] = historyRow("artist", model.OpUpdate)
		}
		return out
	}

	log, cursor := standInBehind(t, ctx, svc, uc, artists(maxCatalogChangePIDs))
	pids, unnamed, _, _, _, _ := svc.catalogChangesSince(uc.ID, cursor, log.changes, noReads, noMembers)
	if unnamed || len(pids) != maxCatalogChangePIDs {
		t.Fatalf("behind a frame's worth: %d pids (unnamed %v), want all %d", len(pids), unnamed, maxCatalogChangePIDs)
	}

	log, cursor = standInBehind(t, ctx, svc, uc, artists(200))
	pids, unnamed, _, _, _, _ = svc.catalogChangesSince(uc.ID, cursor, log.changes, noReads, noMembers)
	if !unnamed || len(pids) != 0 {
		t.Fatalf("behind 200 entities: %d pids (unnamed %v), want unnamed", len(pids), unnamed)
	}
	// The cursor's own row, then pages of ten up to the one holding the
	// sixty-fifth entity.
	if want := 1 + 60 + 10; log.handed > want {
		t.Fatalf("the walk read %d rows, want it to stop by the page holding entity %d (%d rows)", log.handed, maxCatalogChangePIDs+1, want)
	}
}

// A subscribe is answered with the names behind it whoever presents the
// cursor, and the frame built from them tells the account what it may be
// told: an account granted no library none of a track and its album,
// and an artist's row, which nothing beside it decides, as unnamed. An
// administrator is told them all.
func TestARestrictedAccountBehindAChangeIsToldWhatItSees(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	acct, err := svc.Identity.CreateAccount(ctx, AccountCreate{
		Username: "reader", Password: "correct-horse", AccessMode: "granted",
	})
	if err != nil {
		t.Fatal(err)
	}
	reader, err := svc.Grants.UserCtxByID(ctx, acct.User.ID)
	if err != nil {
		t.Fatal(err)
	}
	track, bare := fixtureTrackPID(t, ctx, svc, admin, "Amber Waves")
	view, err := svc.lib.Get(ctx, bare)
	if err != nil || view.AlbumPID == "" {
		t.Fatalf("the fixture track has no album: %+v (%v)", view, err)
	}
	behind := sortedPIDs(track, apiPID(PrefixAlbum, view.AlbumPID))

	before := catalogCursorNow(t, ctx, svc, reader)
	if pids, unnamed, _ := changesSince(t, svc, reader.ID, before); unnamed || len(pids) != 0 {
		t.Fatalf("at the head: %v (unnamed %v), want nothing", pids, unnamed)
	}
	if _, err := svc.Editor.SetItemArtwork(ctx, admin, track, "front", coverPNG(t, 40), false, false); err != nil {
		t.Fatal(err)
	}
	pids, unnamed, _ := changesSince(t, svc, reader.ID, before)
	if unnamed || !slices.Equal(pids, behind) {
		t.Fatalf("behind a change: %v (unnamed %v), want the track and its album %v", pids, unnamed, behind)
	}
	if _, named, unnamed := svc.CatalogFrameFor(reader.ID, "", pids); unnamed || len(named) != 0 {
		t.Fatalf("the reader's frame: %v (unnamed %v), want nothing named", named, unnamed)
	}
	if _, named, unnamed := svc.CatalogFrameFor(admin.ID, "", pids); unnamed || !slices.Equal(named, behind) {
		t.Fatalf("an administrator's frame: %v (unnamed %v), want %v", named, unnamed, behind)
	}

	log, cursor := standInBehind(t, ctx, svc, reader, []model.Change{
		historyRow("genre", model.OpUpdate), historyRow("artist", model.OpUpdate),
	})
	pids, unnamed, _, _, _, _ = svc.catalogChangesSince(reader.ID, cursor, log.changes,
		func(context.Context, []model.PID) ([]*model.ItemView, error) { return nil, nil },
		func(context.Context, []model.PID, []model.PID) ([]*model.ItemView, error) { return nil, nil })
	if unnamed || len(pids) != 1 {
		t.Fatalf("behind a stand-in artist: %v (unnamed %v), want the artist", pids, unnamed)
	}
	if _, named, unnamed := svc.CatalogFrameFor(reader.ID, "", pids); !unnamed || named != nil {
		t.Fatalf("the reader's frame for the artist: %v (unnamed %v), want unnamed", named, unnamed)
	}
}

// A cursor the catalog stream cannot serve is the one a mirror's pull is
// sent back to a snapshot for: one from another generation, one older
// than the log, and one that is not a cursor. Its subscribe is told the
// server cannot name what changed, never names, and is handed a cursor
// it can present next.
func TestAnUnservableCursorIsUnnamedAndHandedOn(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	track, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	unservable := func(what, cursor string, reset bool) {
		t.Helper()
		if _, err := svc.SyncCatalogDelta(ctx, uc, cursor, 10); err == nil || reset != errors.Is(err, ErrSyncReset) {
			t.Fatalf("%s: the mirror's pull answered %v, want it refused (sync-reset %v)", what, err, reset)
		}
		pids, unnamed, next := changesSince(t, svc, uc.ID, cursor)
		if !unnamed || len(pids) != 0 {
			t.Fatalf("%s: %v (unnamed %v), want unnamed", what, pids, unnamed)
		}
		if next == "" {
			t.Fatalf("%s: no cursor was handed on", what)
		}
		if pids, unnamed, _ := changesSince(t, svc, uc.ID, next); unnamed || len(pids) != 0 {
			t.Fatalf("%s: presenting the cursor handed on: %v (unnamed %v), want nothing", what, pids, unnamed)
		}
	}

	unservable("not a cursor", "not-a-cursor", false)

	old := catalogCursorNow(t, ctx, svc, uc)
	svc.mintCatalogGeneration(ctx)
	unservable("another generation", old, true)

	old = catalogCursorNow(t, ctx, svc, uc)
	for shade := range uint8(3) {
		if _, err := svc.Editor.SetItemArtwork(ctx, uc, track, "front", coverPNG(t, 40+shade), false, false); err != nil {
			t.Fatal(err)
		}
	}
	feedCaughtUp(t, ctx, svc)
	if _, err := svc.PruneCatalogChanges(ctx, 1); err != nil {
		t.Fatal(err)
	}
	unservable("older than the log", old, true)
}

// A live frame's position is a cursor the account can present: right
// after the frame, it is told nothing, and the delta serves it.
func TestALiveFramesPositionIsACursorAtItsChanges(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	track, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	quietChanges(t, svc)
	startOrder, _, _ := svc.CatalogPosition()

	if _, err := svc.Editor.SetItemArtwork(ctx, uc, track, "front", coverPNG(t, 40), false, false); err != nil {
		t.Fatal(err)
	}
	feedCaughtUp(t, ctx, svc)
	order, _, pos := svc.CatalogPosition()
	if order <= startOrder {
		t.Fatalf("the position did not move past the change: %d, then %d", startOrder, order)
	}
	if pids, unnamed, _ := svc.DrainCatalogChanges(); unnamed || !slices.Contains(pids, track) {
		t.Fatalf("the drain = %v (unnamed %v), want the track", pids, unnamed)
	}
	since, named, unnamed := svc.CatalogFrameFor(uc.ID, pos, []string{track})
	if since == "" || unnamed || !slices.Equal(named, []string{track}) {
		t.Fatalf("the frame for the account = %q (%v, unnamed %v), want a cursor and the track for an account that sees everything", since, named, unnamed)
	}
	// A frame with no names to decide on reads only the epoch.
	if bare, named, unnamed := svc.CatalogFrameFor(uc.ID, pos, nil); bare != since || unnamed || named != nil {
		t.Fatalf("the frame with no names = %q (%v, unnamed %v), want the same cursor and nothing decided", bare, named, unnamed)
	}
	if pids, unnamed, _ := changesSince(t, svc, uc.ID, since); unnamed || len(pids) != 0 {
		t.Fatalf("presenting the frame's position: %v (unnamed %v), want nothing", pids, unnamed)
	}
	if _, err := svc.SyncCatalogDelta(ctx, uc, since, 10); err != nil {
		t.Fatalf("the delta from the frame's position: %v", err)
	}
}

// A client that subscribes behind a show's cover set through the API is
// told the show and its episodes, as a live frame tells it.
func TestASubscribeBehindAShowsCoverNamesItsEpisodes(t *testing.T) {
	t.Parallel()
	f := openStubFeeds(t, &stubFeed{kind: model.SourceRSS, n: 3, prefix: "Episode"})
	show := f.subscribe(t, "https://feeds.example/small", "rss").Show.PID
	_, bare, _ := parseAPIPID(show)
	episodes, err := f.svc.lib.Query(f.ctx, visibleItems().Where("podcast_pid", query.OpIs, string(bare)).Build(), "")
	if err != nil || len(episodes) != 3 {
		t.Fatalf("the show has %d episodes (%v), want 3", len(episodes), err)
	}
	before := catalogCursorNow(t, f.ctx, f.svc, f.uc)
	if _, err := f.svc.Editor.SetEntityArtwork(f.ctx, f.uc, "podcast", show, "front", coverPNG(t, 40), false); err != nil {
		t.Fatal(err)
	}
	pids, unnamed, _ := changesSince(t, f.svc, f.uc.ID, before)
	if unnamed || !slices.Contains(pids, show) {
		t.Fatalf("behind the show's cover: %v (unnamed %v), want the show %s", pids, unnamed, show)
	}
	for _, ep := range episodes {
		if !slices.Contains(pids, itemAPIPID(ep)) {
			t.Fatalf("behind the show's cover: %v, want its episode %s beside it", pids, itemAPIPID(ep))
		}
	}
}

// A show's row that is not its cover's names the show alone, as a live
// frame does; one the server cannot tell apart, from before what it
// remembers, names its episodes too.
func TestAShowsRowNamesItsEpisodesOnlyForACoverOrWhenUnsure(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	quietChanges(t, svc)
	show := model.PID(ulid.Make().String())
	episode := &model.ItemView{PID: model.PID(ulid.Make().String()), Kind: model.KindEpisode}
	walk := func(what string, ts int64) (asked []model.PID, pids []string, unnamed bool) {
		t.Helper()
		log, cursor := standInBehindAt(t, ctx, svc, uc, ts, []model.Change{{EntityType: "podcast", EntityPID: show, Op: model.OpUpdate}})
		pids, unnamed, _, _, _, _ = svc.catalogChangesSince(uc.ID, cursor, log.changes,
			func(context.Context, []model.PID) ([]*model.ItemView, error) { return nil, nil },
			func(_ context.Context, _, shows []model.PID) ([]*model.ItemView, error) {
				asked = shows
				return []*model.ItemView{episode}, nil
			})
		if unnamed {
			t.Fatalf("%s: the walk was unnamed", what)
		}
		return asked, pids, unnamed
	}
	now := time.Now().UnixNano()
	if asked, pids, _ := walk("a refresh", now); len(asked) != 0 || !slices.Equal(pids, []string{apiPID(PrefixPodcast, show)}) {
		t.Fatalf("a refresh: asked episodes of %v, named %v, want the show alone", asked, pids)
	}
	svc.feed.showCovers.note(show, now+1)
	if asked, pids, _ := walk("a cover", now); !slices.Equal(asked, []model.PID{show}) || !slices.Contains(pids, itemAPIPID(episode)) {
		t.Fatalf("a cover: asked episodes of %v, named %v, want the show's episodes", asked, pids)
	}
	if asked, pids, _ := walk("before the server remembers", 1); !slices.Equal(asked, []model.PID{show}) || !slices.Contains(pids, itemAPIPID(episode)) {
		t.Fatalf("unsure: asked episodes of %v, named %v, want the show's episodes", asked, pids)
	}
}

// A subscribe is told nothing changed only when no row after its cursor
// wakes the catalog: rows of a user's own state move the cursor and
// nothing else. A genre's row names nothing and leaves nothing unnamed,
// yet the catalog moved; an item's is named; a cursor the stream cannot
// serve is unnamed. None of those is told nothing changed.
func TestASubscribeIsToldNothingChangedOnlyWhenNoRowWakesTheCatalog(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	quietChanges(t, svc)
	item := &model.ItemView{PID: model.PID(ulid.Make().String()), Kind: model.KindTrack}
	answer := func(log *standInLog, cursor string) (pids []string, unnamed, unchanged bool) {
		t.Helper()
		pids, unnamed, unchanged, _, _, _ = svc.catalogChangesSince(uc.ID, cursor, log.changes,
			func(context.Context, []model.PID) ([]*model.ItemView, error) { return []*model.ItemView{item}, nil },
			func(context.Context, []model.PID, []model.PID) ([]*model.ItemView, error) { return nil, nil })
		return pids, unnamed, unchanged
	}
	userState := []model.Change{
		historyRow("play_state", model.OpUpdate), historyRow("bookmark", model.OpCreate),
		historyRow("entity_play_state", model.OpUpdate), historyRow("playlist", model.OpUpdate),
	}

	if pids, unnamed, unchanged := answer(standInBehind(t, ctx, svc, uc, nil)); !unchanged || unnamed || len(pids) != 0 {
		t.Fatalf("at the head: %v (unnamed %v, unchanged %v), want unchanged alone", pids, unnamed, unchanged)
	}
	if pids, unnamed, unchanged := answer(standInBehind(t, ctx, svc, uc, userState)); !unchanged || unnamed || len(pids) != 0 {
		t.Fatalf("behind user state alone: %v (unnamed %v, unchanged %v), want unchanged alone", pids, unnamed, unchanged)
	}
	genre := append(slices.Clone(userState), historyRow("genre", model.OpUpdate))
	if pids, unnamed, unchanged := answer(standInBehind(t, ctx, svc, uc, genre)); unchanged || unnamed || len(pids) != 0 {
		t.Fatalf("behind a genre's row: %v (unnamed %v, unchanged %v), want nothing named, nothing unnamed, not unchanged", pids, unnamed, unchanged)
	}
	itemRow := []model.Change{historyRow("play_state", model.OpUpdate), {EntityType: "item", EntityPID: item.PID, Op: model.OpUpdate}}
	if pids, unnamed, unchanged := answer(standInBehind(t, ctx, svc, uc, itemRow)); unchanged || unnamed || !slices.Equal(pids, []string{itemAPIPID(item)}) {
		t.Fatalf("behind an item's row: %v (unnamed %v, unchanged %v), want the item named", pids, unnamed, unchanged)
	}
	if pids, unnamed, unchanged := answer(&standInLog{page: 10}, "not-a-cursor"); unchanged || !unnamed || len(pids) != 0 {
		t.Fatalf("an unservable cursor: %v (unnamed %v, unchanged %v), want unnamed", pids, unnamed, unchanged)
	}
}

// A row of a kind that wakes the catalog counts though it carries no
// pid: nothing is named or unnamed, and the answer is not unchanged. A
// drain that fails after waking rows is unnamed, never unchanged.
func TestAWakingRowWithNoPIDOrAFailedDrainIsNotUnchanged(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	quietChanges(t, svc)
	noMembers := func(context.Context, []model.PID, []model.PID) ([]*model.ItemView, error) { return nil, nil }

	log, cursor := standInBehind(t, ctx, svc, uc, []model.Change{{EntityType: "item", Op: model.OpUpdate}})
	pids, unnamed, unchanged, _, _, _ := svc.catalogChangesSince(uc.ID, cursor, log.changes,
		func(context.Context, []model.PID) ([]*model.ItemView, error) { return nil, nil }, noMembers)
	if unchanged || unnamed || len(pids) != 0 {
		t.Fatalf("behind an item row with no pid: %v (unnamed %v, unchanged %v), want nothing named, nothing unnamed, not unchanged", pids, unnamed, unchanged)
	}

	log, cursor = standInBehind(t, ctx, svc, uc, []model.Change{historyRow("item", model.OpUpdate)})
	pids, unnamed, unchanged, _, _, _ = svc.catalogChangesSince(uc.ID, cursor, log.changes,
		func(context.Context, []model.PID) ([]*model.ItemView, error) { return nil, errors.New("read failed") }, noMembers)
	if unchanged || !unnamed || len(pids) != 0 {
		t.Fatalf("a drain that failed: %v (unnamed %v, unchanged %v), want unnamed", pids, unnamed, unchanged)
	}
}

// A show's cover stamped after the cursor whose row is not after it, the
// cursor's own row or one before, is a change the walk never meets as a
// row: the show and its episodes are named, and the answer is not
// unchanged. Named once: the cursor that answer hands on covers it.
func TestAShowCoverStampedAfterTheCursorIsNamedOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	quietChanges(t, svc)
	show := model.PID(ulid.Make().String())
	episode := &model.ItemView{PID: model.PID(ulid.Make().String()), Kind: model.KindEpisode}
	now := time.Now().UnixNano()
	log, cursor := standInBehindAt(t, ctx, svc, uc, now, nil)
	svc.feed.showCovers.note(show, now+1)
	var asked []model.PID
	answer := func(cursor string) (pids []string, unnamed, unchanged bool, since string) {
		t.Helper()
		asked = nil
		pids, unnamed, unchanged, _, _, pos := svc.catalogChangesSince(uc.ID, cursor, log.changes,
			func(context.Context, []model.PID) ([]*model.ItemView, error) { return nil, nil },
			func(_ context.Context, _, shows []model.PID) ([]*model.ItemView, error) {
				asked = shows
				return []*model.ItemView{episode}, nil
			})
		since, _, _ = svc.CatalogFrameFor(uc.ID, pos, nil)
		return pids, unnamed, unchanged, since
	}
	pids, unnamed, unchanged, since := answer(cursor)
	want := sortedPIDs(apiPID(PrefixPodcast, show), itemAPIPID(episode))
	if unchanged || unnamed || !slices.Equal(pids, want) || !slices.Equal(asked, []model.PID{show}) {
		t.Fatalf("behind a cover stamped after the cursor: %v (unnamed %v, unchanged %v, asked %v), want %v", pids, unnamed, unchanged, asked, want)
	}
	if pids, unnamed, unchanged, _ = answer(since); !unchanged || unnamed || len(pids) != 0 || len(asked) != 0 {
		t.Fatalf("presenting the cursor that answer handed on: %v (unnamed %v, unchanged %v, asked %v), want unchanged alone", pids, unnamed, unchanged, asked)
	}
}

// A show's cover moved while the walk runs is named though the walk met
// the show's row as a plain one and went on past the move's stamp, and
// so is one whose row the walk never meets: the answer's position covers
// both, so presenting it names neither again.
func TestAShowCoverMovedDuringTheWalkIsNamed(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	quietChanges(t, svc)
	met, unmet := model.PID(ulid.Make().String()), model.PID(ulid.Make().String())
	episodes := map[model.PID]*model.ItemView{
		met:   {PID: model.PID(ulid.Make().String()), Kind: model.KindEpisode},
		unmet: {PID: model.PID(ulid.Make().String()), Kind: model.KindEpisode},
	}
	now := time.Now().UnixNano()
	log, cursor := standInBehindAt(t, ctx, svc, uc, now, []model.Change{
		{EntityType: "podcast", EntityPID: met, Op: model.OpUpdate},
		historyRow("play_state", model.OpUpdate),
	})
	// The user's row commits after the cover's move.
	log.rows[2].TS = now + 10
	var moved sync.Once
	duringWalk := func(ctx context.Context, since int64) ([]model.Change, error) {
		moved.Do(func() {
			svc.feed.showCovers.note(met, now+5)
			svc.feed.showCovers.note(unmet, now+20)
		})
		return log.changes(ctx, since)
	}
	var asked []string
	var cover int64
	answer := func(cursor string, changes func(context.Context, int64) ([]model.Change, error)) (pids []string, unnamed, unchanged bool, since string) {
		t.Helper()
		asked = nil
		var pos string
		pids, unnamed, unchanged, _, cover, pos = svc.catalogChangesSince(uc.ID, cursor, changes,
			func(context.Context, []model.PID) ([]*model.ItemView, error) { return nil, nil },
			func(_ context.Context, _, shows []model.PID) ([]*model.ItemView, error) {
				asked = sortedPIDs(pidStrings(shows)...)
				var out []*model.ItemView
				for _, show := range shows {
					out = append(out, episodes[show])
				}
				return out, nil
			})
		since, _, _ = svc.CatalogFrameFor(uc.ID, pos, nil)
		return pids, unnamed, unchanged, since
	}
	pids, unnamed, unchanged, since := answer(cursor, duringWalk)
	want := sortedPIDs(apiPID(PrefixPodcast, met), itemAPIPID(episodes[met]), apiPID(PrefixPodcast, unmet), itemAPIPID(episodes[unmet]))
	if unchanged || unnamed || !slices.Equal(pids, want) || !slices.Equal(asked, sortedPIDs(string(met), string(unmet))) {
		t.Fatalf("covers moved during the walk: %v (unnamed %v, unchanged %v, asked %v), want %v", pids, unnamed, unchanged, asked, want)
	}
	if cover != now+20 {
		t.Fatalf("the answer covers the cover move stamped %d, want the newest, %d", cover, now+20)
	}
	if pids, unnamed, unchanged, _ = answer(since, log.changes); !unchanged || unnamed || len(pids) != 0 || len(asked) != 0 {
		t.Fatalf("presenting the cursor that answer handed on: %v (unnamed %v, unchanged %v, asked %v), want unchanged alone", pids, unnamed, unchanged, asked)
	}
}

// A cover moved during the walk and let go before it ends, by more moves
// than are remembered, cannot be told from the walk's plain rows: the
// answer is unnamed.
func TestAShowCoverLetGoDuringTheWalkIsUnnamed(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	quietChanges(t, svc)
	met, other := model.PID(ulid.Make().String()), model.PID(ulid.Make().String())
	now := time.Now().UnixNano()
	log, cursor := standInBehindAt(t, ctx, svc, uc, now, []model.Change{
		{EntityType: "podcast", EntityPID: met, Op: model.OpUpdate},
	})
	var moved sync.Once
	duringWalk := func(ctx context.Context, since int64) ([]model.Change, error) {
		moved.Do(func() {
			svc.feed.showCovers.note(met, now+5)
			for i := range maxCatalogChangePIDs + 1 {
				svc.feed.showCovers.note(other, now+6+int64(i))
			}
		})
		return log.changes(ctx, since)
	}
	pids, unnamed, unchanged, _, _, _ := svc.catalogChangesSince(uc.ID, cursor, duringWalk,
		func(context.Context, []model.PID) ([]*model.ItemView, error) { return nil, nil },
		func(context.Context, []model.PID, []model.PID) ([]*model.ItemView, error) { return nil, nil })
	if !unnamed || unchanged || len(pids) != 0 {
		t.Fatalf("a cover let go during the walk: %v (unnamed %v, unchanged %v), want unnamed", pids, unnamed, unchanged)
	}
}

// A show's cover a live frame named is not named again to a client that
// presents that frame's position, though the move was stamped after the
// row the position stands on; and the delta serves that position.
func TestAShowCoverALiveFrameNamedIsNotNamedAgain(t *testing.T) {
	t.Parallel()
	f := openStubFeeds(t, &stubFeed{kind: model.SourceRSS, n: 3, prefix: "Episode"})
	show := f.subscribe(t, "https://feeds.example/small", "rss").Show.PID
	quietChanges(t, f.svc)
	if _, err := f.svc.Editor.SetEntityArtwork(f.ctx, f.uc, "podcast", show, "front", coverPNG(t, 40), false); err != nil {
		t.Fatal(err)
	}
	feedCaughtUp(t, f.ctx, f.svc)
	_, _, pos := f.svc.CatalogPosition()
	if pids, unnamed, _ := f.svc.DrainCatalogChanges(); unnamed || !slices.Contains(pids, show) || len(pids) != 4 {
		t.Fatalf("the live frame = %v (unnamed %v), want the show and its three episodes", pids, unnamed)
	}
	since, _, _ := f.svc.CatalogFrameFor(f.uc.ID, pos, nil)
	if pids, unnamed, unchanged, _, _, _ := f.svc.CatalogChangesSince(f.uc.ID, since); !unchanged || unnamed || len(pids) != 0 {
		t.Fatalf("presenting the frame's position: %v (unnamed %v, unchanged %v), want unchanged alone", pids, unnamed, unchanged)
	}
	if _, err := f.svc.SyncCatalogDelta(f.ctx, f.uc, since, 10); err != nil {
		t.Fatalf("the delta from the frame's position: %v", err)
	}
}

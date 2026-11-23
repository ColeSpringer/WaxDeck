package service

import (
	"context"
	"errors"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	"github.com/oklog/ulid/v2"
)

// quietChanges waits out the fixture's own rows and forgets them, so what
// a test drains next is what it wrote.
func quietChanges(t *testing.T, svc *Library) {
	t.Helper()
	settleCatalogFeed(t, svc)
	svc.DrainCatalogChanges()
}

// changesAfter takes what the feed recorded once it is level with the log.
func changesAfter(t *testing.T, ctx context.Context, svc *Library) ([]string, bool) {
	t.Helper()
	feedCaughtUp(t, ctx, svc)
	pids, unnamed, _ := svc.DrainCatalogChanges()
	return pids, unnamed
}

// drainItems drains a set no parent row is in: nothing has members to
// read.
func drainItems(c *catalogChanges, views func([]model.PID) ([]*model.ItemView, error)) ([]string, bool, bool) {
	return c.drain(views, func(albums, shows []model.PID) ([]*model.ItemView, error) {
		panic("a drain with no album or show row read members")
	})
}

// historyRow is a change row the feed takes for one from before the boot:
// no position (Seq 0 leaves the feed's alone) and no time, so recording
// it is all advanceFeed does with it beyond the wakes.
func historyRow(entityType string, op model.ChangeOp) model.Change {
	return model.Change{EntityType: entityType, EntityPID: model.PID(ulid.Make().String()), Op: op}
}

// A track's new cover names the track and, from the read at the drain,
// its album: an album with no cover of its own draws a member's, and the
// write logs no album row.
func TestATracksNewArtNamesTheTrackAndItsAlbum(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	track, bare := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	view, err := svc.lib.Get(ctx, bare)
	if err != nil || view.AlbumPID == "" {
		t.Fatalf("the fixture track has no album: %+v (%v)", view, err)
	}
	album := apiPID(PrefixAlbum, view.AlbumPID)
	quietChanges(t, svc)
	head := feedTail(svc)

	if _, err := svc.Editor.SetItemArtwork(ctx, uc, track, "front", coverPNG(t, 40), false, false); err != nil {
		t.Fatal(err)
	}
	rows, err := svc.lib.Changes(ctx, head)
	if err != nil {
		t.Fatal(err)
	}
	for _, ch := range rows {
		if ch.EntityType == "album" {
			t.Fatalf("the write logged an album row, which names the album on its own: %+v", rows)
		}
	}
	pids, unnamed := changesAfter(t, ctx, svc)
	if unnamed || !slices.Equal(pids, sortedPIDs(album, track)) {
		t.Fatalf("changes = %v (unnamed %v), want the track %s and its album %s", pids, unnamed, track, album)
	}
	if pids, unnamed, _ := svc.DrainCatalogChanges(); len(pids) != 0 || unnamed {
		t.Fatalf("a second drain = %v (unnamed %v), want nothing", pids, unnamed)
	}
}

func sortedPIDs(pids ...string) []string {
	slices.Sort(pids)
	return pids
}

// An artist's portrait, the write that logs no item row, names the artist.
func TestAnArtistPortraitNamesTheArtist(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	_, artist := fixtureEntityPIDs(t, ctx, svc, uc)
	quietChanges(t, svc)

	if _, err := svc.Editor.SetEntityArtwork(ctx, uc, "artist", artist, "front", coverPNG(t, 40), false); err != nil {
		t.Fatal(err)
	}
	if pids, unnamed := changesAfter(t, ctx, svc); unnamed || !slices.Equal(pids, []string{artist}) {
		t.Fatalf("changes = %v (unnamed %v), want the artist %s", pids, unnamed, artist)
	}
}

// Each row is named the way the API spells its entity. A genre has no
// pid there and is not named, which is not the same as left unnamed; an item
// that is gone carries the track prefix, as its sync tombstone does.
func TestChangeRowsAreNamedAsTheAPISpellsThem(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	quietChanges(t, svc)

	var want []string
	for _, tc := range []struct {
		entityType string
		op         model.ChangeOp
		prefix     string
	}{
		{"artist", model.OpUpdate, PrefixArtist},
		{"album", model.OpCreate, PrefixAlbum},
		{"release_group", model.OpUpdate, PrefixReleaseGroup},
		{"series", model.OpUpdate, PrefixSeries},
		{"podcast", model.OpUpdate, PrefixPodcast},
		{"artist", model.OpDelete, PrefixArtist},
		{"item", model.OpDelete, PrefixTrack},
		// An item the catalog no longer holds, whatever its last row said.
		{"item", model.OpUpdate, PrefixTrack},
		{"genre", model.OpUpdate, ""},
		{"file", model.OpUpdate, ""},
		{"playlist", model.OpUpdate, ""},
	} {
		ch := historyRow(tc.entityType, tc.op)
		svc.advanceFeed(ctx, ch)
		if tc.prefix != "" {
			want = append(want, apiPID(tc.prefix, ch.EntityPID))
		}
	}
	slices.Sort(want)
	if pids, unnamed, _ := svc.DrainCatalogChanges(); unnamed || !slices.Equal(pids, want) {
		t.Fatalf("changes = %v (unnamed %v), want %v", pids, unnamed, want)
	}

	svc.advanceFeed(ctx, historyRow("genre", model.OpUpdate))
	if pids, unnamed, _ := svc.DrainCatalogChanges(); len(pids) != 0 || unnamed {
		t.Fatalf("a genre alone = %v (unnamed %v), want nothing named and nothing unnamed", pids, unnamed)
	}
}

// The pending set holds a frame's worth of entities. One more and what
// moved is unnamed until the next drain, which starts over.
func TestMoreChangesThanAFrameNamesAreUnnamed(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	quietChanges(t, svc)

	for range maxCatalogChangePIDs {
		svc.advanceFeed(ctx, historyRow("artist", model.OpUpdate))
	}
	if pids, unnamed, _ := svc.DrainCatalogChanges(); unnamed || len(pids) != maxCatalogChangePIDs {
		t.Fatalf("a full set = %d pids (unnamed %v), want all %d named", len(pids), unnamed, maxCatalogChangePIDs)
	}

	for range maxCatalogChangePIDs + 1 {
		svc.advanceFeed(ctx, historyRow("artist", model.OpUpdate))
	}
	svc.advanceFeed(ctx, historyRow("artist", model.OpUpdate))
	if pids, unnamed, _ := svc.DrainCatalogChanges(); !unnamed || len(pids) != 0 {
		t.Fatalf("past the bound = %v (unnamed %v), want unnamed", pids, unnamed)
	}
	svc.feed.changes.mu.Lock()
	held := len(svc.feed.changes.named) + len(svc.feed.changes.items)
	svc.feed.changes.mu.Unlock()
	if held != 0 {
		t.Fatalf("the set still holds %d entries after the drain", held)
	}

	last := historyRow("artist", model.OpUpdate)
	svc.advanceFeed(ctx, last)
	if pids, unnamed, _ := svc.DrainCatalogChanges(); unnamed || !slices.Equal(pids, []string{apiPID(PrefixArtist, last.EntityPID)}) {
		t.Fatalf("after that was drained = %v (unnamed %v), want the one artist", pids, unnamed)
	}
}

// The albums the drain adds count against the same bound.
func TestAlbumsThatDoNotFitLeaveTheDrainUnnamed(t *testing.T) {
	t.Parallel()
	var c catalogChanges
	for range maxCatalogChangePIDs/2 + 1 {
		c.record(historyRow("item", model.OpUpdate))
	}
	views := func(pids []model.PID) ([]*model.ItemView, error) {
		out := make([]*model.ItemView, len(pids))
		for i, pid := range pids {
			out[i] = &model.ItemView{PID: pid, Kind: model.KindTrack, AlbumPID: model.PID(ulid.Make().String())}
		}
		return out, nil
	}
	if pids, unnamed, _ := drainItems(&c, views); !unnamed || len(pids) != 0 {
		t.Fatalf("drain = %d pids (unnamed %v), want unnamed", len(pids), unnamed)
	}
}

// One read answers every item of a drain: its kind's prefix and its
// album. A deleted item is not asked about, and tracks of one album name
// it once.
func TestTheDrainReadsItsItemsOnce(t *testing.T) {
	t.Parallel()
	var c catalogChanges
	book, track, other, gone := historyRow("item", model.OpUpdate), historyRow("item", model.OpCreate),
		historyRow("item", model.OpUpdate), historyRow("item", model.OpDelete)
	album := model.PID(ulid.Make().String())
	for _, ch := range []model.Change{book, track, other, gone, track} {
		c.record(ch)
	}
	reads := 0
	pids, unnamed, _ := drainItems(&c, func(asked []model.PID) ([]*model.ItemView, error) {
		reads++
		if len(asked) != 3 || slices.Contains(asked, gone.EntityPID) {
			t.Errorf("the read asked for %v, want the three items still there", asked)
		}
		return []*model.ItemView{
			{PID: book.EntityPID, Kind: model.KindBook},
			{PID: track.EntityPID, Kind: model.KindTrack, AlbumPID: album},
			{PID: other.EntityPID, Kind: model.KindTrack, AlbumPID: album},
		}, nil
	})
	want := sortedPIDs(
		apiPID(PrefixBook, book.EntityPID), apiPID(PrefixTrack, track.EntityPID),
		apiPID(PrefixTrack, other.EntityPID), apiPID(PrefixAlbum, album), apiPID(PrefixTrack, gone.EntityPID),
	)
	if reads != 1 || unnamed || !slices.Equal(pids, want) {
		t.Fatalf("drain = %v (unnamed %v, %d reads), want %v from one read", pids, unnamed, reads, want)
	}

	// Nothing but entity rows and a deleted item: no read at all.
	c.record(historyRow("artist", model.OpUpdate))
	c.record(historyRow("item", model.OpDelete))
	if pids, unnamed, _ := drainItems(&c, func([]model.PID) ([]*model.ItemView, error) {
		t.Error("a drain with no item to ask about read the catalog")
		return nil, nil
	}); unnamed || len(pids) != 2 {
		t.Fatalf("drain = %v (unnamed %v), want the two pids", pids, unnamed)
	}
}

// A drain whose read failed cannot say which albums moved, so it names
// nothing; what it held is spent either way.
func TestAFailedAlbumReadIsUnnamed(t *testing.T) {
	t.Parallel()
	var c catalogChanges
	c.record(historyRow("artist", model.OpUpdate))
	c.record(historyRow("item", model.OpUpdate))
	failing := func([]model.PID) ([]*model.ItemView, error) { return nil, errors.New("catalog away") }
	if pids, unnamed, _ := drainItems(&c, failing); !unnamed || len(pids) != 0 {
		t.Fatalf("drain = %v (unnamed %v), want unnamed", pids, unnamed)
	}
	if pids, unnamed, _ := drainItems(&c, failing); unnamed || len(pids) != 0 {
		t.Fatalf("the drain after = %v (unnamed %v), want nothing", pids, unnamed)
	}
}

// A wake no row stands behind has nothing to name, which is not the
// same as entities it could not name: alone, or beside a genre, the
// drain is not unnamed. It says the catalog may be another one, so the
// drain is unknown, and rows recorded on either side of it are not
// named until the next drain: those are entities left unnamed. Rows
// that have no pid, with no such wake, are neither.
func TestAWakeWithNoRowIsUnknownAndUnnamesItsNeighbours(t *testing.T) {
	t.Parallel()
	none := func([]model.PID) ([]*model.ItemView, error) { return nil, nil }
	for _, tc := range []struct {
		name             string
		rows             func(*catalogChanges)
		unnamed, unknown bool
	}{
		{"alone", func(c *catalogChanges) { c.markUnknown() }, false, true},
		{"beside a genre", func(c *catalogChanges) {
			c.record(historyRow("genre", model.OpUpdate))
			c.markUnknown()
			c.record(historyRow("genre", model.OpUpdate))
		}, false, true},
		{"after an entity", func(c *catalogChanges) {
			c.record(historyRow("artist", model.OpUpdate))
			c.markUnknown()
		}, true, true},
		{"before an entity", func(c *catalogChanges) {
			c.markUnknown()
			c.record(historyRow("album", model.OpUpdate))
		}, true, true},
		{"after an item", func(c *catalogChanges) {
			c.record(historyRow("item", model.OpDelete))
			c.markUnknown()
		}, true, true},
		{"before an item", func(c *catalogChanges) {
			c.markUnknown()
			c.record(historyRow("item", model.OpUpdate))
		}, true, true},
		{"after more than fit", func(c *catalogChanges) {
			for range maxCatalogChangePIDs + 1 {
				c.record(historyRow("artist", model.OpUpdate))
			}
			c.markUnknown()
		}, true, true},
		{"a genre and no such wake", func(c *catalogChanges) {
			c.record(historyRow("genre", model.OpUpdate))
		}, false, false},
		{"more than fit and no such wake", func(c *catalogChanges) {
			for range maxCatalogChangePIDs + 1 {
				c.record(historyRow("artist", model.OpUpdate))
			}
		}, true, false},
	} {
		var c catalogChanges
		tc.rows(&c)
		if pids, unnamed, unknown := drainItems(&c, none); len(pids) != 0 || unnamed != tc.unnamed || unknown != tc.unknown {
			t.Errorf("%s: drain = %v (unnamed %v, unknown %v), want no pids, unnamed %v, unknown %v",
				tc.name, pids, unnamed, unknown, tc.unnamed, tc.unknown)
		}
		if pids, unnamed, unknown := drainItems(&c, none); len(pids) != 0 || unnamed || unknown {
			t.Errorf("%s: the drain after = %v (unnamed %v, unknown %v), want nothing", tc.name, pids, unnamed, unknown)
		}
	}
}

// A new catalog generation, and a replaced catalog, are wakes no row
// stands behind: alone the drain has nothing to name, and what was
// recorded beside one is left unnamed, until the next drain.
func TestANewGenerationAndAReplacedCatalogNameNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	quietChanges(t, svc)

	svc.mintCatalogGeneration(ctx)
	if pids, unnamed, unknown := svc.DrainCatalogChanges(); unnamed || !unknown || len(pids) != 0 {
		t.Fatalf("a new generation alone = %v (unnamed %v, unknown %v), want nothing to name and unknown", pids, unnamed, unknown)
	}

	svc.advanceFeed(ctx, historyRow("artist", model.OpUpdate))
	svc.mintCatalogGeneration(ctx)
	svc.advanceFeed(ctx, historyRow("artist", model.OpUpdate))
	if pids, unnamed, _ := svc.DrainCatalogChanges(); !unnamed || len(pids) != 0 {
		t.Fatalf("around a new generation = %v (unnamed %v), want unnamed", pids, unnamed)
	}
	if pids, unnamed, _ := svc.DrainCatalogChanges(); unnamed || len(pids) != 0 {
		t.Fatalf("the drain after = %v (unnamed %v), want nothing", pids, unnamed)
	}

	svc.advanceFeed(ctx, historyRow("artist", model.OpUpdate))
	svc.feed.mu.Lock()
	seq, ts := svc.feed.tail, svc.feed.tailTS
	svc.feed.mu.Unlock()
	if !svc.catalogReplaced(ctx, seq, ts+1) {
		t.Fatal("the fixture's catalog was not taken as replaced")
	}
	if pids, unnamed, _ := svc.DrainCatalogChanges(); !unnamed || len(pids) != 0 {
		t.Fatalf("across a replaced catalog = %v (unnamed %v), want unnamed", pids, unnamed)
	}
}

// A replaced catalog wakes the hub, so what it marks drains beside the
// resync it sends: the next change, however much later, is named. The
// wake comes only once the resync is queued, so no connection takes a
// catalog invalidation ahead of it: a mirror would re-mirror for each.
func TestAReplacedCatalogDrainsAtOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	quietChanges(t, svc)
	select {
	case <-svc.CatalogWakeups():
	default:
	}
	resynced, wokeFirst := false, false
	svc.SetCatalogResyncer(func() {
		resynced, wokeFirst = true, len(svc.catalogWake) > 0
	})

	svc.feed.mu.Lock()
	seq, ts := svc.feed.tail, svc.feed.tailTS
	svc.feed.mu.Unlock()
	if !svc.catalogReplaced(ctx, seq, ts+1) {
		t.Fatal("the fixture's catalog was not taken as replaced")
	}
	if !resynced || wokeFirst {
		t.Fatalf("resync sent %v, the hub woken before it %v: want the resync queued before the wake", resynced, wokeFirst)
	}
	select {
	case <-svc.CatalogWakeups():
	default:
		t.Fatal("a replaced catalog left the hub asleep")
	}
	if pids, unnamed, unknown := svc.DrainCatalogChanges(); unnamed || !unknown || len(pids) != 0 {
		t.Fatalf("the wake's drain = %v (unnamed %v, unknown %v), want nothing to name and unknown", pids, unnamed, unknown)
	}
	later := historyRow("artist", model.OpUpdate)
	svc.advanceFeed(ctx, later)
	if pids, unnamed, _ := svc.DrainCatalogChanges(); unnamed || !slices.Equal(pids, []string{apiPID(PrefixArtist, later.EntityPID)}) {
		t.Fatalf("a later change = %v (unnamed %v), want the artist named", pids, unnamed)
	}
}

// Only an account nothing narrows (every library, explicit content, no
// tag rule) is told a name nothing beside it decides, an artist's row
// alone; any other is told it went unnamed. The answer follows the
// account as an administrator edits it, and one that cannot sign in has
// none.
func TestOnlyAnAccountNothingNarrowsSeesTheWholeCatalog(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	// An artist's row alone: nothing beside it says who may see it.
	artist := apiPID(PrefixArtist, model.PID(ulid.Make().String()))
	seesWhole := func(userID string) bool {
		_, named, unnamed := svc.CatalogFrameFor(userID, "", []string{artist})
		return !unnamed && slices.Equal(named, []string{artist})
	}
	if !seesWhole(admin.ID) {
		t.Fatal("an administrator does not see the whole catalog")
	}
	if seesWhole("us-nobody") {
		t.Fatal("an account that does not exist sees the whole catalog")
	}

	acct, err := svc.Identity.CreateAccount(ctx, AccountCreate{
		Username: "reader", Password: "correct-horse", AccessMode: "granted",
	})
	if err != nil {
		t.Fatal(err)
	}
	id := acct.User.ID
	update := func(what string, upd AccountUpdate, want bool) {
		t.Helper()
		if _, err := svc.Identity.UpdateAccount(ctx, id, upd); err != nil {
			t.Fatalf("%s: %v", what, err)
		}
		if got := seesWhole(id); got != want {
			t.Fatalf("%s: sees the whole catalog = %v, want %v", what, got, want)
		}
	}
	if seesWhole(id) {
		t.Fatal("an account held to granted libraries sees the whole catalog")
	}
	all, granted := "all", "granted"
	open := Permissions{Download: true, Explicit: true}
	update("every library", AccountUpdate{AccessMode: &all}, true)
	update("a tag rule", AccountUpdate{Permissions: &Permissions{Download: true, Explicit: true,
		TagDeny: []TagRule{{Key: "MOOD", Value: "calm"}}}}, false)
	update("the rule lifted", AccountUpdate{Permissions: &open}, true)
	update("no explicit content", AccountUpdate{Permissions: &Permissions{Download: true}}, false)
	update("explicit content back", AccountUpdate{Permissions: &open}, true)
	update("granted libraries again", AccountUpdate{AccessMode: &granted}, false)
	update("every library again", AccountUpdate{AccessMode: &all}, true)
	disabled := true
	update("disabled", AccountUpdate{Disabled: &disabled}, false)
}

// An album's cover is what its tracks draw when they have none of their
// own, and a cover set at the album logs no item row: the album's row
// names its tracks beside it.
func TestAnAlbumsNewCoverNamesTheAlbumAndItsTracks(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	album, _ := fixtureEntityPIDs(t, ctx, svc, uc)
	_, bare, _ := parseAPIPID(album)
	tracks, err := svc.lib.Query(ctx, visibleItems().Where("album_pid", query.OpIs, string(bare)).Build(), "")
	if err != nil || len(tracks) < 2 {
		t.Fatalf("the fixture album has %d tracks (%v), want several", len(tracks), err)
	}
	quietChanges(t, svc)

	if _, err := svc.Editor.SetEntityArtwork(ctx, uc, "album", album, "front", coverPNG(t, 40), false); err != nil {
		t.Fatal(err)
	}
	// A show's cover in the same drain: one read asks for both.
	svc.feed.changes.recordShowCover(model.PID(ulid.Make().String()))
	pids, unnamed := changesAfter(t, ctx, svc)
	if unnamed || !slices.Contains(pids, album) {
		t.Fatalf("changes = %v (unnamed %v), want the album %s named", pids, unnamed, album)
	}
	for _, tr := range tracks {
		if !slices.Contains(pids, itemAPIPID(tr)) {
			t.Fatalf("changes = %v, want the album's track %s named beside it", pids, itemAPIPID(tr))
		}
	}
}

// A show's cover is what its episodes draw when they have none of their
// own: a cover set or cleared at the show names its episodes beside it.
func TestAShowsNewCoverNamesItsEpisodes(t *testing.T) {
	t.Parallel()
	f := openStubFeeds(t, &stubFeed{kind: model.SourceRSS, n: 3, prefix: "Episode"})
	show := f.subscribe(t, "https://feeds.example/small", "rss").Show.PID
	_, bare, _ := parseAPIPID(show)
	episodes, err := f.svc.lib.Query(f.ctx, visibleItems().Where("podcast_pid", query.OpIs, string(bare)).Build(), "")
	if err != nil || len(episodes) != 3 {
		t.Fatalf("the show has %d episodes (%v), want 3", len(episodes), err)
	}
	named := func(what string) {
		t.Helper()
		pids, unnamed := changesAfter(t, f.ctx, f.svc)
		if unnamed || !slices.Contains(pids, show) {
			t.Fatalf("%s: changes = %v (unnamed %v), want the show %s named", what, pids, unnamed, show)
		}
		for _, ep := range episodes {
			if !slices.Contains(pids, itemAPIPID(ep)) {
				t.Fatalf("%s: changes = %v, want the show's episode %s named beside it", what, pids, itemAPIPID(ep))
			}
		}
	}

	quietChanges(t, f.svc)
	if _, err := f.svc.Editor.SetEntityArtwork(f.ctx, f.uc, "podcast", show, "front", coverPNG(t, 40), false); err != nil {
		t.Fatal(err)
	}
	named("a cover set")

	quietChanges(t, f.svc)
	if err := f.svc.Editor.ClearEntityArtwork(f.ctx, f.uc, "podcast", show, "front"); err != nil {
		t.Fatal(err)
	}
	named("the cover cleared")
}

// A show's row is logged for every episode a refresh adds or changes, so
// the row alone names the show and none of its episodes: a show with
// more episodes than a frame names is still named, not left unnamed.
func TestAShowsRowAloneNamesNoEpisodes(t *testing.T) {
	t.Parallel()
	f := openStubFeeds(t, &stubFeed{kind: model.SourceRSS, n: maxCatalogChangePIDs + 6, prefix: "Episode"})
	show := f.subscribe(t, "https://feeds.example/long", "rss").Show.PID
	_, bare, _ := parseAPIPID(show)
	if n, err := f.svc.lib.Query(f.ctx, visibleItems().Where("podcast_pid", query.OpIs, string(bare)).Build(), ""); err != nil || len(n) <= maxCatalogChangePIDs {
		t.Fatalf("the show has %d episodes (%v), want more than a frame names", len(n), err)
	}
	quietChanges(t, f.svc)

	f.svc.advanceFeed(f.ctx, model.Change{EntityType: "podcast", EntityPID: bare, Op: model.OpUpdate})
	if pids, unnamed, _ := f.svc.DrainCatalogChanges(); unnamed || !slices.Equal(pids, []string{show}) {
		t.Fatalf("changes = %v (unnamed %v), want the show %s alone", pids, unnamed, show)
	}

	// Its cover, set, names more episodes than fit, through the real read.
	if _, err := f.svc.Editor.SetEntityArtwork(f.ctx, f.uc, "podcast", show, "front", coverPNG(t, 40), false); err != nil {
		t.Fatal(err)
	}
	if pids, unnamed := changesAfter(t, f.ctx, f.svc); !unnamed || len(pids) != 0 {
		t.Fatalf("a cover set on it: changes = %v (unnamed %v), want unnamed", pids, unnamed)
	}
}

// The drain's two reads share one bound, because every topic's frames
// wait behind the drain: both are handed the same context, so a first
// read that spends it leaves the second none, and the drain unnamed.
func TestTheDrainsReadsShareOneBound(t *testing.T) {
	t.Parallel()
	_, svc, _ := newCatalogFixture(t)
	quietChanges(t, svc)
	svc.feed.changes.record(historyRow("item", model.OpUpdate))
	svc.feed.changes.record(historyRow("album", model.OpUpdate))

	var first, second time.Time
	var spent error
	pids, unnamed, _ := svc.drainCatalogChanges(
		func(ctx context.Context, _ []model.PID) ([]*model.ItemView, error) {
			first, _ = ctx.Deadline()
			// Answers, but only as its bound runs out.
			<-ctx.Done()
			return nil, nil
		},
		func(ctx context.Context, _, _ []model.PID) ([]*model.ItemView, error) {
			second, _ = ctx.Deadline()
			spent = ctx.Err()
			return nil, spent
		})
	if first.IsZero() || !first.Equal(second) {
		t.Errorf("the reads' deadlines are %v and %v, want one bound for both", first, second)
	}
	if spent == nil {
		t.Error("the second read was handed a context the first had not spent")
	}
	if !unnamed || len(pids) != 0 {
		t.Errorf("drain = %v (unnamed %v), want unnamed once the bound ran out", pids, unnamed)
	}
}

// Members count against the frame's bound beside their parent, in one
// read for every parent of a drain: an album whose row is here, a show
// whose cover moved. A parent that is gone has none to read, a show's
// row alone has none read, a failed read leaves the drain unnamed, and a
// track's own row names its album and none of the album's other tracks.
func TestMembersFollowTheirParentUnderTheSameBound(t *testing.T) {
	t.Parallel()
	noItems := func([]model.PID) ([]*model.ItemView, error) { return nil, nil }
	memberViews := func(kind model.Kind, n int) []*model.ItemView {
		out := make([]*model.ItemView, n)
		for i := range out {
			out[i] = &model.ItemView{PID: model.PID(ulid.Make().String()), Kind: kind}
		}
		return out
	}

	t.Run("an album, a show and a gone one of each in one read", func(t *testing.T) {
		var c catalogChanges
		album, show := historyRow("album", model.OpUpdate), historyRow("podcast", model.OpCreate)
		goneAlbum, goneShow := historyRow("album", model.OpDelete), historyRow("podcast", model.OpDelete)
		rowOnly := historyRow("podcast", model.OpUpdate)
		for _, ch := range []model.Change{album, show, goneAlbum, goneShow, album, rowOnly} {
			c.record(ch)
		}
		c.recordShowCover(show.EntityPID)
		// A cover set on a show that is then deleted.
		c.recordShowCover(goneShow.EntityPID)
		c.record(goneShow)
		tracks, episodes := memberViews(model.KindTrack, 2), memberViews(model.KindEpisode, 2)
		reads := 0
		pids, unnamed, _ := c.drain(noItems, func(albums, shows []model.PID) ([]*model.ItemView, error) {
			reads++
			if !slices.Equal(albums, []model.PID{album.EntityPID}) || !slices.Equal(shows, []model.PID{show.EntityPID}) {
				t.Errorf("the read asked for albums %v and shows %v, want the two still there", albums, shows)
			}
			return append(tracks, episodes...), nil
		})
		want := sortedPIDs(
			apiPID(PrefixAlbum, album.EntityPID), apiPID(PrefixPodcast, show.EntityPID),
			apiPID(PrefixAlbum, goneAlbum.EntityPID), apiPID(PrefixPodcast, goneShow.EntityPID),
			apiPID(PrefixPodcast, rowOnly.EntityPID),
			itemAPIPID(tracks[0]), itemAPIPID(tracks[1]), itemAPIPID(episodes[0]), itemAPIPID(episodes[1]),
		)
		if reads != 1 || unnamed || !slices.Equal(pids, want) {
			t.Fatalf("drain = %v (unnamed %v, %d reads), want %v from one read", pids, unnamed, reads, want)
		}
	})

	for _, tc := range []struct {
		name   string
		parent func(*catalogChanges)
		kind   model.Kind
	}{
		{"an album whose tracks do not fit beside it", func(c *catalogChanges) {
			c.record(historyRow("album", model.OpUpdate))
		}, model.KindTrack},
		{"a show whose episodes do not fit beside it", func(c *catalogChanges) {
			c.recordShowCover(model.PID(ulid.Make().String()))
		}, model.KindEpisode},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var c catalogChanges
			tc.parent(&c)
			fits := func([]model.PID, []model.PID) ([]*model.ItemView, error) {
				return memberViews(tc.kind, maxCatalogChangePIDs-1), nil
			}
			if pids, unnamed, _ := c.drain(noItems, fits); unnamed || len(pids) != maxCatalogChangePIDs {
				t.Fatalf("a full frame: drain = %d pids (unnamed %v), want all %d named", len(pids), unnamed, maxCatalogChangePIDs)
			}
			tc.parent(&c)
			over := func([]model.PID, []model.PID) ([]*model.ItemView, error) {
				return memberViews(tc.kind, maxCatalogChangePIDs), nil
			}
			if pids, unnamed, _ := c.drain(noItems, over); !unnamed || len(pids) != 0 {
				t.Fatalf("one more: drain = %d pids (unnamed %v), want unnamed", len(pids), unnamed)
			}
		})
	}

	t.Run("a failed read", func(t *testing.T) {
		var c catalogChanges
		c.record(historyRow("album", model.OpUpdate))
		failing := func([]model.PID, []model.PID) ([]*model.ItemView, error) { return nil, errors.New("catalog away") }
		if pids, unnamed, _ := c.drain(noItems, failing); !unnamed || len(pids) != 0 {
			t.Fatalf("drain = %v (unnamed %v), want unnamed", pids, unnamed)
		}
	})

	t.Run("a track's own row", func(t *testing.T) {
		var c catalogChanges
		track := historyRow("item", model.OpUpdate)
		album := model.PID(ulid.Make().String())
		c.record(track)
		pids, unnamed, _ := drainItems(&c, func([]model.PID) ([]*model.ItemView, error) {
			return []*model.ItemView{{PID: track.EntityPID, Kind: model.KindTrack, AlbumPID: album}}, nil
		})
		if want := sortedPIDs(apiPID(PrefixAlbum, album), apiPID(PrefixTrack, track.EntityPID)); unnamed || !slices.Equal(pids, want) {
			t.Fatalf("drain = %v (unnamed %v), want the track and its album %v alone", pids, unnamed, want)
		}
	})
}

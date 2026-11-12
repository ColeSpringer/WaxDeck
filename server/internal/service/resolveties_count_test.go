package service

import (
	"context"
	"sync"
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// walkCount counts the walks of the resolve ladder a library makes, one
// per ref walked, apart by whether the walk took ties.
type walkCount struct {
	mu          sync.Mutex
	plain, ties int
}

func countWalks(svc *Library) *walkCount {
	c := &walkCount{}
	svc.Playlists.refResolveHook = func(opts waxbin.ResolveOptions, refs int) {
		c.mu.Lock()
		defer c.mu.Unlock()
		if opts.AcceptSameRecording {
			c.ties += refs
		} else {
			c.plain += refs
		}
	}
	return c
}

// take answers the walks counted since the last take.
func (c *walkCount) take() (plain, ties int) {
	c.mu.Lock()
	defer c.mu.Unlock()
	plain, ties = c.plain, c.ties
	c.plain, c.ties = 0, 0
	return plain, ties
}

// tieShape is one way a resolve can end, with what it answers and the
// walks it takes: the plain one, then the one taking ties.
type tieShape struct {
	what        string
	ref         model.PortableRef
	want        *model.ItemView
	candidates  int
	plain, ties int
}

// tieShapes is the library copiesOfOneRecording makes, its copied song's
// two copies given one recording id, and a ref for each way a resolve
// ends. Every walk takes ties first; only a tie on a rung above the
// descriptive one is walked again, plainly.
func tieShapes(t *testing.T) (context.Context, *migrateFixture, []tieShape) {
	t.Helper()
	ctx, f := newMigrateFixtureWith(t, copiesOfOneRecording)
	const mbid = "00000000-0000-4000-8000-0000000000ab"
	copies := f.itemsTitled(t, ctx, "Copied Song")
	if len(copies) != 2 {
		t.Fatalf("copies = %d items, want the album track held twice", len(copies))
	}
	for _, it := range copies {
		if err := f.svc.lib.EditFields(ctx, it.PID, map[string]string{"mbid": mbid}, waxbin.EditOptions{}); err != nil {
			t.Fatal(err)
		}
	}
	alpha := f.itemsTitled(t, ctx, "Alpha Song")
	if len(alpha) != 1 {
		t.Fatalf("alpha = %d items, want one", len(alpha))
	}
	track := func(mbid, artist, title, album string, ms int64) model.PortableRef {
		return model.PortableRef{Kind: model.KindTrack, MBID: mbid, Artist: artist, Title: title, Album: album, DurationMS: ms}
	}
	return ctx, f, []tieShape{
		{"a unique match", track("", "Fixture Artist", "Alpha Song", "Fixture Album", 2000), alpha[0], 1, 0, 1},
		{"a plain miss", track("", "Nobody", "Nothing Song", "", 3000), nil, 0, 0, 1},
		{"an unproven descriptive tie", track("", "Twice Artist", "Twice Song", "Greatest Hits", 3000), nil, 2, 0, 1},
		{"a proven descriptive tie", track("", "Copy Artist", "Copied Song", "Copy Album", 3000), copies[0], 2, 0, 1},
		{"a proven strong-id tie", track(mbid, "Copy Artist", "Copied Song", "Copy Album", 3000), copies[0], 2, 1, 1},
	}
}

// A migration's resolve walks the ladder once, taking ties, and again
// only for a tie a later rung could still overrule, and its answers are
// the ones the ladder gives either way.
func TestAMigrationResolveWalksTwiceOnlyForATieAboveTheLastRung(t *testing.T) {
	t.Parallel()
	ctx, f, shapes := tieShapes(t)
	walks := countWalks(f.svc)
	for _, s := range shapes {
		it, copies, err := f.svc.Migrate.resolveMigrationRef(ctx, s.ref)
		if err != nil {
			t.Fatal(err)
		}
		if plain, ties := walks.take(); plain != s.plain || ties != s.ties {
			t.Errorf("%s: %d plain and %d tie-taking walks, want %d and %d", s.what, plain, ties, s.plain, s.ties)
		}
		if (it == nil) != (s.want == nil) || it != nil && it.PID != s.want.PID || copies != s.candidates {
			t.Errorf("%s: answered %v with %d copies, want %v with %d", s.what, it, copies, s.want, s.candidates)
		}
	}
}

// An entity star's member resolves the same way: one walk, and a second
// only for a tie above the last rung.
func TestAGroupMemberResolveWalksTwiceOnlyForATieAboveTheLastRung(t *testing.T) {
	t.Parallel()
	ctx, f, shapes := tieShapes(t)
	walks := countWalks(f.svc)
	album := func(it *model.ItemView) model.PID { return it.AlbumPID }
	for _, s := range shapes {
		sure, fallback, err := f.svc.Migrate.resolveGroupMember(ctx, s.ref, album)
		if err != nil {
			t.Fatal(err)
		}
		if plain, ties := walks.take(); plain != s.plain || ties != s.ties {
			t.Errorf("%s: %d plain and %d tie-taking walks, want %d and %d", s.what, plain, ties, s.plain, s.ties)
		}
		// The copies sit in two folders, so two albums: a tie between them
		// decides nothing and is only a fallback.
		got := sure
		if s.candidates > 1 {
			if sure != nil {
				t.Errorf("%s: a tie between two albums answered sure %v", s.what, sure)
			}
			got = fallback
		}
		if (got == nil) != (s.want == nil) || got != nil && got.PID != s.want.PID {
			t.Errorf("%s: answered %v, want %v", s.what, got, s.want)
		}
	}
}

// A playlist import walks every entry once, taking ties, walks again only
// the entries whose tie stood above the last rung, and walks nothing more
// for a match its caller may not hold: the tie it falls back on is the one
// the first walk took.
func TestAPlaylistImportWalksTwiceOnlyForATieAboveTheLastRung(t *testing.T) {
	t.Parallel()
	ctx, f, shapes := tieShapes(t)
	refs := make([]PortableRefDTO, len(shapes))
	wantPlain, wantTies := 0, 0
	for i, s := range shapes {
		refs[i] = PortableRefDTO{
			Kind: string(s.ref.Kind), MBID: s.ref.MBID, Artist: s.ref.Artist,
			Title: s.ref.Title, Album: s.ref.Album, DurationMs: s.ref.DurationMS,
		}
		wantPlain += s.plain
		wantTies += s.ties
	}
	walks := countWalks(f.svc)

	res, _, err := f.svc.Playlists.resolvePlaylistImportRefs(ctx, memberFilter{uc: f.uc, subs: f.svc.Podcasts.newSubscriptionFilter(f.uc)}, refs)
	if err != nil {
		t.Fatal(err)
	}
	if plain, ties := walks.take(); plain != wantPlain || ties != wantTies {
		t.Errorf("the import made %d plain and %d tie-taking walks, want %d and %d", plain, ties, wantPlain, wantTies)
	}
	for i, s := range shapes {
		if got := res[i].PID; (s.want == nil) != (got == "") || s.want != nil && got != s.want.PID {
			t.Errorf("%s: resolved to %q, want %v", s.what, got, s.want)
		}
	}

	// A reader granted no library holds none of the matches.
	blind := &UserCtx{ID: f.uc.ID, CatalogPID: f.uc.CatalogPID, Libraries: map[string]bool{"none": true}}
	res, _, err = f.svc.Playlists.resolvePlaylistImportRefs(ctx, memberFilter{uc: blind, subs: f.svc.Podcasts.newSubscriptionFilter(blind)}, refs)
	if err != nil {
		t.Fatal(err)
	}
	if plain, ties := walks.take(); plain != wantPlain || ties != wantTies {
		t.Errorf("the blind import made %d plain and %d tie-taking walks, want %d and %d", plain, ties, wantPlain, wantTies)
	}
	for i, s := range shapes {
		if res[i].Rung != model.MatchNone {
			t.Errorf("%s: the blind reader resolved %+v, want a miss", s.what, res[i])
		}
	}
}

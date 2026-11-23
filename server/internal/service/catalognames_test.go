package service

import (
	"context"
	"errors"
	"slices"
	"testing"

	"github.com/colespringer/waxbin/model"
	"github.com/oklog/ulid/v2"
)

// newPID is an API pid with the prefix that no catalog row stands behind.
func newPID(prefix string) string { return apiPID(prefix, model.PID(ulid.Make().String())) }

// itemEntities answers the album and artist pids of the item.
func itemEntities(t *testing.T, ctx context.Context, svc *Library, pid string) (album, artist string) {
	t.Helper()
	_, bare, _ := parseAPIPID(pid)
	view, err := svc.lib.Get(ctx, bare)
	if err != nil || view.AlbumPID == "" || view.ArtistPID == "" {
		t.Fatalf("item %s has no album or artist: %+v (%v)", pid, view, err)
	}
	return apiPID(PrefixAlbum, view.AlbumPID), apiPID(PrefixArtist, view.ArtistPID)
}

// An account granted one library is told, of a frame's names, the item
// in it and the entities that item belongs to; the item in the other
// library and its album are left out, and nothing it may not be told is
// named. An entity nothing at hand belongs to is left unnamed for it,
// and an item that is gone is not named. An administrator is told all.
func TestARestrictedAccountIsToldTheNamesItSees(t *testing.T) {
	t.Parallel()
	r := newJournalReach(t)
	seen, unseen := r.item(t, "Seen Song"), r.item(t, "Unseen Song")
	seenAlbum, seenArtist := itemEntities(t, r.ctx, r.svc, seen)
	unseenAlbum, _ := itemEntities(t, r.ctx, r.svc, unseen)
	frame := func(pids ...string) []string {
		slices.Sort(pids)
		return pids
	}
	told := func(what string, uc *UserCtx, pids, want []string, wantUnnamed bool) {
		t.Helper()
		_, named, unnamed := r.svc.CatalogFrameFor(uc.ID, "", pids)
		if unnamed != wantUnnamed || !slices.Equal(named, want) {
			t.Fatalf("%s: told %v (unnamed %v), want %v (unnamed %v)", what, named, unnamed, want, wantUnnamed)
		}
	}

	both := frame(seen, seenAlbum, unseen, unseenAlbum)
	told("both items and their albums, to the reader", r.reader, both, frame(seen, seenAlbum), false)
	told("both items and their albums, to an administrator", r.admin, both, both, false)
	told("the unseen item and its album", r.reader, frame(unseen, unseenAlbum), nil, false)
	told("the seen item and its artist", r.reader, frame(seen, seenArtist), frame(seen, seenArtist), false)
	gone := newPID(PrefixTrack)
	told("the seen item beside one that is gone", r.reader, frame(seen, gone), frame(seen), false)

	artist := newPID(PrefixArtist)
	told("an artist's row alone, to the reader", r.reader, frame(artist), nil, true)
	told("an artist's row alone, to an administrator", r.admin, frame(artist), frame(artist), false)
	told("an album alone, to the reader", r.reader, frame(seenAlbum), nil, true)
	told("a series alone, to the reader", r.reader, frame(newPID(PrefixSeries)), nil, true)
}

// An account with explicit content off is not told an episode the feed
// marks, nor one of a show marked as a whole, nor such a show; a show
// is told by what an episode of it at hand says of the show, and left
// unnamed with none.
func TestTheExplicitToggleDecidesAnEpisodesName(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	reader := &UserCtx{ID: admin.ID, CatalogPID: admin.CatalogPID, AllLibraries: true}
	show, marked := model.PID(ulid.Make().String()), model.PID(ulid.Make().String())
	explicit, clean, ofMarked := model.PID(ulid.Make().String()), model.PID(ulid.Make().String()), model.PID(ulid.Make().String())
	views := func(_ context.Context, pids []model.PID) ([]*model.ItemView, error) {
		all := map[model.PID]*model.ItemView{
			explicit: {PID: explicit, Kind: model.KindEpisode, PodcastPID: show, Explicit: true},
			clean:    {PID: clean, Kind: model.KindEpisode, PodcastPID: show},
			ofMarked: {PID: ofMarked, Kind: model.KindEpisode, PodcastPID: marked, PodcastExplicit: true},
		}
		var out []*model.ItemView
		for _, pid := range pids {
			if v := all[pid]; v != nil {
				out = append(out, v)
			}
		}
		return out, nil
	}
	ep := func(pid model.PID) string { return apiPID(PrefixEpisode, pid) }
	pc := func(pid model.PID) string { return apiPID(PrefixPodcast, pid) }
	frame := []string{ep(explicit), ep(clean), ep(ofMarked), pc(show), pc(marked)}
	slices.Sort(frame)
	want := []string{ep(clean), pc(show)}
	slices.Sort(want)

	named, ok := svc.Grants.catalogNamesFor(ctx, reader, frame, views)
	if !ok || !slices.Equal(named, want) {
		t.Fatalf("told %v (decided %v), want %v", named, ok, want)
	}
	if named, ok := svc.Grants.catalogNamesFor(ctx, reader, []string{pc(model.PID(ulid.Make().String()))}, views); ok || named != nil {
		t.Fatalf("a show alone: told %v (decided %v), want it undecided", named, ok)
	}
	if named, ok := svc.Grants.catalogNamesFor(ctx, admin, frame, views); !ok || !slices.Equal(named, frame) {
		t.Fatalf("an administrator: told %v (decided %v), want every name", named, ok)
	}
}

// An account with a tag rule is told a track the rule admits and not one
// it denies, and the album they share for the one it admits; an album
// whose every track at hand it denies is not told.
func TestATagRuleDecidesATracksName(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	f.tag(t, "Canonical", "MOOD", "calm")
	denied, admitted := f.itemNamed(t, "Canonical"), f.itemNamed(t, "Lowercase")
	if denied.AlbumPID == "" || denied.AlbumPID != admitted.AlbumPID {
		t.Fatalf("the fixture tracks do not share an album: %q and %q", denied.AlbumPID, admitted.AlbumPID)
	}
	album := apiPID(PrefixAlbum, denied.AlbumPID)
	uc := f.restricted(nil, []TagRule{{Key: "MOOD", Value: "calm"}})
	told := func(what string, pids, want []string) {
		t.Helper()
		slices.Sort(pids)
		slices.Sort(want)
		named, ok := f.svc.Grants.catalogNamesFor(f.ctx, uc, pids, f.svc.lib.GetMany)
		if !ok || !slices.Equal(named, want) {
			t.Fatalf("%s: told %v (decided %v), want %v", what, named, ok, want)
		}
	}
	told("both tracks and their album", []string{itemAPIPID(denied), itemAPIPID(admitted), album},
		[]string{itemAPIPID(admitted), album})
	told("the denied track and its album", []string{itemAPIPID(denied), album}, nil)
}

// Names cost a restricted account one item read, and one that sees
// everything none; a read that fails decides nothing.
func TestNamesCostOneItemRead(t *testing.T) {
	t.Parallel()
	r := newJournalReach(t)
	seen := r.item(t, "Seen Song")
	album, _ := itemEntities(t, r.ctx, r.svc, seen)
	frame := []string{album, seen}
	slices.Sort(frame)
	reads := 0
	counted := func(ctx context.Context, pids []model.PID) ([]*model.ItemView, error) {
		reads++
		return r.svc.lib.GetMany(ctx, pids)
	}
	if named, ok := r.svc.Grants.catalogNamesFor(r.ctx, r.admin, frame, counted); !ok || !slices.Equal(named, frame) || reads != 0 {
		t.Fatalf("an administrator: told %v (decided %v) after %d reads, want every name and no read", named, ok, reads)
	}
	if named, ok := r.svc.Grants.catalogNamesFor(r.ctx, r.reader, frame, counted); !ok || !slices.Equal(named, frame) || reads != 1 {
		t.Fatalf("the reader: told %v (decided %v) after %d reads, want both and one read", named, ok, reads)
	}
	failed := func(context.Context, []model.PID) ([]*model.ItemView, error) { return nil, errors.New("closed") }
	if named, ok := r.svc.Grants.catalogNamesFor(r.ctx, r.reader, frame, failed); ok || named != nil {
		t.Fatalf("a failed read: told %v (decided %v), want nothing decided", named, ok)
	}
}

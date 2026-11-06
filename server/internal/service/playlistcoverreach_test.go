package service

import (
	"bytes"
	"context"
	"errors"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
)

// coverReach is two libraries, an administrator who owns the playlists,
// and a reader granted the first library alone; each track carries its
// own cover.
type coverReach struct {
	ctx           context.Context
	svc           *Library
	owner, reader *UserCtx
	// seen are the first library's tracks, unseen the second's, by api pid.
	seen   []string
	unseen string
}

func newCoverReach(t *testing.T) coverReach {
	t.Helper()
	seenDir, unseenDir := t.TempDir(), t.TempDir()
	song := func(name, title string) fixtures.Spec {
		return fixtures.Spec{Name: name, Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": title, "ARTIST": "Cover Band", "ALBUM": title}}
	}
	if _, err := fixtures.Generate(seenDir, song("one", "Seen One"), song("two", "Seen Two")); err != nil {
		t.Fatal(err)
	}
	if _, err := fixtures.Generate(unseenDir, song("three", "Unseen Three")); err != nil {
		t.Fatal(err)
	}
	ctx, svc, owner := managedUploadFixture(t, Root{Name: "seen", Path: seenDir}, Root{Name: "unseen", Path: unseenDir})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatalf("scanning: %v", err)
	}
	var seenLib string
	for _, r := range svc.libraryRoots() {
		if r.Name == "seen" {
			seenLib = r.PID
		}
	}
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "reader", Password: "correct-horse", AccessMode: "granted",
		LibraryPIDs: []string{apiPID(PrefixLibrary, model.PID(seenLib))},
	})
	if err != nil {
		t.Fatal(err)
	}
	reader, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	page, err := svc.Items(ctx, owner, ItemFilter{}, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	r := coverReach{ctx: ctx, svc: svc, owner: owner, reader: reader}
	for i, it := range page.Items {
		switch it.Title {
		case "Seen One", "Seen Two":
			r.seen = append(r.seen, it.PID)
		case "Unseen Three":
			r.unseen = it.PID
		}
		giveCovers(t, ctx, svc, owner, []string{it.PID}, coverPNG(t, uint8(40+60*i)))
	}
	if len(r.seen) != 2 || r.unseen == "" {
		t.Fatalf("seen %v, unseen %q; want two and one", r.seen, r.unseen)
	}
	return r
}

// sharedList creates a shared static playlist the owner holds and opens
// it once, which stores its cover.
func (r coverReach) sharedList(t *testing.T, name string, members ...string) string {
	t.Helper()
	pl, err := r.svc.CreatePlaylist(r.ctx, r.owner, PlaylistCreate{
		Name: name, Kind: "static", Visibility: "shared", ItemPIDs: members,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := r.svc.PlaylistItems(r.ctx, r.owner, pl.PID, "", 50); err != nil {
		t.Fatal(err)
	}
	return pl.PID
}

// readerCovers reads a playlist's cover as the reader n times and answers
// how many times the list's members were read meanwhile. The catalog is
// let settle first: a sweep still rewriting after the scan moves what a
// kept answer stands on.
func (r coverReach) readerCovers(t *testing.T, reads *atomic.Int32, pl string, n int, want []byte) int32 {
	t.Helper()
	settleCatalogFeed(t, r.svc)
	before := reads.Load()
	for range n {
		blob, err := r.svc.Art(r.ctx, r.reader, pl, "", 0)
		if err != nil {
			t.Fatalf("the reader's cover: %v", err)
		}
		if want != nil && !bytes.Equal(blob.Bytes, want) {
			t.Fatal("the reader is not shown the cover it should be")
		}
	}
	return reads.Load() - before
}

// A reader's cover for somebody else's shared list costs no member read
// while every member the stored cover was drawn from is one the reader
// sees, and one member read, not one per request, when the reader is
// shown a member's cover instead, until something the answer stands on
// changes.
func TestAReadersSharedListCoverReadsBoundedMembers(t *testing.T) {
	t.Parallel()
	r := newCoverReach(t)
	var reads atomic.Int32
	r.svc.memberReadHook = func(*model.Playlist) { reads.Add(1) }

	seen := r.sharedList(t, "All seen", r.seen...)
	if n := r.readerCovers(t, &reads, seen, 5, nil); n != 0 {
		t.Errorf("five cover reads of a list drawn from members the reader sees read its members %d times, want none", n)
	}

	mixed := r.sharedList(t, "Partly unseen", r.unseen, r.seen[0])
	own, err := r.svc.Art(r.ctx, r.reader, r.seen[0], "", 0)
	if err != nil {
		t.Fatal(err)
	}
	if n := r.readerCovers(t, &reads, mixed, 5, own.Bytes); n != 1 {
		t.Errorf("five cover reads of a list drawn from a member the reader cannot see read its members %d times, want once", n)
	}
	r.svc.noteArtworkChanged(r.ctx)
	if n := r.readerCovers(t, &reads, mixed, 3, own.Bytes); n != 1 {
		t.Errorf("after an artwork change, three cover reads read the members %d times, want once", n)
	}
}

// A generated cover whose sources could not be recorded goes to no reader
// who may not see every member: the image is stored and then writing what
// it was drawn from fails, so the members it shows are not known, and the
// reader is shown a member it sees instead.
func TestACoverWithoutRecordedSourcesGoesToNoRestrictedReader(t *testing.T) {
	t.Parallel()
	r := newCoverReach(t)
	pl := r.sharedList(t, "Changing", r.seen[0])
	r.svc.coverRecordHook = func() error { return errors.New("cut short") }
	if err := r.svc.ReplacePlaylistItems(r.ctx, r.owner, pl, []string{r.unseen, r.seen[0]}, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := r.svc.PlaylistItems(r.ctx, r.owner, pl, "", 50); err != nil {
		t.Fatal(err)
	}
	unseen, err := r.svc.Art(r.ctx, r.owner, r.unseen, "", 0)
	if err != nil {
		t.Fatal(err)
	}
	if stored, err := r.svc.Art(r.ctx, r.owner, pl, "", 0); err != nil || !bytes.Equal(stored.Bytes, unseen.Bytes) {
		t.Fatalf("the owner's cover (%v) is not the one drawn from the new first member", err)
	}
	seen, err := r.svc.Art(r.ctx, r.reader, r.seen[0], "", 0)
	if err != nil {
		t.Fatal(err)
	}
	got, err := r.svc.Art(r.ctx, r.reader, pl, "", 0)
	if err != nil || !bytes.Equal(got.Bytes, seen.Bytes) {
		t.Errorf("the reader is served (%v) a cover other than the member it sees: one drawn from a member it cannot see", err)
	}
}

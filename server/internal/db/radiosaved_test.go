package db

import (
	"context"
	"errors"
	"fmt"
	"testing"
)

func savedSong(user, id, identity string) RadioSavedSong {
	return RadioSavedSong{
		ID:          id,
		UserID:      user,
		IdentityKey: identity,
		RawLine:     "Charlie Parker - Ornithology",
		Artist:      "Charlie Parker",
		Title:       "Ornithology",
		StationPID:  "rs-01JZX5N8QW3F4V9T2B7KDEXAMPLE",
		StationName: "FIP",
		CreatedAtNS: 1,
	}
}

func mustSave(t *testing.T, d *DB, s RadioSavedSong) RadioSavedSong {
	t.Helper()
	got, err := d.CreateRadioSavedSong(context.Background(), s)
	if err != nil {
		t.Fatalf("saving %s: %v", s.ID, err)
	}
	return got
}

func TestRadioSavedSongIsIdempotentOnIdentity(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-a")

	first := mustSave(t, d, savedSong("us-a", "rw-001", "ident-1"))
	if first.ID != "rw-001" {
		t.Fatalf("first save id = %q, want rw-001", first.ID)
	}
	// A second tap on the same announcement answers the row already
	// held rather than minting a second one: the heart is a toggle and
	// two devices can poll across one rollover.
	again, err := d.CreateRadioSavedSong(ctx, savedSong("us-a", "rw-002", "ident-1"))
	if err != nil {
		t.Fatalf("re-save = %v, want the held row", err)
	}
	if again.ID != "rw-001" {
		t.Fatalf("re-save id = %q, want the held rw-001", again.ID)
	}
	page, err := d.ListRadioSavedSongs(ctx, "us-a", "", 10)
	if err != nil || len(page) != 1 {
		t.Fatalf("list after re-save = (%d rows, %v), want exactly 1", len(page), err)
	}
}

func TestRadioSavedSongCapRefusesButHeldRowStillAnswers(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-a")

	for i := 0; i < radioSavedSongCap; i++ {
		mustSave(t, d, savedSong("us-a", fmt.Sprintf("rw-%04d", i), fmt.Sprintf("ident-%d", i)))
	}
	// A new song at the cap is the one refusal this table has.
	if _, err := d.CreateRadioSavedSong(ctx, savedSong("us-a", "rw-9999", "ident-new")); !errors.Is(err, ErrConflict) {
		t.Fatalf("save past the cap = %v, want ErrConflict", err)
	}
	// A song already held answers the held row even at the cap. The
	// insert stores nothing either way, so the conflict re-read has to
	// win over the cap check or a full list stops being able to report
	// what is on it.
	held, err := d.CreateRadioSavedSong(ctx, savedSong("us-a", "rw-8888", "ident-7"))
	if err != nil {
		t.Fatalf("re-save at the cap = %v, want the held row", err)
	}
	if held.ID != "rw-0007" {
		t.Fatalf("re-save at the cap id = %q, want the held rw-0007", held.ID)
	}
}

func TestRadioSavedSongsPageNewestFirst(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-a")
	for i := 0; i < 5; i++ {
		mustSave(t, d, savedSong("us-a", fmt.Sprintf("rw-%03d", i), fmt.Sprintf("ident-%d", i)))
	}

	first, err := d.ListRadioSavedSongs(ctx, "us-a", "", 2)
	if err != nil || len(first) != 2 {
		t.Fatalf("first page = (%d rows, %v), want 2", len(first), err)
	}
	if first[0].ID != "rw-004" || first[1].ID != "rw-003" {
		t.Fatalf("first page = %s, %s, want the two newest", first[0].ID, first[1].ID)
	}
	next, err := d.ListRadioSavedSongs(ctx, "us-a", first[1].ID, 2)
	if err != nil || len(next) != 2 {
		t.Fatalf("second page = (%d rows, %v), want 2", len(next), err)
	}
	if next[0].ID != "rw-002" || next[1].ID != "rw-001" {
		t.Fatalf("second page = %s, %s, want the next two", next[0].ID, next[1].ID)
	}
}

func TestRadioSavedSongsAreOnePerListener(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-a")
	mustCreateTestUser(t, d, "us-b")

	mustSave(t, d, savedSong("us-a", "rw-a", "ident-1"))
	// The same identity for another listener is another row, not a
	// conflict: the unique constraint is per user.
	mustSave(t, d, savedSong("us-b", "rw-b", "ident-1"))

	page, err := d.ListRadioSavedSongs(ctx, "us-b", "", 10)
	if err != nil || len(page) != 1 || page[0].ID != "rw-b" {
		t.Fatalf("us-b list = (%d rows, %v), want only their own", len(page), err)
	}
	// One listener's id never names another's row.
	if err := d.DeleteRadioSavedSong(ctx, "us-b", "rw-a"); err != nil {
		t.Fatalf("cross-user delete = %v, want silent success", err)
	}
	page, err = d.ListRadioSavedSongs(ctx, "us-a", "", 10)
	if err != nil || len(page) != 1 {
		t.Fatalf("us-a list after cross-user delete = (%d rows, %v), want 1", len(page), err)
	}
}

func TestRadioSavedSongDeleteIsAbsentIsSuccess(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-a")
	mustSave(t, d, savedSong("us-a", "rw-a", "ident-1"))

	if err := d.DeleteRadioSavedSong(ctx, "us-a", "rw-a"); err != nil {
		t.Fatal(err)
	}
	if err := d.DeleteRadioSavedSong(ctx, "us-a", "rw-a"); err != nil {
		t.Fatalf("second delete = %v, want silent success", err)
	}
	if _, err := d.RadioSavedSongByIdentity(ctx, "us-a", "ident-1"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("identity lookup after delete = %v, want ErrNotFound", err)
	}
}

func TestRadioSavedSongArtRoundTripsAndOversizeSavesArtless(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-a")

	withArt := savedSong("us-a", "rw-a", "ident-1")
	withArt.Art, withArt.ArtMime, withArt.ArtETag = []byte("\x89PNG-ish"), "image/png", `"abc"`
	saved := mustSave(t, d, withArt)
	if !saved.HasArt {
		t.Fatal("saved row reports no art, want art")
	}
	art, err := d.RadioSavedSongArt(ctx, "us-a", "rw-a")
	if err != nil || string(art.Art) != "\x89PNG-ish" || art.ArtMime != "image/png" {
		t.Fatalf("art read = (%q, %q, %v), want the stored bytes", art.Art, art.ArtMime, err)
	}
	// Only the owner's read finds it.
	if _, err := d.RadioSavedSongArt(ctx, "us-b", "rw-a"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("cross-user art read = %v, want ErrNotFound", err)
	}

	// Past the snapshot cap the row saves anyway, without the picture.
	oversize := savedSong("us-a", "rw-b", "ident-2")
	oversize.Art = make([]byte, RadioSavedArtMaxBytes+1)
	oversize.ArtMime, oversize.ArtETag = "image/jpeg", `"big"`
	big := mustSave(t, d, oversize)
	if big.HasArt {
		t.Fatal("oversize snapshot reports art, want the row saved artless")
	}
	if _, err := d.RadioSavedSongArt(ctx, "us-a", "rw-b"); !errors.Is(err, ErrNotFound) {
		t.Fatalf("oversize art read = %v, want ErrNotFound", err)
	}
}

func TestRadioSavedSongsCascadeWithTheUser(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	mustCreateTestUser(t, d, "us-a")
	mustSave(t, d, savedSong("us-a", "rw-a", "ident-1"))

	if err := d.DeleteUser(ctx, "us-a", false); err != nil {
		t.Fatal(err)
	}
	page, err := d.ListRadioSavedSongs(ctx, "us-a", "", 10)
	if err != nil || len(page) != 0 {
		t.Fatalf("list after user delete = (%d rows, %v), want none", len(page), err)
	}
}

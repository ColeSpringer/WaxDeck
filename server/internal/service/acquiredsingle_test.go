package service

import (
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxdeck/server/internal/match"
)

// A suggestion writes as the metadata editor does, without forcing: a
// field already holding the suggested value is left as it is, lock and
// all, and a lock someone set since keeps their value and says so.
func TestASuggestionKeepsALockedHandEdit(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := managedUploadFixture(t)
	_, id := pendingUploadEntry(t, ctx, svc, uc)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "", false); err != nil {
		t.Fatal(err)
	}
	e, err := svc.db.ReviewEntryByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	_, p := decidedEntry(t, ctx, svc, id)
	pid := model.PID(p.Tracks[0].PID)
	e.Origin = reviewOriginAcquire
	p.Suggested = &reviewOverride{Artist: "Nas", Title: "How Ya Livin'"}
	edit := func(fields map[string]string, lock model.LockChange) {
		t.Helper()
		if err := svc.lib.EditFields(ctx, pid, fields, waxbin.EditOptions{Lock: lock, Force: true}); err != nil {
			t.Fatal(err)
		}
	}
	item := func() *model.ItemView {
		t.Helper()
		it, err := svc.lib.Get(ctx, pid)
		if err != nil {
			t.Fatal(err)
		}
		return it
	}

	edit(map[string]string{"artist": "Nas", "title": "Hand Title"}, model.LockOn)
	warnings := svc.Ingest.writeSuggested(ctx, &e, &p, uc)
	if it := item(); it.Title != "Hand Title" || it.Artist != "Nas" {
		t.Errorf("item = %q by %q, want the locked hand edit kept", it.Title, it.Artist)
	}
	if len(warnings) != 1 || !strings.HasPrefix(warnings[0], filepath.Base(p.Tracks[0].Path)+": ") {
		t.Errorf("warnings = %q, want the file the lock kept named once", warnings)
	}

	// A lock on the title keeps only the title: the artist is its own edit.
	edit(map[string]string{"artist": "Hand Artist"}, model.LockOff)
	warnings = svc.Ingest.writeSuggested(ctx, &e, &p, uc)
	if it := item(); it.Title != "Hand Title" || it.Artist != "Nas" {
		t.Errorf("item = %q by %q, want the locked title kept and the suggested artist written", it.Title, it.Artist)
	}
	if len(warnings) != 1 {
		t.Errorf("warnings = %q, want the locked title's file named once", warnings)
	}

	edit(map[string]string{"title": "Hand Title"}, model.LockOff)
	if warnings := svc.Ingest.writeSuggested(ctx, &e, &p, uc); len(warnings) != 0 {
		t.Errorf("warnings = %q, want none: the locked artist already reads Nas", warnings)
	}
	if it := item(); it.Title != "How Ya Livin'" || it.Artist != "Nas" {
		t.Errorf("item = %q by %q, want the suggested title", it.Title, it.Artist)
	}
	prov, err := svc.lib.Provenance(ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	written := false
	for _, f := range prov {
		if f.Field == "title" {
			written = f.Source == model.SourceUser && f.Locked
		}
	}
	if !written {
		t.Errorf("title provenance = %+v, want a locked user edit", prov)
	}
}

// A suggestion corrects a channel credit and never thins a real one: an
// artist the track already credits, joined or as one of several credits,
// stays as it is, and only a title that differs is written.
func TestASuggestionKeepsEveryCreditedArtist(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := managedUploadFixture(t)
	_, id := pendingUploadEntry(t, ctx, svc, uc)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "", false); err != nil {
		t.Fatal(err)
	}
	e, err := svc.db.ReviewEntryByID(ctx, id)
	if err != nil {
		t.Fatal(err)
	}
	_, p := decidedEntry(t, ctx, svc, id)
	pid := model.PID(p.Tracks[0].PID)
	e.Origin = reviewOriginAcquire
	item := func() *model.ItemView {
		t.Helper()
		it, err := svc.lib.Get(ctx, pid)
		if err != nil {
			t.Fatal(err)
		}
		return it
	}

	if err := svc.lib.EditFields(ctx, pid, map[string]string{"artist": "Artist A, Artist B", "title": "Song (Official Audio)"},
		waxbin.EditOptions{Lock: model.LockOff, Force: true}); err != nil {
		t.Fatal(err)
	}
	p.Suggested = &reviewOverride{Artist: "artist b", Title: "Song"}
	if w := svc.Ingest.writeSuggested(ctx, &e, &p, uc); len(w) != 0 {
		t.Errorf("warnings = %q, want none", w)
	}
	if it := item(); it.Artist != "Artist A, Artist B" || it.Title != "Song" {
		t.Errorf("joined: item = %q by %q, want both artists kept and the suggested title", it.Title, it.Artist)
	}

	if _, _, err := svc.lib.SetCredits(ctx, pid, model.RoleArtist, []string{"Artist C", "Artist D"},
		waxbin.CreditEditOptions{Lock: model.LockOff, Force: true}); err != nil {
		t.Fatal(err)
	}
	before := item().Artist
	p.Suggested = &reviewOverride{Artist: "Artist D", Title: "Song"}
	if w := svc.Ingest.writeSuggested(ctx, &e, &p, uc); len(w) != 0 {
		t.Errorf("warnings = %q, want none", w)
	}
	if it := item(); it.Artist != before {
		t.Errorf("credits: artist = %q, want %q kept: the suggestion is one of its credits", it.Artist, before)
	}
	credits, err := svc.lib.Credits(ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, c := range credits {
		if c.Role == model.RoleArtist {
			names = append(names, c.Name)
		}
	}
	if !slices.Equal(names, []string{"Artist C", "Artist D"}) {
		t.Errorf("artist credits = %q, want both kept", names)
	}

	// An artist the track does not credit is the channel's, and is replaced.
	p.Suggested = &reviewOverride{Artist: "Someone Else", Title: "Song"}
	svc.Ingest.writeSuggested(ctx, &e, &p, uc)
	if it := item(); it.Artist != "Someone Else" {
		t.Errorf("uncredited: artist = %q, want the suggestion written", it.Artist)
	}
}

// An import as an audiobook ignores useSuggested, so an entry that
// offers no suggestion is not refused for asking.
func TestAnAudiobookImportIgnoresUseSuggested(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := managedUploadFixture(t)
	_, id := pendingUploadEntry(t, ctx, svc, uc)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "", true); KindOf(err) != KindInvalid {
		t.Fatalf("as music = %v, want invalid: the entry offers no suggestion", err)
	}
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "audiobook", true); err != nil {
		t.Fatalf("as an audiobook = %v, want it to stand", err)
	}
}

// With only the artist typed the title half is derived, as the judged title:
// the search asks for the song alone either way, and the group that names the
// recording is what picks it among the hits.
func TestAHalfTypedOverrideKeepsWhatNamesTheRecording(t *testing.T) {
	tracks := []match.Track{{Tags: map[string]string{
		"ARTIST": "Some Channel", "TITLE": "Band - Song (X Remix) (Official Audio)",
	}}}
	applyQueryOverride(tracks, &reviewOverride{Artist: "The Band"})
	if q := tracks[0].Query; q == nil || q.Artist != "The Band" || q.Title != "Song (X Remix)" {
		t.Fatalf("query = %+v, want the typed artist and the judged title", q)
	}
	untitled := []match.Track{{Tags: map[string]string{"ARTIST": "Band - Topic"}}}
	applyQueryOverride(untitled, &reviewOverride{Album: "An Album"})
	if q := untitled[0].Query; q == nil || q.Artist != "Band" || q.Title != "" {
		t.Fatalf("untitled query = %+v, want the derived artist and no title", q)
	}
}

// A reverted approval leaves a download unmatched again, so it gets the
// single's album an unmatched download is given.
func TestARevertedDownloadGetsItsSinglesAlbum(t *testing.T) {
	t.Parallel()
	f := openApprovalFixture(t, approvalSetup{origin: model.SourceYouTube})
	if err := f.svc.lib.EditFields(f.ctx, f.it.PID, map[string]string{"album": ""},
		waxbin.EditOptions{Lock: model.LockOff, Force: true}); err != nil {
		t.Fatal(err)
	}
	f.it.Album = ""
	e := pendingMatch(t, f.ctx, f.svc, approvedCandidate(), f.it)
	e.Origin = reviewOriginAcquire
	if err := f.svc.db.UpdateReviewEntry(f.ctx, e); err != nil {
		t.Fatal(err)
	}
	if _, _, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e.ID, "approve", "", "", false); err != nil {
		t.Fatalf("approve: %v", err)
	}
	if _, err := f.svc.Ingest.RevertReviewEntry(f.ctx, f.uc, e.ID); err != nil {
		t.Fatalf("revert: %v", err)
	}
	it, err := f.svc.lib.Get(f.ctx, f.it.PID)
	if err != nil {
		t.Fatal(err)
	}
	if it.Album != "Approved Cut - Single" || it.AlbumArtist != "Test Ensemble" {
		t.Errorf("album after the revert = %q by %q, want the single's album", it.Album, it.AlbumArtist)
	}
}

// A credit the artist string does not spell still counts: a guest
// credited on its own beside a "feat." artist line.
func TestACreditTheArtistLineDoesNotSpellCounts(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := managedUploadFixture(t)
	_, id := pendingUploadEntry(t, ctx, svc, uc)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, id, "as-is", "", "", false); err != nil {
		t.Fatal(err)
	}
	_, p := decidedEntry(t, ctx, svc, id)
	pid := model.PID(p.Tracks[0].PID)
	if _, _, err := svc.lib.SetCredits(ctx, pid, model.RoleArtist, []string{"Artist C", "Artist D"},
		waxbin.CreditEditOptions{Lock: model.LockOff, Force: true}); err != nil {
		t.Fatal(err)
	}
	it, err := svc.lib.Get(ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	// The line the artist string reads, apart from the credits behind it.
	it.Artist = "Artist C feat. Artist D"
	if !svc.Ingest.creditsArtist(ctx, it, "artist d") {
		t.Error("a credited artist the artist line does not split out reads as uncredited")
	}
	if svc.Ingest.creditsArtist(ctx, it, "Artist E") {
		t.Error("an uncredited artist reads as credited")
	}
}

package service

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/query"
	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"

	"github.com/colespringer/waxdeck/fixtures"
)

// fileTag reads one tag off a file.
func fileTag(t *testing.T, path string, key tag.Key) string {
	t.Helper()
	doc, err := waxlabel.ParseFile(context.Background(), path)
	if err != nil {
		t.Fatal(err)
	}
	if vals, ok := doc.Get(key); ok && len(vals) > 0 {
		return vals[0]
	}
	return ""
}

// writeUnsyncedIssues lists the items the rule for tags out of sync
// holds, after a sweep.
func writeUnsyncedIssues(t *testing.T, ctx context.Context, svc *Library) []string {
	t.Helper()
	if err := svc.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	issues, _, err := svc.ListHealthIssuesFor(ctx, ruleWriteUnsynced, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, it := range issues {
		out = append(out, it.PID)
	}
	return out
}

// A catalog-only edit owes the file its values: the rule lists the item,
// and its fix writes every owed value - a field, a credit, a custom tag -
// counting the item filled once nothing is owed.
func TestAWriteUnsyncedFixPaysWhatAnEditLeftOwed(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, pid := managedTrackFixture(t)
	if _, err := svc.EditItemMetadata(ctx, uc, pid, map[string]string{"genre": "Dub", "comment": "late night"},
		MetadataEditParams{Lock: true}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SetItemTag(ctx, uc, pid, "MOOD", []string{"calm"}, MetadataEditParams{Lock: true}); err != nil {
		t.Fatal(err)
	}
	if got := writeUnsyncedIssues(t, ctx, svc); len(got) != 1 || got[0] != pid {
		t.Fatalf("listed = %v, want the edited track", got)
	}
	start, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	sum := fixSummary(t, ctx, svc, uc, start.TaskID)
	if sum.Attempted != 1 || sum.Filled != 1 {
		t.Fatalf("summary %+v, want the track filled", sum)
	}
	if fileTag(t, path, tag.Genre) != "Dub" || fileTag(t, path, tag.Comment) != "late night" || fileTag(t, path, tag.Key("MOOD")) != "calm" {
		t.Fatalf("file = genre %q, comment %q, mood %q; want the edits written",
			fileTag(t, path, tag.Genre), fileTag(t, path, tag.Comment), fileTag(t, path, tag.Key("MOOD")))
	}
	if got := writeUnsyncedIssues(t, ctx, svc); len(got) != 0 {
		t.Fatalf("still listed = %v, want none", got)
	}
}

// A fix on an item whose file already carries its values does nothing
// and says so, rather than counting a fill.
func TestAWriteUnsyncedFixOnAnItemInSyncIsNotAFill(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pid := managedTrackFixture(t)
	start, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	sum := fixSummary(t, ctx, svc, uc, start.TaskID)
	if sum.Filled != 0 || sum.Skipped["already in sync"] != 1 {
		t.Fatalf("summary %+v, want the track skipped as already in sync", sum)
	}
}

// A value a clean-up pass normalized in the catalog alone is not counted
// against the file: a library-wide genre clean-up would otherwise list
// every item it touched.
func TestANormalizedValueIsNotOwedToTheRule(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _, pid := managedTrackFixture(t)
	_, bare, _ := parseAPIPID(pid)
	if _, err := svc.lib.EditManyFields(ctx, []model.PID{bare}, map[string]string{"genre": "Rock"},
		waxbin.EditOptions{Lock: model.LockUnchanged, Source: model.SourceNormalize}); err != nil {
		t.Fatal(err)
	}
	if got := writeUnsyncedIssues(t, ctx, svc); len(got) != 0 {
		t.Fatalf("listed = %v, want a normalized value left to the file", got)
	}
}

// Re-asserting a title its file supplied, to bring a merely unsynced
// file back in line, credits the tags with it, not a person.
func TestPayingUnsyncedDriftKeepsATagValueTheTags(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _, pid := managedTrackFixture(t)
	it, err := svc.getItem(ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.payWriteDrift(ctx, it, writeDrift{unsynced: true}); err != nil {
		t.Fatal(err)
	}
	prov, err := svc.lib.Provenance(ctx, it.PID)
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range prov {
		if p.Field == "title" && p.Source == model.SourceUser {
			t.Fatalf("title provenance = %+v, want it left the tags'", p)
		}
	}
}

// A cover cleared from a track has nothing of its own to embed: paying
// what the clear left owed does not make the album's picture the track's
// own, nor write it into the file.
func TestPayingOwedArtLeavesAClearedCoverCleared(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _, pid := managedTrackFixture(t)
	it, err := svc.getItem(ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.lib.SetEntityArt(ctx, model.ArtAlbum, it.AlbumPID, model.ArtRoleFront, coverPNG(t, 40),
		waxbin.ArtEditOptions{Source: model.SourceUser}); err != nil {
		t.Fatal(err)
	}
	if err := svc.payOwedArt(ctx, it, model.Attribution{Source: model.SourceUser}); err != nil {
		t.Fatal(err)
	}
	roles, err := svc.lib.ArtRoles(ctx, model.EntityRef{Type: model.ArtTrack, PID: it.PID})
	if err != nil {
		t.Fatal(err)
	}
	for _, r := range roles {
		if r.Role == model.ArtRoleFront && r.SourceHash != "" {
			t.Fatalf("the track holds a front cover of its own after the fix: %+v", r)
		}
	}
}

// A track's own cover set in the catalog alone is what paying owed art
// writes into its file.
func TestPayingOwedArtEmbedsTheTracksOwnCover(t *testing.T) {
	t.Parallel()
	ctx, svc, _, path, pid := managedTrackFixture(t)
	it, err := svc.getItem(ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.lib.SetItemArt(ctx, it.PID, model.ArtRoleFront, coverPNG(t, 40),
		waxbin.ArtEditOptions{Source: model.SourceUser}); err != nil {
		t.Fatal(err)
	}
	if err := svc.payOwedArt(ctx, it, model.Attribution{Source: model.SourceUser}); err != nil {
		t.Fatal(err)
	}
	doc, err := waxlabel.ParseFile(ctx, path)
	if err != nil {
		t.Fatal(err)
	}
	if len(doc.Pictures()) == 0 {
		t.Fatal("the track's own cover was not written into its file")
	}
}

// The fix grades an item by the files the sweep grades it by: a copy in
// a read-only library, which no write reaches, does not keep an item the
// rule no longer lists from counting as filled.
func TestAReadOnlyCopyDoesNotHoldAWriteDriftFixBack(t *testing.T) {
	t.Parallel()
	archive := t.TempDir()
	var paths []string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.Roots[0].Managed = true
		c.Roots = append(c.Roots, Root{Name: "archive", Path: archive})
		var err error
		if paths, err = fixtures.Generate(c.Roots[0].Path, fixtures.Spec{
			Name: "stray", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Stray", "ARTIST": "Nomad", "ALBUM": "Wander", "TRACKNUMBER": "1"},
		}); err != nil {
			t.Fatal(err)
		}
	})
	raw, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(archive, filepath.Base(paths[0])), raw, 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	libs, err := svc.lib.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, lib := range libs {
		if filepath.Clean(lib.DisplayRoot) == filepath.Clean(archive) {
			if err := svc.LibraryReadOnlySet(ctx, uc, apiPID(PrefixLibrary, lib.PID), true); err != nil {
				t.Fatal(err)
			}
		}
	}
	items, err := svc.lib.Query(ctx, query.New(query.EntityItems).Build(), "")
	if err != nil || len(items) != 1 {
		t.Fatalf("items = %v (%v), want the one track", items, err)
	}
	pid := apiPID(PrefixTrack, items[0].PID)
	if _, err := svc.EditItemMetadata(ctx, uc, pid, map[string]string{"genre": "Dub"}, MetadataEditParams{Lock: true}); err != nil {
		t.Fatal(err)
	}
	start, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	if sum := fixSummary(t, ctx, svc, uc, start.TaskID); sum.Filled != 1 {
		t.Fatalf("summary %+v, want the track filled", sum)
	}
	if got := writeUnsyncedIssues(t, ctx, svc); len(got) != 0 {
		t.Fatalf("still listed = %v, want none", got)
	}
}

// A write the item's own file refuses is skipped as refused, its values
// still owed.
func TestAWriteDriftFixTheFileRefusesIsSkippedAsRefused(t *testing.T) {
	t.Parallel()
	if runtime.GOOS == "windows" || os.Geteuid() == 0 {
		t.Skip("a folder cannot be made unwritable here")
	}
	ctx, svc, uc, path, pid := managedTrackFixture(t)
	if _, err := svc.EditItemMetadata(ctx, uc, pid, map[string]string{"genre": "Dub"}, MetadataEditParams{Lock: true}); err != nil {
		t.Fatal(err)
	}
	dir := filepath.Dir(path)
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
	start, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	if sum := fixSummary(t, ctx, svc, uc, start.TaskID); sum.Filled != 0 || sum.Skipped["write refused"] != 1 {
		t.Fatalf("summary %+v, want the track skipped as refused", sum)
	}
}

// A composer typed over the credit it retired is what the file is owed:
// the fix writes it, and re-asserting the retired credit, which has no
// names left, does not clear it from the catalog and the file.
func TestAWriteDriftFixKeepsAComposerTypedOverItsCredit(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, pid := managedTrackFixture(t)
	if _, err := svc.SetItemCredits(ctx, uc, pid, "composer", []string{"Ada Credit"}, MetadataEditParams{}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.EditItemMetadata(ctx, uc, pid, map[string]string{"composer": "Typed Composer"},
		MetadataEditParams{Lock: true}); err != nil {
		t.Fatal(err)
	}
	start, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	if sum := fixSummary(t, ctx, svc, uc, start.TaskID); sum.Filled != 1 {
		t.Fatalf("summary %+v, want the track filled", sum)
	}
	it, err := svc.getItem(ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	if it.Composer != "Typed Composer" || fileTag(t, path, tag.Composer) != "Typed Composer" {
		t.Fatalf("composer = catalog %q, file %q; want the typed value in both", it.Composer, fileTag(t, path, tag.Composer))
	}
}

// A composer credit a clean-up pass respelled in the catalog alone is
// paid under the clean-up's name: the file gets the column the catalog
// holds, and the retired credit, which has no names left, clears nothing.
func TestAWriteDriftFixPaysANormalizedComposerItsCreditStillOwes(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, pid := managedTrackFixture(t)
	_, bare, _ := parseAPIPID(pid)
	if _, err := svc.SetItemCredits(ctx, uc, pid, "composer", []string{"ada credit"}, MetadataEditParams{}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.EditManyFields(ctx, []model.PID{bare}, map[string]string{"composer": "Ada Credit"},
		waxbin.EditOptions{Lock: model.LockUnchanged, Source: model.SourceNormalize}); err != nil {
		t.Fatal(err)
	}
	start, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	if sum := fixSummary(t, ctx, svc, uc, start.TaskID); sum.Filled != 1 {
		t.Fatalf("summary %+v, want the track filled", sum)
	}
	it, err := svc.getItem(ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	if it.Composer != "Ada Credit" || fileTag(t, path, tag.Composer) != "Ada Credit" {
		t.Fatalf("composer = catalog %q, file %q; want the respelled value in both", it.Composer, fileTag(t, path, tag.Composer))
	}
	prov, err := svc.lib.Provenance(ctx, bare)
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range prov {
		if (p.Field == "composer" || p.Field == model.CreditField(model.RoleComposer)) && p.Source != model.SourceNormalize {
			t.Fatalf("provenance %s = %+v, want the clean-up's", p.Field, p.Attribution)
		}
	}
}

// A source's artist set over a person's credit is paid as the source's:
// the credit it retired is not re-asserted as a person's edit.
func TestAWriteDriftFixLeavesASourcesArtistTheSources(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, pid := managedTrackFixture(t)
	_, bare, _ := parseAPIPID(pid)
	if _, err := svc.SetItemCredits(ctx, uc, pid, "artist", []string{"Credit Person"}, MetadataEditParams{}); err != nil {
		t.Fatal(err)
	}
	if err := svc.lib.EditFields(ctx, bare, map[string]string{"artist": "Enriched Artist"}, waxbin.EditOptions{
		Source: model.SourceEnrichment, Provider: "musicbrainz",
	}); err != nil {
		t.Fatal(err)
	}
	start, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	if sum := fixSummary(t, ctx, svc, uc, start.TaskID); sum.Filled != 1 {
		t.Fatalf("summary %+v, want the track filled", sum)
	}
	if got := fileTag(t, path, tag.Artist); got != "Enriched Artist" {
		t.Fatalf("file artist = %q, want the source's value", got)
	}
	prov, err := svc.lib.Provenance(ctx, bare)
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range prov {
		if (p.Field == "artist" || p.Field == model.CreditField(model.RoleArtist)) && p.Source != model.SourceEnrichment {
			t.Fatalf("provenance %s = %+v, want the artist left the source's", p.Field, p.Attribution)
		}
	}
}

// Paying a fetched cover the catalog alone took keeps where it was
// fetched from, beside the source and provider.
func TestPayingOwedArtKeepsWhereTheCoverWasFetched(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pid := managedTrackFixture(t)
	it, err := svc.getItem(ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	const fetched = "https://covers.example.org/stray.png"
	if err := svc.lib.SetItemArt(ctx, it.PID, model.ArtRoleFront, coverPNG(t, 40), waxbin.ArtEditOptions{
		Source: model.SourceEnrichment, Provider: "musicbrainz", SourceURL: fetched,
	}); err != nil {
		t.Fatal(err)
	}
	start, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	if sum := fixSummary(t, ctx, svc, uc, start.TaskID); sum.Filled != 1 {
		t.Fatalf("summary %+v, want the track filled", sum)
	}
	p, err := svc.lib.ArtProvenance(ctx, model.EntityRef{Type: model.ArtTrack, PID: it.PID}, model.ArtRoleFront)
	if err != nil {
		t.Fatal(err)
	}
	if p.Source != model.SourceEnrichment || p.Provider != "musicbrainz" || p.SourceURL != fetched {
		t.Fatalf("cover attribution = %+v, want the fetch's source, provider and url", p.Attribution)
	}
}

// A write the files refused is a refusal only when nothing else in the
// pass failed outright.
func TestAWriteDriftPassThatAlsoFailedIsNotARefusal(t *testing.T) {
	t.Parallel()
	refused := &waxbin.WriteBackError{ItemPID: "tr-refused"}
	if !writeBackRefusedOnly(errors.Join(refused, &waxbin.WriteBackError{ItemPID: "tr-other"})) {
		t.Error("refusals alone did not read as a refusal")
	}
	if writeBackRefusedOnly(errors.Join(refused, errors.New("store gone"))) {
		t.Error("a refusal joined with a hard failure read as a refusal")
	}
	if writeBackRefusedOnly(errors.Join(errors.New("store gone"), fmt.Errorf("pay: %w", refused))) {
		t.Error("a hard failure joined with a wrapped refusal read as a refusal")
	}
}

// A file a refused write left unsynced is rewritten by the fix even when
// all it still owes is its album's value, which only the album's editor
// writes.
func TestAWriteDriftFixRewritesAnUnsyncedFileThatOwesOnlyItsAlbum(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pid := readOnlyFixture(t)
	it, err := svc.getItem(ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	if out, err := svc.EditEntity(ctx, "album", apiPID(PrefixAlbum, it.AlbumPID), map[string]string{"label": "Night Shift"},
		MetadataEditParams{WriteBack: true}); err != nil || len(out.Failures) != 1 {
		t.Fatalf("album edit = %+v (%v), want its write refused", out.Failures, err)
	}
	setLibrariesReadOnly(t, ctx, svc, uc, false)
	unsynced := func() bool {
		t.Helper()
		rows, err := svc.lib.FileDiagnostics(ctx, model.DiagnosticFilter{ItemPID: it.PID})
		if err != nil {
			t.Fatal(err)
		}
		for _, r := range rows {
			if r.Code == model.DiagTagWriteUnsynced || r.Code == model.DiagTagWriteLost {
				return true
			}
		}
		return false
	}
	if !unsynced() {
		t.Fatal("the refused write left no unsynced row")
	}
	start, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	fixSummary(t, ctx, svc, uc, start.TaskID)
	if unsynced() {
		t.Fatal("the fix left the file unsynced")
	}
}

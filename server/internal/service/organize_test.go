package service

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/organize"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// A read-only library's files stay where they are: the catalog leaves
// the library out and the counts say so, while a read-only server holds
// every move back.
func TestOrganizeLeavesAReadOnlyLibraryInPlace(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, _ := managedTrackFixture(t)
	profile := organize.DefaultProfileName
	if plan, err := svc.PreviewOrganize(ctx, uc, profile, nil); err != nil || plan.TotalActions != 1 || plan.Held != 0 {
		t.Fatalf("writable preview = %+v (%v), want the track's move", plan, err)
	}
	setServerReadOnly(t, ctx, svc, true)
	if plan, err := svc.PreviewOrganize(ctx, uc, profile, nil); err != nil || plan.TotalActions != 0 || plan.Held != 1 {
		t.Fatalf("read-only server preview = %+v (%v), want the move held", plan, err)
	}
	setServerReadOnly(t, ctx, svc, false)
	setLibrariesReadOnly(t, ctx, svc, uc, true)
	plan, err := svc.PreviewOrganize(ctx, uc, profile, nil)
	if err != nil || plan.TotalActions != 0 || plan.ReadOnlyLibraries != 1 {
		t.Fatalf("read-only library preview = %+v (%v), want the library left out", plan, err)
	}
	rep, err := svc.ApplyOrganize(ctx, uc, profile, nil)
	if err != nil || rep.Moved != 0 || rep.ReadOnlyLibraries != 1 {
		t.Fatalf("apply = %+v (%v), want the library left out", rep, err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("the track moved out of a read-only library: %v", err)
	}
}

// The listing says how many libraries organize can lay out, which is
// none until a root is managed.
func TestOrganizeProfilesCountTheManagedLibraries(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openEnrichFixture(t, func(*Config) {})
	if got, err := svc.OrganizeProfilesFor(ctx, uc); err != nil || got.ManagedLibraries != 0 || len(got.Profiles) == 0 {
		t.Fatalf("in-place profiles = %+v (%v), want the built-in and no managed library", got, err)
	}
	ctx, svc, uc, _, _ = managedTrackFixture(t)
	if got, err := svc.OrganizeProfilesFor(ctx, uc); err != nil || got.ManagedLibraries != 1 {
		t.Fatalf("managed profiles = %+v (%v), want one managed library", got, err)
	}
}

// managedAt is a service over dataDir whose configured root is managed
// and holds one track off the native layout.
func managedAt(t *testing.T, dataDir string) (context.Context, *Library, *UserCtx, func()) {
	t.Helper()
	ctx, svc, uc, stop := openServiceAt(t, dataDir, func(c *Config) {
		c.Roots[0].Managed = true
		if _, err := os.Stat(filepath.Join(c.Roots[0].Path, "stray.flac")); err == nil {
			return
		}
		if _, err := fixtures.Generate(c.Roots[0].Path, fixtures.Spec{
			Name: "stray", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Stray", "ARTIST": "Nomad", "ALBUM": "Wander", "TRACKNUMBER": "1"},
		}); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	return ctx, svc, uc, stop
}

func profileNamed(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, name string) (OrganizeProfileDTO, bool) {
	t.Helper()
	got, err := svc.OrganizeProfilesFor(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range got.Profiles {
		if p.Name == name {
			return p, true
		}
	}
	return OrganizeProfileDTO{}, false
}

// A saved profile lists with its templates and sample paths, outlives a
// restart, and plans a pass.
func TestASavedProfileListsWithSamplesAndSurvivesARestart(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, stop := managedAt(t, dataDir)
	saved, err := svc.PutOrganizeProfile(ctx, uc, "flat", OrganizeProfileInput{Music: "{artist}/{title}.{ext}", TagWrite: true})
	if err != nil {
		t.Fatal(err)
	}
	if saved.Music != "{artist}/{title}.{ext}" || saved.Audiobook == "" || !saved.TagWrite || saved.BuiltIn ||
		saved.Sample.Music != filepath.Join("Test Ensemble", "Amber Waves.flac") || saved.Sample.Podcast == "" {
		t.Fatalf("saved = %+v, want the templates, the inherited ones and samples", saved)
	}
	if native, ok := profileNamed(t, ctx, svc, uc, organize.DefaultProfileName); !ok || !native.BuiltIn {
		t.Fatalf("native = %+v (listed %v), want the built-in", native, ok)
	}
	stop()

	ctx, svc, uc, _ = managedAt(t, dataDir)
	if got, ok := profileNamed(t, ctx, svc, uc, "flat"); !ok || got.Music != saved.Music {
		t.Fatalf("after a restart flat = %+v (listed %v), want it back", got, ok)
	}
	plan, err := svc.PreviewOrganize(ctx, uc, "flat", nil)
	if err != nil || plan.TotalActions != 1 || plan.Actions[0].To != filepath.Join("Nomad", "Stray.flac") {
		t.Fatalf("plan = %+v (%v), want the track laid out flat", plan, err)
	}
}

// A profile a managed library lays out by stays until the library moves
// off it; a built-in is not the administrator's to delete.
func TestAProfileALibraryNamesCannotBeDeleted(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := managedAt(t, t.TempDir())
	if _, err := svc.PutOrganizeProfile(ctx, uc, "flat", OrganizeProfileInput{Music: "{title}.{ext}"}); err != nil {
		t.Fatal(err)
	}
	lib := apiPID(PrefixLibrary, model.PID(svc.libraryRoots()[0].PID))
	if info, err := svc.SetLibraryProfile(ctx, uc, lib, "flat"); err != nil || info.Profile != "flat" {
		t.Fatalf("set = %+v (%v), want flat", info, err)
	}
	if err := svc.DeleteOrganizeProfile(ctx, uc, "flat"); KindOf(err) != KindConflict {
		t.Fatalf("deleting a profile in use = %v, want a conflict", err)
	}
	if _, err := svc.SetLibraryProfile(ctx, uc, lib, organize.DefaultProfileName); err != nil {
		t.Fatal(err)
	}
	if err := svc.DeleteOrganizeProfile(ctx, uc, "flat"); err != nil {
		t.Fatalf("deleting a profile nothing names: %v", err)
	}
	if err := svc.DeleteOrganizeProfile(ctx, uc, organize.DefaultProfileName); KindOf(err) != KindInvalid {
		t.Errorf("deleting the built-in = %v, want invalid", err)
	}
	if err := svc.DeleteOrganizeProfile(ctx, uc, "gone"); KindOf(err) != KindNotFound {
		t.Errorf("deleting an unknown profile = %v, want not found", err)
	}
	if _, err := svc.SetLibraryProfile(ctx, uc, lib, "gone"); KindOf(err) != KindInvalid {
		t.Errorf("a library on an unknown profile = %v, want invalid", err)
	}
}

// A template that does not parse is refused, saved or previewed.
func TestABadTemplateIsInvalid(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := managedAt(t, t.TempDir())
	if _, err := svc.PutOrganizeProfile(ctx, uc, "bad", OrganizeProfileInput{Music: "{nope}/{title}.{ext}"}); KindOf(err) != KindInvalid {
		t.Errorf("saving an unknown field = %v, want invalid", err)
	}
	if _, err := svc.PreviewOrganizeProfile(ctx, uc, "bad", OrganizeProfileInput{Music: "{artist"}); KindOf(err) != KindInvalid {
		t.Errorf("previewing an open brace = %v, want invalid", err)
	}
	if _, ok := profileNamed(t, ctx, svc, uc, "bad"); ok {
		t.Error("a refused profile was listed")
	}
	sample, err := svc.PreviewOrganizeProfile(ctx, uc, "", OrganizeProfileInput{Podcast: "{podcast}/{episode}.{ext}"})
	if err != nil || sample.Podcast != filepath.Join("Night Shift Radio", "The Lighthouse Keeper.mp3") || sample.Music == "" {
		t.Errorf("preview = %+v (%v), want the podcast template and the native rest", sample, err)
	}
}

// A library's default profile is the catalog's: a restart keeps it and
// the read-only flag beside it.
func TestALibrarysProfileSurvivesARestart(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, stop := managedAt(t, dataDir)
	if _, err := svc.PutOrganizeProfile(ctx, uc, "flat", OrganizeProfileInput{Music: "{title}.{ext}"}); err != nil {
		t.Fatal(err)
	}
	lib := apiPID(PrefixLibrary, model.PID(svc.libraryRoots()[0].PID))
	if _, err := svc.SetLibraryProfile(ctx, uc, lib, "flat"); err != nil {
		t.Fatal(err)
	}
	if err := svc.LibraryReadOnlySet(ctx, uc, lib, true); err != nil {
		t.Fatal(err)
	}
	stop()
	ctx, svc, _, _ = managedAt(t, dataDir)
	infos, err := svc.Libraries(ctx)
	if err != nil || len(infos) != 1 || infos[0].Profile != "flat" || !infos[0].ReadOnly {
		t.Fatalf("libraries = %+v (%v), want flat and read-only", infos, err)
	}
}

// A library naming a profile no longer defined starts under the default
// rather than refusing to start.
func TestALibraryOnADeletedProfileStartsUnderTheDefault(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, stop := managedAt(t, dataDir)
	if _, err := svc.PutOrganizeProfile(ctx, uc, "flat", OrganizeProfileInput{Music: "{title}.{ext}"}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SetLibraryProfile(ctx, uc, apiPID(PrefixLibrary, model.PID(svc.libraryRoots()[0].PID)), "flat"); err != nil {
		t.Fatal(err)
	}
	stop()
	store, err := wdb.Open(context.Background(), filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.OrganizeProfilesDelete(context.Background(), "flat"); err != nil {
		t.Fatal(err)
	}
	store.Close()
	ctx, svc, _, _ = managedAt(t, dataDir)
	if infos, err := svc.Libraries(ctx); err != nil || infos[0].Profile != organize.DefaultProfileName {
		t.Fatalf("libraries = %+v (%v), want the default profile", infos, err)
	}
}

// A runtime library on a profile that is gone, as a fresh waxdeck.db or
// an older backup leaves it, starts under the default too: organizing
// every library would otherwise refuse.
func TestARuntimeLibraryOnADeletedProfileStartsUnderTheDefault(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, stop := managedAt(t, dataDir)
	if _, err := svc.PutOrganizeProfile(ctx, uc, "flat", OrganizeProfileInput{Music: "{title}.{ext}"}); err != nil {
		t.Fatal(err)
	}
	extra, err := svc.AddLibrary(ctx, uc, AddLibraryInput{Name: "extra", Path: t.TempDir(), Managed: true})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SetLibraryProfile(ctx, uc, extra.PID, "flat"); err != nil {
		t.Fatal(err)
	}
	stop()
	store, err := wdb.Open(context.Background(), filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.OrganizeProfilesDelete(context.Background(), "flat"); err != nil {
		t.Fatal(err)
	}
	store.Close()
	ctx, svc, uc, _ = managedAt(t, dataDir)
	infos, err := svc.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, info := range infos {
		if info.Profile != organize.DefaultProfileName {
			t.Errorf("library %s on %q, want the default profile", info.Name, info.Profile)
		}
	}
	if _, err := svc.PreviewOrganize(ctx, uc, "", nil); err != nil {
		t.Errorf("planning each library under its own = %v", err)
	}
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "library.profile"}, "", 10)
	if err != nil || len(page.Events) == 0 || page.Events[0].Detail["undefined"] != "flat" {
		t.Errorf("audit = %+v (%v), want the move to the default recorded", page.Events, err)
	}
}

// A template the catalog would parse to unbounded depth is refused before
// it gets there, on save and on preview alike.
func TestAnOversizedTemplateIsRefused(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := managedAt(t, t.TempDir())
	huge := OrganizeProfileInput{Music: strings.Repeat("<", maxTemplateLen+1)}
	if _, err := svc.PutOrganizeProfile(ctx, uc, "deep", huge); KindOf(err) != KindInvalid {
		t.Errorf("saving = %v, want invalid", err)
	}
	if _, err := svc.PreviewOrganizeProfile(ctx, uc, "deep", huge); KindOf(err) != KindInvalid {
		t.Errorf("previewing = %v, want invalid", err)
	}
}

// A profile name is counted in characters, trimmed wherever it arrives,
// and kept free of what a path segment cannot carry.
func TestProfileNamesAreCheckedAlike(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := managedAt(t, t.TempDir())
	music := OrganizeProfileInput{Music: "{title}.{ext}"}
	if _, err := svc.PutOrganizeProfile(ctx, uc, strings.Repeat("整", 22), music); err != nil {
		t.Errorf("a 22-character name = %v, want it saved", err)
	}
	for _, name := range []string{"rock/pop", "what?", "C# layout", `a\b`, strings.Repeat("x", 65)} {
		if _, err := svc.PutOrganizeProfile(ctx, uc, name, music); KindOf(err) != KindInvalid {
			t.Errorf("saving %q = %v, want invalid", name, err)
		}
	}
	if _, err := svc.PutOrganizeProfile(ctx, uc, " flat", music); err != nil {
		t.Fatal(err)
	}
	pid := apiPID(PrefixLibrary, model.PID(svc.libraryRoots()[0].PID))
	if _, err := svc.SetLibraryProfile(ctx, uc, pid, "flat "); err != nil {
		t.Errorf("naming the library's profile with a space = %v", err)
	}
	if _, err := svc.SetLibraryProfile(ctx, uc, pid, organize.DefaultProfileName); err != nil {
		t.Fatal(err)
	}
	if err := svc.DeleteOrganizeProfile(ctx, uc, " flat"); err != nil {
		t.Errorf("deleting by the name as typed = %v", err)
	}
}

// A saved row that no longer validates stays out of the catalog's set and
// out of every other save's way.
func TestAnInvalidStoredProfileBlocksNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := managedAt(t, t.TempDir())
	if err := svc.db.OrganizeProfilesUpsert(ctx, wdb.OrganizeProfile{Name: "broken", Music: "{unterminated"}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.PutOrganizeProfile(ctx, uc, "flat", OrganizeProfileInput{Music: "{title}.{ext}"}); err != nil {
		t.Fatalf("saving beside a broken row = %v", err)
	}
	if err := svc.DeleteOrganizeProfile(ctx, uc, "flat"); err != nil {
		t.Errorf("deleting beside a broken row = %v", err)
	}
}

// The samples carry every field the default templates read, so their
// optional groups show.
func TestSamplesShowEveryDefaultToken(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := managedAt(t, t.TempDir())
	sample, err := svc.PreviewOrganizeProfile(ctx, uc, "", OrganizeProfileInput{Music: "{genre}/{title}.{ext}"})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(sample.Music, "Ambient/") {
		t.Errorf("music sample = %q, want the sample's genre", sample.Music)
	}
	if !strings.Contains(sample.Audiobook, sampleBook.Subtitle) || !strings.Contains(sample.Audiobook, sampleBook.ASIN) {
		t.Errorf("book sample = %q, want its subtitle and ASIN groups", sample.Audiobook)
	}
}

// A saved profile reports what it sets itself, apart from what it
// inherits; a built-in nothing overrides reports nothing saved.
func TestAProfileSaysWhatItSetsItself(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := managedAt(t, t.TempDir())
	if _, err := svc.PutOrganizeProfile(ctx, uc, "flat", OrganizeProfileInput{Music: "{title}.{ext}"}); err != nil {
		t.Fatal(err)
	}
	flat, _ := profileNamed(t, ctx, svc, uc, "flat")
	if flat.Saved == nil || flat.Saved.Music != "{title}.{ext}" || flat.Saved.Audiobook != "" || flat.Audiobook == "" {
		t.Errorf("flat = %+v, want its own music template and an inherited audiobook one", flat)
	}
	if native, _ := profileNamed(t, ctx, svc, uc, organize.DefaultProfileName); native.Saved != nil {
		t.Errorf("the built-in reports saved templates %+v", native.Saved)
	}
}

// An empty profile plans each library under its own.
func TestAnEmptyProfilePlansEachLibraryUnderItsOwn(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := managedAt(t, t.TempDir())
	if _, err := svc.PutOrganizeProfile(ctx, uc, "flat", OrganizeProfileInput{Music: "{title}.{ext}"}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SetLibraryProfile(ctx, uc, apiPID(PrefixLibrary, model.PID(svc.libraryRoots()[0].PID)), "flat"); err != nil {
		t.Fatal(err)
	}
	plan, err := svc.PreviewOrganize(ctx, uc, "", nil)
	if err != nil || plan.TotalActions != 1 || plan.Actions[0].To != "Stray.flac" {
		t.Fatalf("plan = %+v (%v), want the library's own flat layout", plan, err)
	}
	if _, err := svc.PreviewOrganize(ctx, uc, "gone", nil); KindOf(err) != KindInvalid {
		t.Errorf("an unknown profile = %v, want invalid", err)
	}
}

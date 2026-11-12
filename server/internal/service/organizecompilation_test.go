package service

import (
	"context"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/organize"

	"github.com/colespringer/waxdeck/fixtures"
)

// managedCompilation is a service whose managed root holds one track of a
// compilation tagged with an album artist of its own.
func managedCompilation(t *testing.T) (context.Context, *Library, *UserCtx) {
	t.Helper()
	ctx, svc, uc, _ := openServiceAt(t, t.TempDir(), func(c *Config) {
		c.Roots[0].Managed = true
		if _, err := fixtures.Generate(c.Roots[0].Path, fixtures.Spec{
			Name: "drive", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Night Drive", "ARTIST": "Neon Coast", "ALBUMARTIST": "Harbor Selectors",
				"ALBUM": "Coastal Nights", "TRACKNUMBER": "4", "COMPILATION": "1"},
		}); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	return ctx, svc, uc
}

func sameFolder(a, b *string) bool {
	return (a == nil) == (b == nil) && (a == nil || *a == *b)
}

// A profile files a compilation where its folder says: Various Artists
// unless set, its own tagged album artist when set empty, and otherwise
// the folder named.
func TestACompilationFilesWhereItsProfileSays(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := managedCompilation(t)
	for _, tc := range []struct {
		name   string
		folder *string
		under  string
	}{
		{"unset", nil, "Various Artists"},
		{"own", ptrTo(""), "Harbor Selectors"},
		{"mixes", ptrTo("Mixes"), "Mixes"},
	} {
		if _, err := svc.Health.PutOrganizeProfile(ctx, uc, tc.name, OrganizeProfileInput{CompilationFolder: tc.folder}); err != nil {
			t.Fatalf("saving %s: %v", tc.name, err)
		}
		want := filepath.Join(tc.under, "Coastal Nights", "04 - Night Drive.flac")
		plan, err := svc.Health.PreviewOrganize(ctx, uc, tc.name, nil)
		if err != nil || plan.TotalActions != 1 || plan.Actions[0].To != want {
			t.Errorf("%s plans %+v (%v), want the compilation at %s", tc.name, plan.Actions, err, want)
		}
	}
}

// A profile reports its folder as saved, unset included, across a
// restart; a built-in reports none, and the audit names what was saved.
func TestACompilationFolderIsReportedAsSaved(t *testing.T) {
	t.Parallel()
	dataDir := t.TempDir()
	ctx, svc, uc, stop := managedAt(t, dataDir)
	want := map[string]*string{"unset": nil, "own": ptrTo(""), "mixes": ptrTo("Mixes")}
	for name, folder := range want {
		saved, err := svc.Health.PutOrganizeProfile(ctx, uc, name, OrganizeProfileInput{CompilationFolder: folder})
		if err != nil || !sameFolder(saved.CompilationFolder, folder) {
			t.Fatalf("saving %s = %v (%v), want the folder %v", name, saved.CompilationFolder, err, folder)
		}
	}
	page, err := svc.Audit.Events(ctx, AuditFilter{Action: "organize.profile"}, "", 10)
	if err != nil || len(page.Events) != 3 {
		t.Fatalf("audit = %+v (%v), want the three saves", page.Events, err)
	}
	for _, e := range page.Events {
		got, named := e.Detail["compilationFolder"]
		var saved any
		if folder := want[e.TargetName]; folder != nil {
			saved = *folder
		}
		if !named || got != saved {
			t.Errorf("%s audited the folder as %v (named %v), want %v", e.TargetName, got, named, saved)
		}
	}
	stop()

	ctx, svc, uc, _ = managedAt(t, dataDir)
	for name, folder := range want {
		got, ok := profileNamed(t, ctx, svc, uc, name)
		if !ok || !sameFolder(got.CompilationFolder, folder) {
			t.Errorf("after a restart %s = %v (listed %v), want %v", name, got.CompilationFolder, ok, folder)
		}
	}
	if native, _ := profileNamed(t, ctx, svc, uc, organize.DefaultProfileName); native.CompilationFolder != nil {
		t.Errorf("the built-in reports the folder %q", *native.CompilationFolder)
	}
	// Once saved it plans by the folder, not by the default.
	if plan, err := svc.Health.PreviewOrganize(ctx, uc, "own", nil); err != nil || plan.TotalActions != 1 {
		t.Errorf("planning after a restart = %+v (%v)", plan, err)
	}
}

// A folder is trimmed, bounded, and refused when it names no folder.
func TestACompilationFolderIsChecked(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := managedAt(t, t.TempDir())
	for raw, want := range map[string]string{"  Mixes  ": "Mixes", "   ": ""} {
		saved, err := svc.Health.PutOrganizeProfile(ctx, uc, "trimmed", OrganizeProfileInput{CompilationFolder: ptrTo(raw)})
		if err != nil || saved.CompilationFolder == nil || *saved.CompilationFolder != want {
			t.Errorf("saving %q = %v (%v), want %q", raw, saved.CompilationFolder, err, want)
		}
	}
	for _, bad := range []string{"...", strings.Repeat("x", maxCompilationFolderLen+1)} {
		in := OrganizeProfileInput{CompilationFolder: ptrTo(bad)}
		if _, err := svc.Health.PutOrganizeProfile(ctx, uc, "bad", in); KindOf(err) != KindInvalid {
			t.Errorf("saving %.12q = %v, want invalid", bad, err)
		}
		if _, err := svc.Health.PreviewOrganizeProfile(ctx, uc, "bad", in); KindOf(err) != KindInvalid {
			t.Errorf("previewing %.12q = %v, want invalid", bad, err)
		}
	}
	if _, ok := profileNamed(t, ctx, svc, uc, "bad"); ok {
		t.Error("a refused folder's profile was listed")
	}
}

// The preview takes the folder, and its sample shows where a compilation
// goes.
func TestAProfileSampleShowsWhereACompilationGoes(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := managedAt(t, t.TempDir())
	for _, tc := range []struct {
		folder *string
		under  string
	}{
		{nil, "Various Artists"},
		{ptrTo(""), sampleCompilation.AlbumArtist},
		{ptrTo("Mixes"), "Mixes"},
	} {
		sample, err := svc.Health.PreviewOrganizeProfile(ctx, uc, "", OrganizeProfileInput{CompilationFolder: tc.folder})
		if err != nil || !strings.HasPrefix(sample.Compilation, tc.under+string(filepath.Separator)) {
			t.Errorf("folder %v samples %q (%v), want it under %s", tc.folder, sample.Compilation, err, tc.under)
		}
		if !strings.HasPrefix(sample.Music, sampleTrack.AlbumArtist) {
			t.Errorf("folder %v moved the plain track: %q", tc.folder, sample.Music)
		}
	}
	saved, err := svc.Health.PutOrganizeProfile(ctx, uc, "mixes", OrganizeProfileInput{CompilationFolder: ptrTo("Mixes")})
	if err != nil || !strings.HasPrefix(saved.Sample.Compilation, "Mixes"+string(filepath.Separator)) {
		t.Errorf("saved sample = %+v (%v), want the compilation under Mixes", saved.Sample, err)
	}
}

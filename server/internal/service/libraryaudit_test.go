package service

import (
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/organize"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// podcastLibraryWithAnEpisode brings the podcast library into being the
// way the first download does, and answers its pid and the episode.
func podcastLibraryWithAnEpisode(t *testing.T, f stubFeedFixture) (libPID string, episode model.PID) {
	t.Helper()
	sub := f.subscribe(t, "https://feeds.example/one", "rss")
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "one", Codec: fixtures.CodecMP3, Container: fixtures.ContainerMP3, Duration: 2 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	_, episode, _ = parseAPIPID(showEpisodePIDs(t, f, sub.Show.PID)[0])
	if _, err := f.svc.lib.Podcasts().ImportEpisodeFile(f.ctx, episode, paths[0], false); err != nil {
		t.Fatal(err)
	}
	libPID, _ = f.svc.podcastLibrary(f.ctx)
	if libPID == "" {
		t.Fatal("no podcast library after a fetch")
	}
	return libPID, episode
}

func auditedLibraryNames(t *testing.T, f stubFeedFixture, action string) []string {
	t.Helper()
	page, err := f.svc.AuditEvents(f.ctx, wdb.AuditFilter{Action: action}, "", 50)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, e := range page.Events {
		out = append(out, e.TargetName)
	}
	return out
}

// A library switch names the library it moved. The podcast library has
// no root in the console's table, so it is named the way the server
// names it everywhere else. Turning the folder fallback off is the one
// switch the catalog accepts on it (the others refuse a podcast library
// outright, as does a restore into it), so that is the entry to read.
func TestALibrarySwitchNamesThePodcastLibrary(t *testing.T) {
	t.Parallel()
	f := openStubFeeds(t, &stubFeed{kind: model.SourceRSS, n: 1, prefix: "Episode"})
	podcasts, _ := podcastLibraryWithAnEpisode(t, f)
	roots := f.svc.libraryRoots()
	if len(roots) != 1 {
		t.Fatalf("roots = %+v, want the one library", roots)
	}

	for _, c := range []struct{ name, pid string }{
		{"podcasts", podcasts},
		{roots[0].Name, roots[0].PID},
	} {
		api := apiPID(PrefixLibrary, model.PID(c.pid))
		if err := f.svc.LibraryFolderFallbackSet(f.ctx, f.uc, api, false); err != nil {
			t.Fatalf("switching %s: %v", c.name, err)
		}
	}
	got := auditedLibraryNames(t, f, "library.folder-fallback")
	slices.Sort(got)
	if !slices.Equal(got, []string{"lib", "podcasts"}) {
		t.Errorf("library.folder-fallback entries name %q, want lib and the podcast library", got)
	}
}

// The podcast library refuses the switches that would make an entry
// without a name, so there is nothing else to name.
func TestThePodcastLibraryRefusesTheOtherSwitches(t *testing.T) {
	t.Parallel()
	f := openStubFeeds(t, &stubFeed{kind: model.SourceRSS, n: 1, prefix: "Episode"})
	podcasts, _ := podcastLibraryWithAnEpisode(t, f)
	api := apiPID(PrefixLibrary, model.PID(podcasts))

	if err := f.svc.LibraryReadOnlySet(f.ctx, f.uc, api, true); KindOf(err) != KindInvalid {
		t.Errorf("flagging it read-only = %v, want invalid", err)
	}
	if err := f.svc.LibraryFolderFallbackSet(f.ctx, f.uc, api, true); KindOf(err) != KindInvalid {
		t.Errorf("turning its folder fallback on = %v, want invalid", err)
	}
	if err := f.svc.SetLibraryMatching(f.ctx, f.uc, api, LibraryMatching{Mode: "review"}); KindOf(err) != KindInvalid {
		t.Errorf("setting its matching = %v, want invalid", err)
	}
	for _, action := range []string{"library.read-only", "library.matching"} {
		if got := auditedLibraryNames(t, f, action); len(got) != 0 {
			t.Errorf("%s recorded %q for a refused switch", action, got)
		}
	}
}

// Choosing the profile a managed library is laid out by names the library
// in its audit entry, as the other library switches do.
func TestAProfileChoiceNamesTheLibrary(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := managedAt(t, t.TempDir())
	root := svc.libraryRoots()[0]
	apiLib := apiPID(PrefixLibrary, model.PID(root.PID))
	if _, err := svc.SetLibraryProfile(ctx, uc, apiLib, organize.DefaultProfileName); err != nil {
		t.Fatal(err)
	}
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "library.profile", TargetPID: apiLib}, "", 10)
	if err != nil || len(page.Events) == 0 {
		t.Fatalf("library.profile audit = %+v (%v), want the choice recorded", page.Events, err)
	}
	if got := page.Events[0]; got.TargetName != root.Name {
		t.Fatalf("library.profile names %q, want the library's name %q", got.TargetName, root.Name)
	}
}

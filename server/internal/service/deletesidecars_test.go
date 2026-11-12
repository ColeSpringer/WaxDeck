package service

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"

	"github.com/colespringer/waxdeck/fixtures"
)

// touchSidecarFiles writes small files into dir, a sidecar or a stray each.
func touchSidecarFiles(t *testing.T, dir string, names ...string) {
	t.Helper()
	for _, name := range names {
		if err := os.WriteFile(filepath.Join(dir, name), []byte("sidecar"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

// sidecarsAcross is the sidecars across a plan's entries, sorted.
func sidecarsAcross(res DeleteItemsResultDTO) []string {
	var out []string
	for _, e := range res.Entries {
		out = append(out, e.Sidecars...)
	}
	slices.Sort(out)
	return out
}

// A plan names the covers, lyrics and other files that carry a deleted
// file's name, as places in the library like its files, and leaves out
// the folder's own cover and whatever else is not named for the file.
// What it names is what the delete then takes.
func TestADeletePlanNamesTheSidecarsThatGoWithItsFiles(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, root, tracks := newTrashFixture(t, "Words")
	tr := tracks["Words"]
	folder := filepath.Join(root, "Words")
	// keep.bin is no companion, so it keeps the folder and what is in it.
	touchSidecarFiles(t, folder, "track.lrc", "track.jpg", "cover.jpg", "notes.txt", "keep.bin")

	want := []string{"Words/track.jpg", "Words/track.lrc"}
	plan, err := svc.Tools.DeleteItems(ctx, admin, []string{tr.pid}, "trash", true)
	if err != nil {
		t.Fatal(err)
	}
	if got := sidecarsAcross(plan); !slices.Equal(got, want) {
		t.Fatalf("plan sidecars = %q, want %q", got, want)
	}
	for _, p := range sidecarsAcross(plan) {
		if filepath.IsAbs(p) || strings.Contains(p, root) {
			t.Errorf("sidecar %q names the server's folder", p)
		}
	}
	for _, name := range want {
		trashFileStillThere(t, filepath.Join(root, filepath.FromSlash(name)), "a sidecar the dry run only named")
	}

	res, err := svc.Tools.DeleteItems(ctx, admin, []string{tr.pid}, "trash", false)
	if err != nil {
		t.Fatal(err)
	}
	if got := sidecarsAcross(res); !slices.Equal(got, want) {
		t.Errorf("applied sidecars = %q, want %q", got, want)
	}
	for _, name := range want {
		if _, err := os.Stat(filepath.Join(root, filepath.FromSlash(name))); !os.IsNotExist(err) {
			t.Errorf("%s is still in the library after the delete: %v", name, err)
		}
	}
	for _, name := range []string{"cover.jpg", "notes.txt"} {
		trashFileStillThere(t, filepath.Join(folder, name), name+", which the plan did not name")
	}
}

// Files of one name share their sidecars, so a delete of one of them
// takes none and says so, and a delete of all of them names each once,
// with the last to go.
func TestASidecarAnotherFileStillUsesIsNotNamedUntilBothGo(t *testing.T) {
	t.Parallel()
	var root string
	ctx, svc, admin := openEnrichFixture(t, func(c *Config) {
		c.Roots[0].Managed = true
		root = c.Roots[0].Path
	})
	folder := filepath.Join(root, "Pair")
	if _, err := fixtures.Generate(folder,
		fixtures.Spec{Name: "song", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Song Lossless", "ARTIST": "Pair", "ALBUM": "Twice"}},
		fixtures.Spec{Name: "song", Codec: fixtures.CodecMP3, Duration: 3 * time.Second,
			Tags: map[string]string{"TITLE": "Song Small", "ARTIST": "Pair", "ALBUM": "Twice"}},
	); err != nil {
		t.Fatal(err)
	}
	touchSidecarFiles(t, folder, "song.lrc", "song.jpg")
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	flac, mp3 := itemPIDByTitle(t, ctx, svc, admin, "Song Lossless"), itemPIDByTitle(t, ctx, svc, admin, "Song Small")

	one, err := svc.Tools.DeleteItems(ctx, admin, []string{flac}, "trash", true)
	if err != nil {
		t.Fatal(err)
	}
	if got := sidecarsAcross(one); len(got) != 0 {
		t.Errorf("one of the pair names %q, want none while the other still uses them", got)
	}

	both, err := svc.Tools.DeleteItems(ctx, admin, []string{flac, mp3}, "trash", true)
	if err != nil {
		t.Fatal(err)
	}
	want := []string{"Pair/song.jpg", "Pair/song.lrc"}
	if got := sidecarsAcross(both); !slices.Equal(got, want) {
		t.Fatalf("both of the pair name %q, want each sidecar once: %q", got, want)
	}
	owners := 0
	for _, e := range both.Entries {
		if len(e.Sidecars) > 0 {
			owners++
		}
	}
	if owners != 1 {
		t.Errorf("%d entries carry the sidecars, want the one whose file goes last", owners)
	}

	if _, err := svc.Tools.DeleteItems(ctx, admin, []string{flac}, "trash", false); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"song.lrc", "song.jpg"} {
		trashFileStillThere(t, filepath.Join(folder, name), name+" after one of the pair went")
	}
	res, err := svc.Tools.DeleteItems(ctx, admin, []string{mp3}, "trash", false)
	if err != nil {
		t.Fatal(err)
	}
	if got := sidecarsAcross(res); !slices.Equal(got, want) {
		t.Errorf("the last of the pair names %q, want %q", got, want)
	}
	for _, name := range []string{"song.lrc", "song.jpg"} {
		if _, err := os.Stat(filepath.Join(folder, name)); !os.IsNotExist(err) {
			t.Errorf("%s is still in place after the last of the pair went: %v", name, err)
		}
	}
}

// A caller who sees only some of an item's files is told the sidecars of
// the files their delete takes, not of a copy in a library out of their
// reach, which stays with its own; and a delete of one file names that
// file's alone.
func TestAPlanNamesOnlyTheSidecarsOfFilesTheCallerDeletes(t *testing.T) {
	t.Parallel()
	f := newTrashCopyFixture(t)
	touchSidecarFiles(t, f.homeDir, "stray.lrc")
	touchSidecarFiles(t, f.copyDir, "stray.jpg")

	admin, err := f.svc.Tools.DeleteItems(f.ctx, f.admin, []string{f.pid}, "trash", true)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := sidecarsAcross(admin), []string{"stray.jpg", "stray.lrc"}; !slices.Equal(got, want) {
		t.Errorf("administrator's plan names %q, want the track's and its copy's: %q", got, want)
	}

	curator, err := f.svc.Tools.DeleteItems(f.ctx, f.caller(true, f.home), []string{f.pid}, "trash", true)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := sidecarsAcross(curator), []string{"stray.lrc"}; !slices.Equal(got, want) {
		t.Errorf("a caller seeing only the home library is told %q, want %q", got, want)
	}

	one, err := f.svc.Tools.DeleteItemFiles(f.ctx, f.admin, f.pid, []string{string(f.copy.FilePID)}, "trash", true)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := sidecarsAcross(one), []string{"stray.jpg"}; !slices.Equal(got, want) {
		t.Errorf("deleting the copy alone names %q, want %q", got, want)
	}
}

// An applied delete names the sidecars that left with the files: one the
// delete did not take, though the plan named it, stays out of the list
// that says what went.
func TestAnAppliedDeleteNamesOnlyTheSidecarsThatLeft(t *testing.T) {
	t.Parallel()
	ctx, svc, admin, root, tracks := newTrashFixture(t, "Words")
	tr := tracks["Words"]
	folder := filepath.Join(root, "Words")
	touchSidecarFiles(t, folder, "track.lrc", "track.jpg")
	svc.Tools.deleteApplyHook = func(context.Context) {
		// The lyrics stop being a file between the plan and the move.
		if err := os.Remove(filepath.Join(folder, "track.lrc")); err != nil {
			t.Error(err)
		}
		if err := os.Mkdir(filepath.Join(folder, "track.lrc"), 0o755); err != nil {
			t.Error(err)
		}
	}
	res, err := svc.Tools.DeleteItems(ctx, admin, []string{tr.pid}, "trash", false)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := sidecarsAcross(res), []string{"Words/track.jpg"}; !slices.Equal(got, want) {
		t.Errorf("applied sidecars = %q, want only the cover that left: %q", got, want)
	}
	trashFileStillThere(t, filepath.Join(folder, "track.lrc"), "the lyrics the move did not take")
}

// A file the delete could not remove keeps its sidecars and does not
// name them as gone.
func TestAFileThatStaysKeepsItsSidecarsOutOfTheList(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	ctx, svc, admin, root, tracks := newTrashFixture(t, "Open", "Locked")
	touchSidecarFiles(t, filepath.Join(root, "Open"), "track.lrc")
	touchSidecarFiles(t, filepath.Join(root, "Locked"), "track.lrc")
	lockFolder(t, filepath.Join(root, "Locked"))
	res, err := svc.Tools.DeleteItems(ctx, admin, []string{tracks["Open"].pid, tracks["Locked"].pid}, "trash", false)
	if err != nil {
		t.Fatal(err)
	}
	if got, want := sidecarsAcross(res), []string{"Open/track.lrc"}; !slices.Equal(got, want) {
		t.Errorf("applied sidecars = %q, want the file that went's alone: %q", got, want)
	}
	for _, e := range res.Entries {
		if e.PID == tracks["Locked"].pid && len(e.Sidecars) != 0 {
			t.Errorf("the entry that stayed names %q", e.Sidecars)
		}
	}
	trashFileStillThere(t, filepath.Join(root, "Locked", "track.lrc"), "the sidecar of the file that stayed")
}

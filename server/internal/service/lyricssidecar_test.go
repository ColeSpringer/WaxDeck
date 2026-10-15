package service

import (
	"io/fs"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// sidecarSiblingBeside generates an MP3 named like the audio at path, in
// its folder, which a scan would hand path's .lrc too, and answers the
// .lrc they share.
func sidecarSiblingBeside(t *testing.T, path string) string {
	t.Helper()
	stem := strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	if _, err := fixtures.Generate(filepath.Dir(path), fixtures.Spec{
		Name: stem, Codec: fixtures.CodecMP3, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Another " + stem},
	}); err != nil {
		t.Fatal(err)
	}
	return lyricsSidecar(path)
}

// Writing lyrics back refuses a sidecar another audio file of that name
// reads, as clearing them does: the other file's lyrics stay its own.
func TestWritingLyricsBackLeavesASidecarAnotherFileReads(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, pid := managedTrackFixture(t)
	sidecar := sidecarSiblingBeside(t, path)
	const theirs = "[00:00.50]Theirs\n"
	if err := os.WriteFile(sidecar, []byte(theirs), 0o644); err != nil {
		t.Fatal(err)
	}
	out, err := svc.SetItemLyrics(ctx, uc, pid, "[00:00.50]Mine\n", "", MetadataEditParams{WriteBack: true})
	if err != nil {
		t.Fatal(err)
	}
	if len(out.Failures) != 1 || !strings.Contains(out.Failures[0].Reason, "reads the sidecar too") {
		t.Fatalf("failures = %+v, want the shared sidecar refused", out.Failures)
	}
	if got, err := os.ReadFile(sidecar); err != nil || string(got) != theirs {
		t.Fatalf("sidecar = %q (%v), want the other file's lyrics kept", got, err)
	}
}

// A sidecar in a folder that cannot be listed may be another file's, so
// clearing lyrics with write-back keeps it and says it could not check.
func TestClearingLyricsKeepsASidecarItCannotCheck(t *testing.T) {
	t.Parallel()
	if runtime.GOOS == "windows" || os.Geteuid() == 0 {
		t.Skip("a folder cannot be made unlistable here")
	}
	ctx, svc, uc, path, pid := managedTrackFixture(t)
	if out, err := svc.SetItemLyrics(ctx, uc, pid, "[00:00.50]Mine\n", "", MetadataEditParams{WriteBack: true}); err != nil || len(out.Failures) != 0 {
		t.Fatalf("set = %+v (%v), want the sidecar written", out.Failures, err)
	}
	dir := filepath.Dir(path)
	if err := os.Chmod(dir, 0o300); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
	out, err := svc.ClearItemLyrics(ctx, uc, pid, MetadataEditParams{WriteBack: true})
	if err != nil {
		t.Fatal(err)
	}
	if len(out.Failures) != 1 || !strings.Contains(out.Failures[0].Reason, "could not be checked") {
		t.Fatalf("failures = %+v, want the sidecar kept as unchecked", out.Failures)
	}
	if _, err := os.Lstat(lyricsSidecar(path)); err != nil {
		t.Fatalf("the sidecar went: %v", err)
	}
}

// A carved track has no sidecar of its own, a scan reading none into
// one, so clearing its lyrics with write-back is a clean clear that
// leaves the rip's .lrc alone.
func TestClearingACarvedTracksLyricsWritingBackRefusesNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCueFixture(t)
	one, _, _ := carvedTracks(t, ctx, svc, uc)
	it, err := svc.getVisibleItem(ctx, uc, one)
	if err != nil {
		t.Fatal(err)
	}
	ripSidecar := lyricsSidecar(string(it.Path))
	if err := os.WriteFile(ripSidecar, []byte("[00:00.50]The rip's\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SetItemLyrics(ctx, uc, one, "[00:00.50]Carved\n", "", MetadataEditParams{}); err != nil {
		t.Fatal(err)
	}
	out, err := svc.ClearItemLyrics(ctx, uc, one, MetadataEditParams{WriteBack: true})
	if err != nil || len(out.Failures) != 0 {
		t.Fatalf("clear = %+v (%v), want a clean clear", out.Failures, err)
	}
	if _, err := os.Stat(ripSidecar); err != nil {
		t.Fatalf("the rip's sidecar went: %v", err)
	}
}

// A mount that refuses a mode change still takes the sidecar, as it
// takes a tool's piece: the mode is best effort. Not parallel: it stands
// the refusing mount in for every crash-safe write.
func TestASidecarIsWrittenWhereTheMountRefusesItsMode(t *testing.T) {
	chmod := chmodTempFile
	chmodTempFile = func(*os.File, os.FileMode) error { return fs.ErrPermission }
	t.Cleanup(func() { chmodTempFile = chmod })
	path := filepath.Join(t.TempDir(), "song.lrc")
	if err := writeFileCrashSafe(path, []byte("lyrics\n"), 0o644); err != nil {
		t.Fatalf("write = %v, want the sidecar written without its mode", err)
	}
	if got, err := os.ReadFile(path); err != nil || string(got) != "lyrics\n" {
		t.Fatalf("sidecar = %q (%v), want the lyrics", got, err)
	}
}

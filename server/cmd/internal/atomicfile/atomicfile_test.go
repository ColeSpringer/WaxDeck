package atomicfile

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestWriteIfChangedCreatesTheFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "out.txt")
	if err := WriteIfChanged(path, []byte("new")); err != nil {
		t.Fatal(err)
	}
	if got, err := os.ReadFile(path); err != nil || string(got) != "new" {
		t.Fatalf("read %q, %v", got, err)
	}
	if st, err := os.Stat(path); err != nil || st.Mode().Perm() != 0o644 {
		t.Errorf("a new file's mode is %v (%v), want 644", st.Mode().Perm(), err)
	}
	wantOnly(t, filepath.Dir(path), "out.txt")
}

// An unchanged file is not rewritten, so its mtime stays: make reads the
// generated files' mtimes to decide what to rebuild.
func TestWriteIfChangedLeavesAnUnchangedFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "out.txt")
	if err := os.WriteFile(path, []byte("same"), 0o644); err != nil {
		t.Fatal(err)
	}
	past := time.Now().Add(-time.Hour).Truncate(time.Second)
	if err := os.Chtimes(path, past, past); err != nil {
		t.Fatal(err)
	}
	if err := WriteIfChanged(path, []byte("same")); err != nil {
		t.Fatal(err)
	}
	if st, err := os.Stat(path); err != nil || !st.ModTime().Equal(past) {
		t.Errorf("an unchanged file was rewritten: mtime %v, want %v (%v)", st.ModTime(), past, err)
	}
}

func TestWriteIfChangedKeepsTheMode(t *testing.T) {
	path := filepath.Join(t.TempDir(), "out.txt")
	if err := os.WriteFile(path, []byte("old"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := WriteIfChanged(path, []byte("new")); err != nil {
		t.Fatal(err)
	}
	if got, _ := os.ReadFile(path); string(got) != "new" {
		t.Errorf("read %q, want new", got)
	}
	if st, err := os.Stat(path); err != nil || st.Mode().Perm() != 0o600 {
		t.Errorf("mode %v (%v), want the file's own 600", st.Mode().Perm(), err)
	}
	wantOnly(t, filepath.Dir(path), "out.txt")
}

// A write that cannot complete leaves the old file whole.
func TestWriteIfChangedFailsWithoutTouchingTheFile(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root writes into a read-only directory")
	}
	dir := t.TempDir()
	path := filepath.Join(dir, "out.txt")
	if err := os.WriteFile(path, []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(dir, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(dir, 0o755) })
	if err := WriteIfChanged(path, []byte("new")); err == nil {
		t.Fatal("a write into a read-only directory succeeded")
	}
	if got, _ := os.ReadFile(path); string(got) != "old" {
		t.Errorf("read %q, want old", got)
	}
	wantOnly(t, dir, "out.txt")
}

// A write that fails once its temp file exists, at the rename over a
// directory, removes the temp file.
func TestWriteIfChangedFailingLateLeavesNoTempFile(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "out.txt")
	if err := os.MkdirAll(filepath.Join(path, "inside"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := WriteIfChanged(path, []byte("new")); err == nil {
		t.Fatal("a write over a non-empty directory succeeded")
	}
	wantOnly(t, dir, "out.txt")
	wantOnly(t, path, "inside")
}

// wantOnly fails unless dir holds exactly the named entries: no temp file
// is left behind.
func wantOnly(t *testing.T, dir string, names ...string) {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, e := range entries {
		got = append(got, e.Name())
	}
	if strings.Join(got, ",") != strings.Join(names, ",") {
		t.Errorf("%s holds %v, want %v", dir, got, names)
	}
}

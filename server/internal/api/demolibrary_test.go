package api

import (
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"sync"
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
)

// The demo library is the same four encoded files for every harness,
// and synthesizing them is the single largest cost in this package:
// around 2.4s per harness under -race, times the hundred-odd harnesses
// the tests build. Encoding it once per test binary and copying the
// tree costs milliseconds instead. Each harness still gets its own
// writable directory, which several tests extend with extra fixtures
// (books, chaptered books, duplicates) and others mutate outright.
var demoLibraryTemplate = sync.OnceValues(func() (string, error) {
	dir, err := os.MkdirTemp("", "waxdeck-demo-library-")
	if err != nil {
		return "", err
	}
	if _, err := fixtures.Generate(dir, fixtures.DemoLibrary()...); err != nil {
		os.RemoveAll(dir)
		return "", err
	}
	demoLibraryDir = dir
	return dir, nil
})

// demoLibraryDir records the template for TestMain to remove. Only the
// once-function writes it, and only TestMain reads it, after every test
// has finished.
var demoLibraryDir string

func TestMain(m *testing.M) {
	code := m.Run()
	if demoLibraryDir != "" {
		os.RemoveAll(demoLibraryDir)
	}
	os.Exit(code)
}

// generateDemoLibrary fills dir with the demo library: Alpha (flac),
// Bravo (mp3), Charlie (opus), and Delta (vorbis), all titled and
// tagged.
func generateDemoLibrary(t *testing.T, dir string) {
	t.Helper()
	src, err := demoLibraryTemplate()
	if err != nil {
		t.Fatalf("generating fixtures: %v", err)
	}
	if err := copyTree(src, dir); err != nil {
		t.Fatalf("copying fixtures: %v", err)
	}
}

// copyTree copies src's files and directories into dst, which must
// already exist. Nothing under the fixture template is a symlink or a
// special file, so a plain walk covers it.
func copyTree(src, dst string) error {
	return filepath.WalkDir(src, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		rel, err := filepath.Rel(src, path)
		if err != nil {
			return err
		}
		if rel == "." {
			return nil
		}
		target := filepath.Join(dst, rel)
		info, err := d.Info()
		if err != nil {
			return err
		}
		if d.IsDir() {
			return os.MkdirAll(target, info.Mode().Perm())
		}
		in, err := os.Open(path)
		if err != nil {
			return err
		}
		defer in.Close()
		out, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, info.Mode().Perm())
		if err != nil {
			return err
		}
		if _, err := io.Copy(out, in); err != nil {
			out.Close()
			return err
		}
		return out.Close()
	})
}

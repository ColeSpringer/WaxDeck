package fixtures_test

import (
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
)

// TestSafProbeIsTheTreeTheChannelTestAsserts pins the probe's shape
// against the expectations in app/app/integration_test/saf_channel_test
// .dart: the tree is what that test walks, and a rename here would fail
// it on a device with nothing on this side to say why.
func TestSafProbeIsTheTreeTheChannelTestAsserts(t *testing.T) {
	dir := t.TempDir()
	root, err := fixtures.GenerateSafProbe(dir)
	if err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join(dir, "WaxProbe"); root != want {
		t.Errorf("root = %q, want %q", root, want)
	}

	var got []string
	if err := filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			return nil
		}
		rel, err := filepath.Rel(root, path)
		if err != nil {
			return err
		}
		got = append(got, filepath.ToSlash(rel))
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	slices.Sort(got)
	want := []string{
		"Disc1/sodium-sky.mp3",
		"lantern-one.mp3",
		"lantern-two.mp3",
		"memoir.aax",
		"notes.txt",
	}
	if !slices.Equal(got, want) {
		t.Errorf("tree = %v, want %v", got, want)
	}

	// The audio has to be real: the test reads a whole file back over
	// the channel and checks the byte count against the declared size.
	for _, name := range []string{"lantern-one.mp3", "lantern-two.mp3", "Disc1/sodium-sky.mp3"} {
		info, err := os.Stat(filepath.Join(root, filepath.FromSlash(name)))
		if err != nil {
			t.Fatal(err)
		}
		if info.Size() == 0 {
			t.Errorf("%s is empty", name)
		}
	}

	// The two the filter has to leave behind are stubs by design; what
	// makes them countable is the extension alone.
	for _, name := range []string{"notes.txt", "memoir.aax"} {
		body, err := os.ReadFile(filepath.Join(root, name))
		if err != nil {
			t.Fatal(err)
		}
		if strings.TrimSpace(string(body)) == "" {
			t.Errorf("%s is empty", name)
		}
	}
}

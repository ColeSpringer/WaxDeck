package fixtures

import (
	"fmt"
	"os"
	"path/filepath"
	"time"
)

// SafProbeDir is the folder name the Android SAF integration test picks
// through the system tree picker, and the name it asserts every walked
// entry's relative directory against.
const SafProbeDir = "WaxProbe"

// GenerateSafProbe writes the tree the waxdeck/saf channel test walks:
// two tracks at the top, one under a disc subdirectory, and two files
// the Dart-side filter has to leave behind - a text file it counts as
// unsupported and an Audible container it counts as DRM.
//
// Bespoke rather than a []Spec preset because the shape is the point:
// Generate writes flat and audio-only, and what this proves is a tree
// with a subdirectory in it and non-audio beside the audio. The
// non-audio files are stubs - nothing decodes them, the extension is
// the whole test - the way run-stack.sh assembles the desktop
// folder-pick tree.
func GenerateSafProbe(dir string) (string, error) {
	root := filepath.Join(dir, SafProbeDir)
	track := func(name, title string, d time.Duration) Spec {
		return Spec{
			Name:     name,
			Codec:    CodecMP3,
			Duration: d,
			Tags: map[string]string{
				"TITLE":  title,
				"ARTIST": "Lantern Field",
				"ALBUM":  "Sodium Sky",
			},
		}
	}
	// Durations distinct from each other and from every other fixture
	// set's: the tone is deterministic, so two MP3s of the same length
	// decode to the same audio and share a fingerprint however their
	// tags differ.
	if _, err := Generate(root,
		track("lantern-one", "Lantern One", 5100*time.Millisecond),
		track("lantern-two", "Lantern Two", 5600*time.Millisecond),
	); err != nil {
		return "", err
	}
	if _, err := Generate(filepath.Join(root, "Disc1"),
		track("sodium-sky", "Sodium Sky", 5900*time.Millisecond),
	); err != nil {
		return "", err
	}
	for name, body := range map[string]string{
		"notes.txt":  "not audio\n",
		"memoir.aax": "not really encrypted\n",
	} {
		path := filepath.Join(root, name)
		if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
			return "", fmt.Errorf("fixtures: writing %s: %w", name, err)
		}
	}
	return root, nil
}

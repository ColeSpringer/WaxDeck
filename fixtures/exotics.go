package fixtures

import (
	"embed"
	"fmt"
	"os"
	"path/filepath"
)

//go:embed testdata/exotics
var exotics embed.FS

// The repository policy is "no binary media in git", and these two files
// are the exception it names: WMA and Musepack are formats WaxFlow
// decodes but cannot encode, so no Spec can synthesize them and there is
// no way to cover the scan, chapter, and transcode paths they reach
// without checking a sample in. Both are a few KB. Everything else in
// this package is still generated.
const (
	// ExoticMusepack is a Musepack SV8 stream (the current stream
	// version) carrying chapter packets: ReferenceSignal through
	// mpcenc r475 --thumb, mono, 2 s, with chapters Intro, Middle and
	// Coda at 0, 750 and 1500 ms written by mpcchap. Vendored from
	// WaxBin's internal/testaudio/testdata at 9583470.
	ExoticMusepack = "ref-2s-sv8-chapters.mpc"
	// ExoticWMA is a WMAv2 stream carrying Marker Object chapters:
	// 8 kHz mono, 2 s, chapters Intro, Mïddle and Coda at 0, 500 and
	// 1250 ms. The middle title is non-ASCII on purpose, since ASF
	// markers are UTF-16. Vendored from WaxFlow's container/asf/testdata
	// by way of WaxBin's internal/testaudio/testdata at 9583470.
	ExoticWMA = "chapters.wma"
)

// AllExotics is every vendored sample, for a caller that wants the set
// rather than one by name.
var AllExotics = []string{ExoticMusepack, ExoticWMA}

// Vendored returns one vendored sample's bytes by name (one of the
// Exotic constants). An unknown name is an error rather than empty
// bytes, so a typo fails where it is written.
func Vendored(name string) ([]byte, error) {
	data, err := exotics.ReadFile("testdata/exotics/" + name)
	if err != nil {
		return nil, fmt.Errorf("fixtures: no vendored sample %q", name)
	}
	return data, nil
}

// WriteVendored writes the named vendored samples into dir (created if
// absent) under their own names and returns the written paths, in the
// order given. It is the Generate counterpart for the files that cannot
// be synthesized, so a test library can hold both.
func WriteVendored(dir string, names ...string) ([]string, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, fmt.Errorf("fixtures: creating %s: %w", dir, err)
	}
	paths := make([]string, 0, len(names))
	for _, name := range names {
		data, err := Vendored(name)
		if err != nil {
			return paths, err
		}
		path := filepath.Join(dir, name)
		if err := os.WriteFile(path, data, 0o644); err != nil {
			return paths, err
		}
		paths = append(paths, path)
	}
	return paths, nil
}

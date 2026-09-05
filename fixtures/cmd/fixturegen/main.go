// Command fixturegen writes a synthesized fixture library to a
// directory and prints the file list, one path per line.
//
//	fixturegen -out <dir> [-preset default|demo|conformance|upload|upload-folder|upload-workbench|saf-probe|cover|podcast|book|all] [-base-url <url>]
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/colespringer/waxdeck/fixtures"
)

func main() {
	out := flag.String("out", "", "output directory (required)")
	preset := flag.String("preset", "default",
		"spec preset: default (the codec/container matrix), demo (a titled album), conformance (the engine-suite tone), upload (the manual-upload album), upload-folder (the folder-pick album), upload-workbench (the release-workbench album), saf-probe (the Android tree-picker probe folder), cover (an exotic cover image to set by hand), podcast (the default feed), book (the audiobook fixtures), all")
	baseURL := flag.String("base-url", "http://127.0.0.1:4421",
		"base URL podcast enclosure links point at (the podcast preset; 'all' includes the feed only when this flag is set explicitly)")
	flag.Parse()
	if *out == "" {
		fmt.Fprintln(os.Stderr, "fixturegen: -out is required")
		flag.Usage()
		os.Exit(2)
	}
	baseURLSet := false
	flag.Visit(func(f *flag.Flag) {
		if f.Name == "base-url" {
			baseURLSet = true
		}
	})

	if err := run(*out, *preset, *baseURL, baseURLSet); err != nil {
		fmt.Fprintf(os.Stderr, "fixturegen: %v\n", err)
		os.Exit(1)
	}
}

func run(out, preset, baseURL string, baseURLSet bool) error {
	var specs []fixtures.Spec
	switch preset {
	case "default":
		specs = fixtures.DefaultLibrary()
	case "demo":
		specs = fixtures.DemoLibrary()
	case "conformance":
		specs = fixtures.ConformanceMedia()
	case "upload":
		specs = fixtures.UploadSources()
	case "cover":
		return generateCover(out)
	case "upload-folder":
		specs = fixtures.UploadFolderSources()
	case "upload-workbench":
		specs = fixtures.UploadWorkbenchSources()
	case "saf-probe":
		return generateSafProbe(out)
	case "all":
		specs = append(fixtures.DefaultLibrary(), fixtures.DemoLibrary()...)
	case "podcast":
		return generatePodcast(out, baseURL)
	case "book":
		return generateBooks(out)
	default:
		return fmt.Errorf("unknown preset %q", preset)
	}

	paths, err := fixtures.Generate(out, specs...)
	for _, p := range paths {
		fmt.Println(p)
	}
	if err != nil {
		return err
	}
	if preset == "all" {
		if err := generateBooks(out); err != nil {
			return err
		}
		// The feed's enclosure URLs need a real base, so 'all' only
		// includes it when the caller said where it will be served.
		if baseURLSet {
			if err := generatePodcast(out, baseURL); err != nil {
				return err
			}
		}
	}
	return nil
}

// generateCover writes the exotic cover the artwork surfaces are driven
// with. Its own preset rather than part of `all`: it is not media under
// scan, it is a file a person picks from a dialog, so it belongs beside
// the upload sources rather than inside a library.
func generateCover(out string) error {
	path, err := fixtures.GenerateExoticCover(out)
	if err != nil {
		return err
	}
	fmt.Println(path)
	return nil
}

// generateSafProbe writes the Android tree-picker probe folder. Its own
// preset for the generateCover reason and one more: the tree it writes
// has a shape, and the []Spec path writes flat.
func generateSafProbe(out string) error {
	root, err := fixtures.GenerateSafProbe(out)
	if err != nil {
		return err
	}
	fmt.Println(root)
	return nil
}

func generatePodcast(out, baseURL string) error {
	feedPath, err := fixtures.GeneratePodcastFeed(out, fixtures.DefaultPodcastFeed(baseURL), baseURL)
	if err != nil {
		return err
	}
	fmt.Println(feedPath)
	return nil
}

func generateBooks(out string) error {
	bookDir, err := fixtures.GenerateBook(out)
	if err != nil {
		return err
	}
	fmt.Println(bookDir)
	chaptered, err := fixtures.GenerateChapteredBook(out)
	if err != nil {
		return err
	}
	fmt.Println(chaptered)
	// A tagged series, which the two books above deliberately are not:
	// the series screen needs books whose tags name one and number them.
	series, err := fixtures.GenerateSeriesBooks(out, seriesName, 3)
	if err != nil {
		return err
	}
	for _, path := range series {
		fmt.Println(path)
	}
	return nil
}

// seriesName is the series the e2e corpus carries. The specs that read
// it spell it out themselves - a Go constant is not reachable from
// TypeScript - so renaming it means renaming it there too.
const seriesName = "Tidewater"

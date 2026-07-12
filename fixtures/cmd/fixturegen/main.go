// Command fixturegen writes a synthesized fixture library to a
// directory and prints the file list, one path per line.
//
//	fixturegen -out <dir> [-preset default|ffmpeg|all]
//
// The default preset needs no ffmpeg; ffmpeg-only specs in the other
// presets are skipped with a warning when no ffmpeg is on PATH.
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
		"spec preset: default (WaxFlow-native only), ffmpeg (formats needing ffmpeg), all")
	flag.Parse()
	if *out == "" {
		fmt.Fprintln(os.Stderr, "fixturegen: -out is required")
		flag.Usage()
		os.Exit(2)
	}

	var specs []fixtures.Spec
	switch *preset {
	case "default":
		specs = fixtures.DefaultLibrary()
	case "ffmpeg":
		specs = fixtures.FFmpegLibrary()
	case "all":
		specs = append(fixtures.DefaultLibrary(), fixtures.FFmpegLibrary()...)
	default:
		fmt.Fprintf(os.Stderr, "fixturegen: unknown preset %q\n", *preset)
		os.Exit(2)
	}

	// ffmpeg is never hard-required: without one, ffmpeg-only specs are
	// skipped loudly rather than failing the run.
	if !fixtures.FFmpegAvailable() {
		kept := specs[:0]
		for _, s := range specs {
			if s.NeedsFFmpeg() {
				fmt.Fprintf(os.Stderr, "fixturegen: skipping %s: ffmpeg not on PATH\n", s.Filename())
				continue
			}
			kept = append(kept, s)
		}
		specs = kept
	}

	paths, err := fixtures.Generate(*out, specs...)
	for _, p := range paths {
		fmt.Println(p)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "fixturegen: %v\n", err)
		os.Exit(1)
	}
}

// Command fixturegen writes a synthesized fixture library to a
// directory and prints the file list, one path per line.
//
//	fixturegen -out <dir> [-preset default|demo|conformance|all]
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
		"spec preset: default (the codec/container matrix), demo (a titled album), conformance (the engine-suite tone), all")
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
	case "demo":
		specs = fixtures.DemoLibrary()
	case "conformance":
		specs = fixtures.ConformanceMedia()
	case "all":
		specs = append(fixtures.DefaultLibrary(), fixtures.DemoLibrary()...)
	default:
		fmt.Fprintf(os.Stderr, "fixturegen: unknown preset %q\n", *preset)
		os.Exit(2)
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

// Command dartgen generates the Dart API client's models, enums and JSON
// codec, and per tag its interface and the Dio calls implementing it, from
// the bundled OpenAPI spec, steered by a hints file (dartgen.yaml) for
// what the spec cannot say. Output is deterministic, and a run with any
// spec or hints error writes nothing. With -format it is dart formatted,
// in a staging copy under the package's .dart_tool, before it is compared
// with the files there. With -client, the run also fails unless that
// client.dart takes calls.g.dart, the one part the run writes, and no
// other part from the output directory, and unless the hand-written
// package around it leaves the generated code its names (hand.go). With
// -extensions, the classes that model_extensions.dart's extensions extend
// are public (public.g.dart exports them), and the run fails unless those
// extensions declare no member a generated field or the generated hasMore
// takes, and each copyWith there takes every field of its class and passes
// it on.
//
// Run as: go run ./cmd/dartgen -format -spec ../api/openapi.yaml
// -hints ../app/packages/waxdeck_api/dartgen.yaml
// -out ../app/packages/waxdeck_api/lib/src/gen
// -client ../app/packages/waxdeck_api/lib/src/client.dart
// -extensions ../app/packages/waxdeck_api/lib/src/model_extensions.dart
package main

import (
	"bytes"
	"flag"
	"fmt"
	"io/fs"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/server/cmd/internal/atomicfile"
)

func main() {
	specPath := flag.String("spec", "../api/openapi.yaml", "bundled OpenAPI spec")
	hintsPath := flag.String("hints", "../app/packages/waxdeck_api/dartgen.yaml", "hints file")
	out := flag.String("out", "../app/packages/waxdeck_api/lib/src/gen", "output directory")
	client := flag.String("client", "", "client.dart, whose part directives and package the run checks its names against (none: no check)")
	extensions := flag.String("extensions", "", "model_extensions.dart, whose extensions on generated classes are checked and make those classes public (none: neither)")
	format := flag.Bool("format", false, "dart format the output before comparing it with the files there (needs dart on PATH)")
	flag.Parse()
	var formatter func(dir string) error
	if *format {
		formatter = dartFormat
	}
	if err := run(*specPath, *hintsPath, *out, *client, *extensions, formatter); err != nil {
		fmt.Fprintf(os.Stderr, "dartgen: %v\n", err)
		os.Exit(1)
	}
}

func run(specPath, hintsPath, out, client, extensions string, format func(dir string) error) error {
	var hand *handPackage
	if client != "" {
		// The part first: a client the output is not beside has no
		// package around it to check the names against.
		src, err := os.ReadFile(client)
		if err != nil {
			return err
		}
		if err := clientParts(client, out, string(src)); err != nil {
			return err
		}
		if hand, err = readHandPackage(client, out); err != nil {
			return err
		}
	}
	files, err := build(specPath, hintsPath, extensions, hand)
	if err != nil {
		return err
	}
	if format != nil {
		if files, err = formatted(out, files, format); err != nil {
			return err
		}
	}
	return writeOutputs(out, files)
}

// stagePattern names the staging copies a formatting run makes.
const stagePattern = ".dartgen-*"

// staleStage is how old a staging copy is before a run takes it for an
// interrupted run's. A run makes and formats a few dozen files in seconds
// and removes its copy as it ends, so an hour is far past any live run's,
// and a concurrent run's copy is never touched.
const staleStage = time.Hour

// formatted is files as format leaves them, run over a staging copy in
// the .dart_tool of out's package (whose language version and options it
// formats by, and which git and the web build ignore). A copy that an
// interrupted run left there, older than staleStage, goes first.
func formatted(out string, files map[string][]byte, format func(dir string) error) (map[string][]byte, error) {
	pkg, err := packageRoot(out)
	if err != nil {
		return nil, err
	}
	tool := filepath.Join(pkg, ".dart_tool")
	if err := os.MkdirAll(tool, 0o755); err != nil {
		return nil, err
	}
	stale, err := filepath.Glob(filepath.Join(tool, stagePattern))
	if err != nil {
		return nil, err
	}
	for _, dir := range stale {
		info, err := os.Stat(dir)
		if err != nil || time.Since(info.ModTime()) < staleStage {
			continue
		}
		if err := os.RemoveAll(dir); err != nil {
			return nil, err
		}
	}
	stage, err := os.MkdirTemp(tool, stagePattern)
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(stage)
	for rel, data := range files {
		path := filepath.Join(stage, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return nil, err
		}
		if err := os.WriteFile(path, data, 0o644); err != nil {
			return nil, err
		}
	}
	if err := format(stage); err != nil {
		return nil, err
	}
	done := make(map[string][]byte, len(files))
	for rel := range files {
		data, err := os.ReadFile(filepath.Join(stage, filepath.FromSlash(rel)))
		if err != nil {
			return nil, err
		}
		done[rel] = data
	}
	return done, nil
}

// packageRoot is the nearest directory at or above out holding a
// pubspec.yaml.
func packageRoot(out string) (string, error) {
	dir, err := filepath.Abs(out)
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "pubspec.yaml")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("-format: no pubspec.yaml at or above %s, whose package's .dart_tool stages the run", out)
		}
		dir = parent
	}
}

// dartFormat runs dart format over dir.
func dartFormat(dir string) error {
	if msg, err := exec.Command("dart", "format", dir).CombinedOutput(); err != nil {
		return fmt.Errorf("dart format %s: %w\n%s", dir, err, msg)
	}
	return nil
}

// generate builds every output file in memory, keyed by slash path
// relative to the output directory. extensions, when given, is the
// model_extensions.dart the model is checked against.
func generate(specPath, hintsPath, extensions string) (map[string][]byte, error) {
	return build(specPath, hintsPath, extensions, nil)
}

// build is generate, its names checked against hand, the hand-written
// package around client.dart, when given.
func build(specPath, hintsPath, extensions string, hand *handPackage) (map[string][]byte, error) {
	s, err := loadSpec(specPath)
	if err != nil {
		return nil, err
	}
	h, err := parseHints(hintsPath)
	if err != nil {
		return nil, err
	}
	var ext *extensionsFile
	if extensions != "" {
		src, err := os.ReadFile(extensions)
		if err != nil {
			return nil, err
		}
		ext = &extensionsFile{path: extensions, list: parseExtensions(string(src))}
	}
	m, err := buildModel(s, h, ext, hand)
	if err != nil {
		return nil, err
	}
	cs, err := buildCalls(m)
	if err != nil {
		return nil, err
	}
	files := m.emit(cs.public())
	for rel, data := range cs.emit() {
		files[rel] = data
	}
	return files, nil
}

// writeOutputs writes files under out and removes the .g.dart files
// there that carry dartgen's header and the run did not produce, and a
// directory that leaves empty; another generator's are left alone.
func writeOutputs(out string, files map[string][]byte) error {
	for _, rel := range slices.Sorted(maps.Keys(files)) {
		path := filepath.Join(out, filepath.FromSlash(rel))
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return err
		}
		if err := atomicfile.WriteIfChanged(path, files[rel]); err != nil {
			return err
		}
	}
	var stale []string
	err := filepath.WalkDir(out, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(d.Name(), ".g.dart") {
			return nil
		}
		rel, err := filepath.Rel(out, path)
		if err != nil {
			return err
		}
		if _, ok := files[filepath.ToSlash(rel)]; ok {
			return nil
		}
		data, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		if bytes.HasPrefix(data, []byte(header)) {
			stale = append(stale, path)
		}
		return nil
	})
	if err != nil {
		return err
	}
	for _, path := range stale {
		if err := os.Remove(path); err != nil {
			return err
		}
	}
	for _, path := range stale {
		rel, err := filepath.Rel(out, path)
		if err != nil {
			return err
		}
		for dir := filepath.Dir(rel); dir != "."; dir = filepath.Dir(dir) {
			full := filepath.Join(out, dir)
			if entries, err := os.ReadDir(full); err != nil || len(entries) > 0 {
				break
			}
			if err := os.Remove(full); err != nil {
				return err
			}
		}
	}
	return nil
}

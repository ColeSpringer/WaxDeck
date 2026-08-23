package main

import (
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"testing"
)

// Every WAXDECK_* env var the server binaries read must appear in
// docs/configuration.md: deploy/.env reaches the server verbatim, so an
// undocumented variable is a knob nobody can find.
func TestEveryServerEnvVarIsDocumented(t *testing.T) {
	doc, err := os.ReadFile(filepath.Join("..", "..", "..", "docs", "configuration.md"))
	if err != nil {
		t.Fatalf("reading docs/configuration.md: %v", err)
	}

	read := regexp.MustCompile(`(?:envOr|envIntOr|envInt64Or|os\.Getenv)\(\s*"(WAXDECK_[A-Z0-9_]+)"`)
	keys := map[string][]string{}
	root := filepath.Join("..", "..")
	err = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(path, ".go") || strings.HasSuffix(path, "_test.go") {
			return nil
		}
		src, err := os.ReadFile(path)
		if err != nil {
			return err
		}
		for _, m := range read.FindAllStringSubmatch(string(src), -1) {
			keys[m[1]] = append(keys[m[1]], path)
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walking server sources: %v", err)
	}
	if len(keys) == 0 {
		t.Fatal("found no WAXDECK_ env reads at all; the scan is broken")
	}

	// Backticked, as the doc spells every key, so a key that is a prefix
	// of a documented sibling cannot pass on the sibling's entry.
	var missing []string
	for key := range keys {
		if !strings.Contains(string(doc), "`"+key+"`") {
			missing = append(missing, key)
		}
	}
	sort.Strings(missing)
	for _, key := range missing {
		t.Errorf("%s (read in %s) is not documented in docs/configuration.md", key, filepath.Base(keys[key][0]))
	}

	// And the other direction: a documented WAXDECK_ key must exist,
	// either as a server read or as a compose-level variable, so the doc
	// cannot keep describing a knob that was removed.
	composeSrc := ""
	for _, f := range []string{"compose.yaml", ".env.example"} {
		b, err := os.ReadFile(filepath.Join("..", "..", "..", "deploy", f))
		if err != nil {
			t.Fatalf("reading deploy/%s: %v", f, err)
		}
		composeSrc += string(b)
	}
	documented := regexp.MustCompile("`(WAXDECK_[A-Z0-9_]+)`").FindAllStringSubmatch(string(doc), -1)
	var stale []string
	seen := map[string]bool{}
	for _, m := range documented {
		key := m[1]
		if seen[key] {
			continue
		}
		seen[key] = true
		if _, ok := keys[key]; !ok && !strings.Contains(composeSrc, key) {
			stale = append(stale, key)
		}
	}
	sort.Strings(stale)
	for _, key := range stale {
		t.Errorf("%s is documented but nothing reads it (not in server code, compose.yaml, or .env.example)", key)
	}
}

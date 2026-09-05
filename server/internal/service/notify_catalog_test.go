package service

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// The catalog is a Go slice here and a free string on the wire, so a
// client cannot enumerate it and the spec's prose is the only place the
// current set is written down for anybody to check against. This is what
// keeps the two from drifting: a new event that never reaches the prose
// leaves every client drawing its raw wire token.
func TestNotifyCatalogMatchesTheSpec(t *testing.T) {
	t.Parallel()
	path, ok := repoFile("api/spec/notifications.yaml")
	if !ok {
		t.Skip("no api/spec/notifications.yaml above the test's working directory")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("reading the spec fragment: %v", err)
	}
	spec := string(raw)
	const opening = "The current catalog is"
	start := strings.Index(spec, opening)
	if start < 0 {
		t.Fatalf("the spec no longer says %q", opening)
	}
	tail := spec[start:]
	end := strings.Index(tail, "`playlist-synced`")
	if end < 0 {
		t.Fatal("the catalog list no longer ends as it did")
	}
	end = strings.Index(tail[end:], ".")
	if end < 0 {
		t.Fatal("the catalog sentence no longer ends in a full stop")
	}
	sentence := tail[:strings.Index(tail, "`playlist-synced`")+end]

	documented := map[string]bool{}
	for _, m := range regexp.MustCompile("`([a-z][a-z-]*)`").FindAllStringSubmatch(sentence, -1) {
		documented[m[1]] = true
	}
	held := map[string]bool{}
	for _, e := range notifyEventCatalog {
		held[e.Name] = true
	}
	for name := range held {
		if !documented[name] {
			t.Errorf("event %q is emitted but not in the spec's catalog sentence", name)
		}
	}
	for name := range documented {
		if !held[name] {
			t.Errorf("event %q is documented but this server cannot emit it", name)
		}
	}
}

// repoFile walks up from the test's working directory looking for a
// repo-relative path. Absent in a stripped checkout, which is a skip
// rather than a failure.
func repoFile(relative string) (string, bool) {
	dir, err := os.Getwd()
	if err != nil {
		return "", false
	}
	for range 8 {
		candidate := filepath.Join(dir, relative)
		if _, err := os.Stat(candidate); err == nil {
			return candidate, true
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", false
		}
		dir = parent
	}
	return "", false
}

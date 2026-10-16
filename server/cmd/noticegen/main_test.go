package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func writeFile(t *testing.T, path, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

func blockTitles(t *testing.T, dir string) []string {
	t.Helper()
	var titles []string
	if err := vendoredWebNotices(dir, func(title string, _ []byte) {
		titles = append(titles, title)
	}); err != nil {
		t.Fatal(err)
	}
	return titles
}

func wantError(t *testing.T, dir, mention string) {
	t.Helper()
	err := vendoredWebNotices(dir, func(string, []byte) {})
	if err == nil || !strings.Contains(err.Error(), mention) {
		t.Fatalf("want an error naming %s, got %v", mention, err)
	}
}

func TestVendoredWebNoticesRefuseAnUnlicensedFile(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "hls.min.js"), "js")
	wantError(t, dir, "hls-LICENSE.txt")
}

// A directory is a collection of assets kept at the paths an engine
// asks for, and each is licensed on its own: one licence over the whole
// tree would let a second font family in under the first one's terms.
func TestVendoredWebNoticesLicenseEachEntryOfACollection(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "hls.min.js"), "js")
	writeFile(t, filepath.Join(dir, "hls-LICENSE.txt"), "hls licence")
	writeFile(t, filepath.Join(dir, "fonts", "face", "v1", "x.woff2"), "wOF2")
	wantError(t, dir, "face-LICENSE.txt")

	writeFile(t, filepath.Join(dir, "fonts", "face-LICENSE.txt"), "face licence")
	want := []string{"web/vendor/hls-LICENSE.txt", "web/vendor/fonts/face-LICENSE.txt"}
	if got := blockTitles(t, dir); strings.Join(got, ",") != strings.Join(want, ",") {
		t.Fatalf("blocks %v, want %v", got, want)
	}

	writeFile(t, filepath.Join(dir, "fonts", "other", "v2", "y.woff2"), "wOF2")
	wantError(t, dir, "other-LICENSE.txt")
}

// A licence beside nothing is what a removal or a half-finished refresh
// leaves, and it would ship terms for bytes that are not there.
func TestVendoredWebNoticesRefuseALicenseWithNoAsset(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, filepath.Join(dir, "hls-LICENSE.txt"), "hls licence")
	wantError(t, dir, "hls-LICENSE.txt")

	collection := t.TempDir()
	writeFile(t, filepath.Join(collection, "fonts", "face-LICENSE.txt"), "face licence")
	wantError(t, collection, "face-LICENSE.txt")

	// The old shape, one licence beside the whole tree, is an orphan now.
	whole := t.TempDir()
	writeFile(t, filepath.Join(whole, "fonts", "face", "v1", "x.woff2"), "wOF2")
	writeFile(t, filepath.Join(whole, "fonts", "face-LICENSE.txt"), "face licence")
	writeFile(t, filepath.Join(whole, "fonts-LICENSE.txt"), "tree licence")
	wantError(t, whole, "fonts-LICENSE.txt")
}

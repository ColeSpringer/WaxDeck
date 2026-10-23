package web

import (
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func mustHandler(t *testing.T, dir string) http.Handler {
	t.Helper()
	h, _, err := Handler(dir)
	if err != nil {
		t.Fatal(err)
	}
	return h
}

// A web dir without the app's shell would answer every navigation with
// a 404, so it is refused up front, naming the directory.
func TestAWebDirWithoutAnIndexIsRefused(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "main.dart.js"), []byte("//"), 0o644); err != nil {
		t.Fatal(err)
	}
	for _, d := range []string{dir, filepath.Join(dir, "missing")} {
		if _, _, err := Handler(d); err == nil || err.Error() != "web dir "+d+" has no index.html" {
			t.Fatalf("Handler(%s) = %v, want the missing-index refusal", d, err)
		}
	}
	if err := os.Mkdir(filepath.Join(dir, "index.html"), 0o755); err != nil {
		t.Fatal(err)
	}
	if _, _, err := Handler(dir); err == nil || !strings.Contains(err.Error(), "has no index.html") {
		t.Fatalf("a directory named index.html = %v, want the refusal", err)
	}
}

// The handler says where it serves from, for the startup log.
func TestHandlerSaysWhichSourceItServes(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "index.html"), []byte("<html></html>"), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, source, err := Handler(dir); err != nil || source != SourceDir {
		t.Fatalf("Handler(dir) source = %q, %v; want %q", source, err, SourceDir)
	}
	want := SourcePlaceholder
	if distFS != nil {
		want = SourceEmbedded
	}
	if _, source, err := Handler(""); err != nil || source != want {
		t.Fatalf(`Handler("") source = %q, %v; want %q`, source, err, want)
	}
}

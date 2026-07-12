package web

import (
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPlaceholderServed(t *testing.T) {
	ts := httptest.NewServer(Handler(""))
	defer ts.Close()

	for _, path := range []string{"/", "/some/spa/route"} {
		resp, err := http.Get(ts.URL + path)
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 200 {
			t.Fatalf("GET %s = %d", path, resp.StatusCode)
		}
		if !strings.Contains(string(body), "WaxDeck") {
			t.Fatalf("GET %s: body does not mention WaxDeck", path)
		}
		if got := resp.Header.Get("Cross-Origin-Opener-Policy"); got != "same-origin" {
			t.Fatalf("COOP = %q", got)
		}
		if got := resp.Header.Get("Cross-Origin-Embedder-Policy"); got != "credentialless" {
			t.Fatalf("COEP = %q", got)
		}
	}
}

func TestDirectoryRequestFallsBackToShell(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "index.html"),
		[]byte("<html><title>WaxDeck shell</title></html>"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(dir, "assets"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "assets", "secret.txt"),
		[]byte("do not list me"), 0o644); err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(Handler(dir))
	defer ts.Close()

	// A directory request must return the SPA shell, never a directory listing.
	for _, p := range []string{"/assets", "/assets/"} {
		resp, err := http.Get(ts.URL + p)
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 200 {
			t.Fatalf("GET %s = %d, want 200 (shell)", p, resp.StatusCode)
		}
		if !strings.Contains(string(body), "WaxDeck shell") {
			t.Fatalf("GET %s did not return the shell: %s", p, body)
		}
		if strings.Contains(string(body), "secret.txt") {
			t.Fatalf("GET %s leaked a directory listing", p)
		}
	}

	// A real nested file is still served directly.
	resp, err := http.Get(ts.URL + "/assets/secret.txt")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.Contains(string(body), "do not list me") {
		t.Fatalf("nested file not served: %s", body)
	}
}

func TestDevDirOverridesEmbeds(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "index.html"),
		[]byte("<html><title>WaxDeck dev</title></html>"), 0o644); err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(Handler(dir))
	defer ts.Close()

	resp, err := http.Get(ts.URL + "/")
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !strings.Contains(string(body), "WaxDeck dev") {
		t.Fatalf("dev dir not served: %s", body)
	}
}

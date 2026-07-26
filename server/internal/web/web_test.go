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
		// Browsers mark document navigations; the SPA fallback answers
		// those, so the deep-link case must ask like one.
		resp := get(t, ts.URL+path, map[string]string{"Sec-Fetch-Mode": "navigate"})
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

	// A directory navigation must return the SPA shell, never a
	// directory listing.
	for _, p := range []string{"/assets", "/assets/"} {
		resp := get(t, ts.URL+p, map[string]string{"Accept": "text/html"})
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

func get(t *testing.T, url string, headers map[string]string) *http.Response {
	t.Helper()
	req, err := http.NewRequest(http.MethodGet, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	for k, v := range headers {
		req.Header.Set(k, v)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

func TestShellAnswersNavigationsOnly(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "index.html"),
		[]byte("<html><title>WaxDeck shell</title></html>"), 0o644); err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(Handler(dir))
	defer ts.Close()

	// Subresource-shaped misses 404 wherever they land: a font the
	// engine's fallback probes for (deliberately unrouted), a broken
	// asset reference, a manifest. HTML with a 200 would feed the shell
	// to font and wasm loaders, which fail later and stranger.
	for _, tc := range []struct {
		path    string
		headers map[string]string
	}{
		{"/wax-font-fallback/notosans/v37/shard.woff2", map[string]string{"Sec-Fetch-Mode": "no-cors"}},
		{"/assets/wax-font-fallback/roboto/v32/x.woff2", nil},
		{"/assets/packages/waxdeck_ui/assets/fonts/Missing.otf", nil},
		{"/canvaskit/nothing.wasm", nil},
		{"/manifest.json", map[string]string{"Sec-Fetch-Mode": "cors"}},
		// Sec-Fetch-Mode wins over Accept when both are present.
		{"/icons/Icon-192.png", map[string]string{"Sec-Fetch-Mode": "no-cors", "Accept": "text/html"}},
	} {
		resp := get(t, ts.URL+tc.path, tc.headers)
		resp.Body.Close()
		if resp.StatusCode != http.StatusNotFound {
			t.Fatalf("GET %s (%v) = %d, want 404", tc.path, tc.headers, resp.StatusCode)
		}
	}

	// Navigations get the shell: the modern header, and the Accept
	// fallback for clients that do not send it.
	for _, headers := range []map[string]string{
		{"Sec-Fetch-Mode": "navigate"},
		{"Accept": "text/html,application/xhtml+xml"},
	} {
		resp := get(t, ts.URL+"/library/some-client-route", headers)
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		if resp.StatusCode != 200 || !strings.Contains(string(body), "WaxDeck shell") {
			t.Fatalf("navigation (%v) lost the shell: %d %s", headers, resp.StatusCode, body)
		}
	}
}

func TestConditionalRequestsRevalidate(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "index.html"),
		[]byte("<html><title>WaxDeck shell</title></html>"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(dir, "assets"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "assets", "big-face.otf"),
		[]byte("pretend this is sixteen megabytes"), 0o644); err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewServer(Handler(dir))
	defer ts.Close()

	// First fetch carries a validator; embed.FS has no mtimes, so
	// without an ETag every reload would re-download the whole engine
	// and font set.
	resp, err := http.Get(ts.URL + "/assets/big-face.otf")
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	etag := resp.Header.Get("ETag")
	if etag == "" {
		t.Fatal("no ETag on asset response")
	}
	if cc := resp.Header.Get("Cache-Control"); cc != "no-cache" {
		t.Fatalf("Cache-Control = %q, want no-cache (revalidate, not re-download)", cc)
	}

	// Revalidation answers 304 with no body.
	resp2 := get(t, ts.URL+"/assets/big-face.otf", map[string]string{"If-None-Match": etag})
	body, _ := io.ReadAll(resp2.Body)
	resp2.Body.Close()
	if resp2.StatusCode != http.StatusNotModified {
		t.Fatalf("conditional GET = %d, want 304", resp2.StatusCode)
	}
	if len(body) != 0 {
		t.Fatalf("304 carried a body of %d bytes", len(body))
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

// Package web serves the WaxDeck web UI from one of three sources, in
// priority order:
//
//  1. --web-dir (dev): a directory on disk, for hot iteration against
//     `flutter build web` output without re-embedding.
//  2. The embedded Flutter build (builds with `-tags withweb`; `make web`
//     populates the dist/ tree that go:embed bundles).
//  3. A committed placeholder page (plain builds: keeps `go build ./...`
//     working without a Flutter toolchain).
package web

import (
	"crypto/sha256"
	"embed"
	"encoding/hex"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path"
	"strings"
	"sync"
)

//go:embed placeholder
var placeholderFS embed.FS

// distFS is populated by web_dist.go when built with -tags withweb.
var distFS fs.FS

// Handler returns the SPA handler. devDir, when non-empty, overrides any
// embedded build.
func Handler(devDir string) http.Handler {
	var files fs.FS
	switch {
	case devDir != "":
		files = os.DirFS(devDir)
	case distFS != nil:
		files = distFS
	default:
		files, _ = fs.Sub(placeholderFS, "placeholder")
	}
	return &spaHandler{files: files}
}

type spaHandler struct {
	files fs.FS

	// Content hashes for validators: embed.FS reports a zero ModTime, so
	// without these every reload re-downloads the whole engine and font
	// set (the CJK face alone is 16 MB). Computed on first serve, cached
	// for the process's life; the embedded tree never changes underneath
	// a running binary, and the dev tree changing at worst re-hashes.
	etags sync.Map // name -> `"hex"`
}

func (h *spaHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	// Required for the WasmGC build target: cross-origin isolation on the
	// app shell. We control the single origin, so these are safe globally.
	w.Header().Set("Cross-Origin-Opener-Policy", "same-origin")
	w.Header().Set("Cross-Origin-Embedder-Policy", "credentialless")

	name := strings.TrimPrefix(path.Clean(r.URL.Path), "/")
	if name == "" {
		name = "index.html"
	}
	if h.serveFile(w, r, name) {
		return
	}
	// Past here the answer depends on the request headers rather than on
	// the path alone, so it has to say so: without Vary a shared cache in
	// front of WaxDeck keys on the URL and will hand one of these two
	// answers to a request that asked the other way - the shell to a font
	// or wasm loader, which is exactly what the 404 below exists to
	// prevent, or a cached 404 to a real deep link. Every location in the
	// route table resolves through here, so this is the whole app's
	// surface, not an edge.
	w.Header().Set("Vary", "Sec-Fetch-Mode, Accept")
	// The shell answers navigations only. A subresource miss (a font the
	// engine's fallback probes for, a wasm path, an icon) must fail as a
	// 404: answering it with HTML feeds the shell to font and wasm
	// loaders, which fail later and stranger, and the engine's font
	// fallback is pointed at an unrouted path on purpose, expecting
	// exactly that 404. Browsers mark navigations explicitly
	// (Sec-Fetch-Mode); anything older or hand-rolled says what it can
	// render in Accept.
	if !isNavigation(r) {
		// A 404 with no cache directive is heuristically cacheable, and a
		// stored one outlives the deploy that would have made the path
		// real. Nothing about a miss is worth keeping.
		w.Header().Set("Cache-Control", "no-store")
		http.NotFound(w, r)
		return
	}
	// SPA fallback: unknown paths and directories get the app shell so
	// client-side routing can take over.
	if !h.serveFile(w, r, "index.html") {
		w.Header().Set("Cache-Control", "no-store")
		http.Error(w, "index.html not found", http.StatusNotFound)
	}
}

// isNavigation reports whether the request is a document navigation (a
// typed URL, a shared deep link, a reload) rather than a subresource or
// programmatic fetch.
func isNavigation(r *http.Request) bool {
	if mode := r.Header.Get("Sec-Fetch-Mode"); mode != "" {
		return mode == "navigate"
	}
	return strings.Contains(r.Header.Get("Accept"), "text/html")
}

// serveFile serves name as a regular file, opening it exactly once. It reports
// false without writing a body when name is missing or a directory, so the
// caller can fall back to the SPA shell. A directory must never reach the file
// server, which would emit a listing or a redirect.
func (h *spaHandler) serveFile(w http.ResponseWriter, r *http.Request, name string) bool {
	f, err := h.files.Open(name)
	if err != nil {
		return false
	}
	info, err := f.Stat()
	if err != nil || info.IsDir() {
		f.Close()
		return false
	}
	// no-cache means "revalidate before reuse", not "do not store": with
	// the ETag below, an unchanged file costs a conditional request and a
	// 304 instead of a re-download. index.html must revalidate so
	// deployments land; everything else is content-addressed in practice
	// but revalidation is what makes that safe without trusting names.
	w.Header().Set("Cache-Control", "no-cache")
	if rs, ok := f.(io.ReadSeeker); ok {
		defer f.Close()
		if etag := h.etagFor(name, rs); etag != "" {
			w.Header().Set("ETag", etag)
		}
		http.ServeContent(w, r, name, info.ModTime(), rs)
		return true
	}
	// Regular file that is not seekable (not expected from embed.FS or
	// os.DirFS): fall back to the file server, which reopens it.
	f.Close()
	http.ServeFileFS(w, r, h.files, name)
	return true
}

// etagFor returns the strong validator for name, hashing the content on
// first use and rewinding the reader for the serve that follows.
func (h *spaHandler) etagFor(name string, rs io.ReadSeeker) string {
	if cached, ok := h.etags.Load(name); ok {
		return cached.(string)
	}
	hash := sha256.New()
	if _, err := io.Copy(hash, rs); err != nil {
		return ""
	}
	if _, err := rs.Seek(0, io.SeekStart); err != nil {
		return ""
	}
	etag := `"` + hex.EncodeToString(hash.Sum(nil)[:16]) + `"`
	h.etags.Store(name, etag)
	return etag
}

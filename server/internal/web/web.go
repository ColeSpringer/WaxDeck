// Package web serves the WaxDeck web UI from one of three sources, in
// priority order:
//
//  1. --web-dir (dev): a directory on disk, for hot iteration against
//     `flutter build web` output without re-embedding.
//  2. The embedded Flutter build (builds with `-tags withweb`, whose
//     go:embed of dist/ is populated by `make web`).
//  3. A committed placeholder page (plain builds: keeps `go build ./...`
//     working without a Flutter toolchain).
package web

import (
	"embed"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path"
	"strings"
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
	// SPA fallback: unknown paths and directories get the app shell so
	// client-side routing can take over.
	if !h.serveFile(w, r, "index.html") {
		http.Error(w, "index.html not found", http.StatusNotFound)
	}
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
	if name == "index.html" {
		w.Header().Set("Cache-Control", "no-cache")
	}
	if rs, ok := f.(io.ReadSeeker); ok {
		defer f.Close()
		http.ServeContent(w, r, name, info.ModTime(), rs)
		return true
	}
	// Regular file that is not seekable (not expected from embed.FS or
	// os.DirFS): fall back to the file server, which reopens it.
	f.Close()
	http.ServeFileFS(w, r, h.files, name)
	return true
}

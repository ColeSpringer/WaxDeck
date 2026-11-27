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
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"sync"
)

//go:embed placeholder
var placeholderFS embed.FS

// distFS is populated by web_dist.go when built with -tags withweb.
var distFS fs.FS

// Where the web UI is served from, as Handler reports it.
const (
	SourceDir         = "dir"
	SourceEmbedded    = "embedded"
	SourcePlaceholder = "placeholder"
)

// Handler returns the SPA handler and the source it serves from. devDir,
// when non-empty, overrides any embedded build and has to hold the app's
// index.html: without it every navigation would answer a 404.
func Handler(devDir string) (http.Handler, string, error) {
	switch {
	case devDir != "":
		if st, err := os.Stat(filepath.Join(devDir, "index.html")); err != nil || st.IsDir() {
			return nil, "", fmt.Errorf("web dir %s has no index.html", devDir)
		}
		return &spaHandler{files: os.DirFS(devDir)}, SourceDir, nil
	case distFS != nil:
		return &spaHandler{files: distFS}, SourceEmbedded, nil
	default:
		files, _ := fs.Sub(placeholderFS, "placeholder")
		return &spaHandler{files: files}, SourcePlaceholder, nil
	}
}

type spaHandler struct {
	files fs.FS

	// Content hashes for validators: embed.FS reports a zero ModTime, so
	// without these every reload re-downloads the whole engine and font
	// set (the CJK face alone is 16 MB). Computed on first serve and kept
	// beside the size and time they were computed for, so a dev tree
	// rebuilt underneath a running server is hashed again rather than
	// answered from the old bytes.
	hashes sync.Map // name -> contentHash
}

type contentHash struct {
	size    int64
	modTime int64
	etag    string
	// The name carries this content's own hash, so the URL can never
	// answer other bytes.
	immutable bool
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
	// loaders, which fail later and stranger, and the engine's per-glyph
	// font fallback asks this origin for shards the build does not ship,
	// expecting exactly that 404. Browsers mark navigations explicitly
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
	// 304 instead of a re-download. index.html and flutter_bootstrap.js
	// must revalidate so deployments land. What the build named after its
	// own content can be kept outright, once the name is checked against
	// the bytes.
	cacheControl := "no-cache"
	if rs, ok := f.(io.ReadSeeker); ok {
		defer f.Close()
		if sum, ok := h.hashFor(name, info, rs); ok {
			w.Header().Set("ETag", sum.etag)
			if sum.immutable {
				cacheControl = "public, max-age=31536000, immutable"
			}
		}
		w.Header().Set("Cache-Control", cacheControl)
		http.ServeContent(w, r, name, info.ModTime(), rs)
		return true
	}
	// Regular file that is not seekable (not expected from embed.FS or
	// os.DirFS): fall back to the file server, which reopens it.
	f.Close()
	w.Header().Set("Cache-Control", cacheControl)
	http.ServeFileFS(w, r, h.files, name)
	return true
}

// hashFor returns the strong validator for this version of name, hashing
// the content on first use and rewinding the reader for the serve that
// follows. A changed file replaces its entry.
func (h *spaHandler) hashFor(name string, info fs.FileInfo, rs io.ReadSeeker) (contentHash, bool) {
	size, modTime := info.Size(), info.ModTime().UnixNano()
	if cached, ok := h.hashes.Load(name); ok {
		if sum := cached.(contentHash); sum.size == size && sum.modTime == modTime {
			return sum, true
		}
	}
	hash := sha256.New()
	if _, err := io.Copy(hash, rs); err != nil {
		return contentHash{}, false
	}
	if _, err := rs.Seek(0, io.SeekStart); err != nil {
		return contentHash{}, false
	}
	sum := hash.Sum(nil)
	result := contentHash{
		size:      size,
		modTime:   modTime,
		etag:      `"` + hex.EncodeToString(sum[:16]) + `"`,
		immutable: namesOwnHash(path.Base(name), sum),
	}
	h.hashes.Store(name, result)
	return result, true
}

// namesOwnHash reports whether base carries the first eight hex digits of
// its content's SHA-256 as a dotted segment, the names `flutter build web
// --web-content-hash` gives (main.dart.1a2b3c4d.wasm, NOTICES.1a2b3c4d).
func namesOwnHash(base string, sum []byte) bool {
	short := "." + hex.EncodeToString(sum[:4])
	return strings.Contains(base, short+".") || strings.HasSuffix(base, short)
}

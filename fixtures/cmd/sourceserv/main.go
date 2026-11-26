// Command sourceserv serves a canned acquisition source for the
// end-to-end harness: a playlist manifest at /playlist, a private one the
// bridge refuses at /playlist-private, a slow one at /playlist-slow whose
// entries each take about slowServe to download, and the entry audio at
// /audio/<id>, synthesized at startup with -generate. It is
// what the server's -source-stub-url bridge enumerates and fetches, so
// the playlist-sync scenarios run against a stubbed source instead of a
// real platform. Under /lyrics it is also a custom enrichment provider
// (docs/custom-provider-api) answering lyrics for one fixture title, so
// a health fix has a source to run against. It holds no state and must
// never face a real network.
//
//	sourceserv -dir /tmp/source -generate
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// manifest is the playlist document the bridge enumerates: entries in
// playlist order, each naming its audio by id.
type manifest struct {
	ID    string `json:"id"`
	Title string `json:"title"`
	// Refuse is the reason the bridge refuses the list for, as a source
	// refuses a private one.
	Refuse  string  `json:"refuse,omitempty"`
	Entries []entry `json:"entries"`
}

type entry struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

func main() {
	var (
		addr     = flag.String("addr", envOr("SOURCESERV_ADDR", "127.0.0.1:4422"), "listen address")
		dir      = flag.String("dir", "", "directory to serve (required)")
		generate = flag.Bool("generate", false, "synthesize the default source playlist into -dir before serving")
	)
	flag.Parse()
	if *dir == "" {
		fmt.Fprintln(os.Stderr, "sourceserv: -dir is required")
		flag.Usage()
		os.Exit(2)
	}

	if *generate {
		if err := generateDefault(*dir); err != nil {
			log.Fatalf("sourceserv: generating: %v", err)
		}
		log.Printf("sourceserv generated %s, %s and %s", filepath.Join(*dir, "playlist.json"),
			filepath.Join(*dir, privateManifest), filepath.Join(*dir, slowManifest))
	}

	log.Printf("sourceserv serving %s on %s", *dir, *addr)
	srv := &http.Server{Addr: *addr, Handler: &server{dir: *dir}, ReadHeaderTimeout: 5 * time.Second}
	log.Fatal(srv.ListenAndServe())
}

// privateManifest is the refused list's manifest file.
const privateManifest = "playlist-private.json"

// slowManifest is the slow list's manifest file; its entries' ids carry
// slowPrefix, and each is served over slowServe.
const (
	slowManifest = "playlist-slow.json"
	slowPrefix   = "vid-slow-"
	slowServe    = 15 * time.Second
)

// generateDefault synthesizes three single-track releases and the
// manifest listing them in order, a private list of one entry with audio
// of its own, and a slow list of three more.
func generateDefault(dir string) error {
	if err := generatePrivate(dir); err != nil {
		return err
	}
	if err := generateSlow(dir); err != nil {
		return err
	}
	specs := make([]fixtures.Spec, 3)
	m := manifest{ID: "PLstub", Title: "Stub Tapes"}
	for i := range specs {
		n := i + 1
		specs[i] = fixtures.Spec{
			Name:     fmt.Sprintf("stub-cut-%d", n),
			Codec:    fixtures.CodecMP3,
			Duration: time.Duration(3+n) * time.Second,
			Tags: map[string]string{
				"TITLE":  fmt.Sprintf("Stub Cut %d", n),
				"ARTIST": "DJ Stub",
				"ALBUM":  fmt.Sprintf("Stub Singles %d", n),
			},
		}
		m.Entries = append(m.Entries, entry{
			ID:    fmt.Sprintf("vid-%d", n),
			Title: fmt.Sprintf("Stub Cut %d", n),
		})
	}
	paths, err := fixtures.Generate(dir, specs...)
	if err != nil {
		return err
	}
	for i, p := range paths {
		final := filepath.Join(dir, fmt.Sprintf("vid-%d.mp3", i+1))
		if err := os.Rename(p, final); err != nil {
			return err
		}
	}
	raw, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, "playlist.json"), raw, 0o644)
}

// generatePrivate synthesizes the private list: one entry the bridge never
// reaches, since it refuses the list.
func generatePrivate(dir string) error {
	paths, err := fixtures.Generate(dir, fixtures.Spec{
		Name:     "stub-private",
		Codec:    fixtures.CodecMP3,
		Duration: 3 * time.Second,
		Tags:     map[string]string{"TITLE": "Stub Hidden", "ARTIST": "DJ Stub", "ALBUM": "Stub Private"},
	})
	if err != nil {
		return err
	}
	if err := os.Rename(paths[0], filepath.Join(dir, "vid-private.mp3")); err != nil {
		return err
	}
	raw, err := json.MarshalIndent(manifest{
		ID: "PLstubprivate", Title: "Stub Private", Refuse: "playlist-unavailable",
		Entries: []entry{{ID: "vid-private", Title: "Stub Hidden"}},
	}, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, privateManifest), raw, 0o644)
}

// generateSlow synthesizes the slow list: three entries with audio of
// their own, which the server hands out slowly.
func generateSlow(dir string) error {
	m := manifest{ID: "PLstubslow", Title: "Stub Slow"}
	for n := 1; n <= 3; n++ {
		paths, err := fixtures.Generate(dir, fixtures.Spec{
			Name:     fmt.Sprintf("stub-slow-%d", n),
			Codec:    fixtures.CodecMP3,
			Duration: time.Duration(3+n) * time.Second,
			Tags: map[string]string{
				"TITLE":  fmt.Sprintf("Stub Slow Cut %d", n),
				"ARTIST": "DJ Stub",
				"ALBUM":  fmt.Sprintf("Stub Slow Singles %d", n),
			},
		})
		if err != nil {
			return err
		}
		id := fmt.Sprintf("%s%d", slowPrefix, n)
		if err := os.Rename(paths[0], filepath.Join(dir, id+".mp3")); err != nil {
			return err
		}
		m.Entries = append(m.Entries, entry{ID: id, Title: fmt.Sprintf("Stub Slow Cut %d", n)})
	}
	raw, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(dir, slowManifest), raw, 0o644)
}

// serveSlowly writes the file at path over about slowServe, in pieces,
// stopping when the client goes.
func serveSlowly(w http.ResponseWriter, r *http.Request, path string) {
	data, err := os.ReadFile(path)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	const pieces = 30
	w.Header().Set("Content-Type", "audio/mpeg")
	w.Header().Set("Content-Length", strconv.Itoa(len(data)))
	flusher, _ := w.(http.Flusher)
	size := (len(data) + pieces - 1) / pieces
	tick := time.NewTicker(slowServe / pieces)
	defer tick.Stop()
	for len(data) > 0 {
		n := min(size, len(data))
		if _, err := w.Write(data[:n]); err != nil {
			return
		}
		if flusher != nil {
			flusher.Flush()
		}
		data = data[n:]
		if len(data) == 0 {
			return
		}
		select {
		case <-r.Context().Done():
			return
		case <-tick.C:
		}
	}
}

type server struct{ dir string }

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.URL.Path == "/playlist":
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		http.ServeFile(w, r, filepath.Join(s.dir, "playlist.json"))
	case r.URL.Path == "/playlist-private":
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		http.ServeFile(w, r, filepath.Join(s.dir, privateManifest))
	case r.URL.Path == "/playlist-slow":
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		http.ServeFile(w, r, filepath.Join(s.dir, slowManifest))
	case r.URL.Path == "/lyrics/capabilities":
		writeJSON(w, map[string]any{"name": "stubtapes-lyrics", "capabilities": []string{"lyrics"}})
	case r.URL.Path == "/lyrics/enrich" && r.Method == http.MethodPost:
		var req struct {
			Wants []string `json:"wants"`
			Title string   `json:"title"`
		}
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		// One title, so a fix fills one track and leaves the rest failing.
		if req.Title != lyricsTitle || !slices.Contains(req.Wants, "lyrics") {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		writeJSON(w, map[string]any{"lyrics": map[string]any{"unsynced": "Stubbed lyrics for " + lyricsTitle}})
	case strings.HasPrefix(r.URL.Path, "/audio/"):
		id := strings.TrimPrefix(r.URL.Path, "/audio/")
		if strings.ContainsAny(id, "/\\.") {
			http.NotFound(w, r)
			return
		}
		if strings.HasPrefix(id, slowPrefix) {
			serveSlowly(w, r, filepath.Join(s.dir, id+".mp3"))
			return
		}
		w.Header().Set("Content-Type", "audio/mpeg")
		http.ServeFile(w, r, filepath.Join(s.dir, id+".mp3"))
	default:
		http.NotFound(w, r)
	}
}

// lyricsTitle is the fixture track the stub provider knows lyrics for.
const lyricsTitle = "Alpha Song"

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("sourceserv: writing a response: %v", err)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

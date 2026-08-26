// Command sourceserv serves a canned acquisition source for the
// end-to-end harness: a playlist manifest at /playlist and the entry
// audio at /audio/<id>, synthesized at startup with -generate. It is
// what the server's -source-stub-url bridge enumerates and fetches, so
// the playlist-sync scenarios run against a stubbed source instead of a
// real platform. It holds no state and must never face a real network.
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
	"strings"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// manifest is the playlist document the bridge enumerates: entries in
// playlist order, each naming its audio by id.
type manifest struct {
	ID      string  `json:"id"`
	Title   string  `json:"title"`
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
		log.Printf("sourceserv generated %s", filepath.Join(*dir, "playlist.json"))
	}

	log.Printf("sourceserv serving %s on %s", *dir, *addr)
	srv := &http.Server{Addr: *addr, Handler: &server{dir: *dir}, ReadHeaderTimeout: 5 * time.Second}
	log.Fatal(srv.ListenAndServe())
}

// generateDefault synthesizes three single-track releases and the
// manifest listing them in order.
func generateDefault(dir string) error {
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

type server struct{ dir string }

func (s *server) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.URL.Path == "/playlist":
		w.Header().Set("Content-Type", "application/json; charset=utf-8")
		http.ServeFile(w, r, filepath.Join(s.dir, "playlist.json"))
	case strings.HasPrefix(r.URL.Path, "/audio/"):
		id := strings.TrimPrefix(r.URL.Path, "/audio/")
		if strings.ContainsAny(id, "/\\.") {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "audio/mpeg")
		http.ServeFile(w, r, filepath.Join(s.dir, id+".mp3"))
	default:
		http.NotFound(w, r)
	}
}

func envOr(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

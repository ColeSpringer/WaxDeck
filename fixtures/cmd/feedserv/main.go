// Command feedserv serves a directory of podcast-feed fixtures over
// HTTP for the end-to-end harness: feed.xml, episode audio, transcript
// and chapter documents, with correct content types, Range support, and
// ETag/Last-Modified conditional GETs so feed polling behaves like it
// does against a real host. With -generate it first synthesizes the
// default fixture feed into the directory, enclosure URLs pointing back
// at itself. It holds no state and must never face a real network.
//
//	feedserv -dir /tmp/feed -generate
package main

import (
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

func main() {
	var (
		addr     = flag.String("addr", envOr("FEEDSERV_ADDR", "127.0.0.1:4421"), "listen address")
		dir      = flag.String("dir", "", "directory to serve (required)")
		generate = flag.Bool("generate", false, "synthesize the default podcast feed into -dir before serving")
	)
	flag.Parse()
	if *dir == "" {
		fmt.Fprintln(os.Stderr, "feedserv: -dir is required")
		flag.Usage()
		os.Exit(2)
	}

	if *generate {
		baseURL := "http://" + *addr
		feedPath, err := fixtures.GeneratePodcastFeed(*dir, fixtures.DefaultPodcastFeed(baseURL), baseURL)
		if err != nil {
			log.Fatalf("feedserv: generating feed: %v", err)
		}
		log.Printf("feedserv generated %s", feedPath)
	}

	log.Printf("feedserv serving %s on %s", *dir, *addr)
	srv := &http.Server{Addr: *addr, Handler: &fileServer{dir: *dir}, ReadHeaderTimeout: 5 * time.Second}
	log.Fatal(srv.ListenAndServe())
}

// contentTypes maps served extensions to their MIME types. Chapter
// documents get the Podcasting 2.0 type via a suffix check before this
// table is consulted.
var contentTypes = map[string]string{
	".xml":  "application/rss+xml; charset=utf-8",
	".mp3":  "audio/mpeg",
	".m4a":  "audio/mp4",
	".m4b":  "audio/mp4",
	".aac":  "audio/aac",
	".ogg":  "audio/ogg",
	".opus": "audio/ogg",
	".flac": "audio/flac",
	".vtt":  "text/vtt; charset=utf-8",
	".json": "application/json",
}

// fileServer is a minimal wrapper over http.ServeFile: it pins content
// types the stdlib sniffer would get wrong for feed media, adds a weak
// ETag from each file's size and mtime (ServeContent then honors
// If-None-Match, including on feed.xml conditional polls; Range and
// Last-Modified come with it), and logs one line per request.
type fileServer struct {
	dir string
}

func (s *fileServer) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	lw := &loggingWriter{ResponseWriter: w, status: http.StatusOK}
	defer func() { log.Printf("%s %s %d", r.Method, r.URL.Path, lw.status) }()

	// path.Clean on a rooted path removes any traversal before the
	// URL path is mapped onto the served directory.
	name := path.Clean("/" + r.URL.Path)
	if name == "/" {
		name = "/feed.xml"
	}
	fp := filepath.Join(s.dir, filepath.FromSlash(name))
	info, err := os.Stat(fp)
	if err != nil || info.IsDir() {
		http.NotFound(lw, r)
		return
	}
	if ct := contentTypeFor(fp); ct != "" {
		lw.Header().Set("Content-Type", ct)
	}
	lw.Header().Set("ETag", fmt.Sprintf(`"%x-%x"`, info.ModTime().UnixNano(), info.Size()))
	http.ServeFile(lw, r, fp)
}

// contentTypeFor resolves a served file's MIME type; empty falls back
// to ServeFile's own extension and sniff logic.
func contentTypeFor(fp string) string {
	base := strings.ToLower(filepath.Base(fp))
	if strings.HasSuffix(base, ".chapters.json") {
		return "application/json+chapters"
	}
	return contentTypes[filepath.Ext(base)]
}

// loggingWriter records the status code for the per-request log line.
type loggingWriter struct {
	http.ResponseWriter
	status int
}

func (w *loggingWriter) WriteHeader(status int) {
	w.status = status
	w.ResponseWriter.WriteHeader(status)
}

func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

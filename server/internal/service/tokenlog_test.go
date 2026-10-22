package service

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"math/rand/v2"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
)

// A tokenized feed's enclosure and cover addresses carry its token, so an
// episode download that fails and a cover the catalog could not fetch say
// so in the log, and in the fetch queue the API reads, without them.
func TestDownloadAndCatalogFailuresNameNoAddress(t *testing.T) {
	var logged lockedBuffer
	dir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
		cfg.Logger = slog.New(slog.NewTextHandler(&logged, &slog.HandlerOptions{Level: slog.LevelDebug}))
	})
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasSuffix(r.URL.Path, "/feed.xml") {
			http.Error(w, "no", http.StatusForbidden)
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprintf(w, `<?xml version="1.0"?><rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>Token Show</title>
<itunes:image href="http://%[1]s/s3cr3t-token/cover.png"/>
<item><title>One</title><guid>token-1</guid><enclosure url="http://%[1]s/s3cr3t-token/one.mp3" type="audio/mpeg" length="100"/></item>
</channel></rss>`, r.Host)
	}))
	t.Cleanup(ts.Close)
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: ts.URL + "/s3cr3t-token/feed.xml"})
	if err != nil {
		t.Fatal(err)
	}
	eps, _, err := svc.Episodes(ctx, uc, sub.Show.PID, "", 10)
	if err != nil || len(eps) != 1 {
		t.Fatalf("episodes = %+v (%v), want one", eps, err)
	}
	if err := svc.QueueEpisodeFetch(ctx, uc, eps[0].PID); err != nil {
		t.Fatal(err)
	}
	if !svc.DrainFetchQueue(ctx) {
		t.Fatal("the fetch queue had nothing to work")
	}
	_, bare, _ := parseAPIPID(eps[0].PID)
	rows, err := svc.db.FetchQueueRows(ctx, []string{string(bare)})
	if lastErr := rows[string(bare)].LastError; err != nil || lastErr == "" || strings.Contains(lastErr, "s3cr3t") {
		t.Errorf("the queue's failure = %q (%v), want a sentence naming no address", lastErr, err)
	}
	out := logged.String()
	if !strings.Contains(out, "episode fetch failed") || !strings.Contains(out, "reason=host-refused") {
		t.Errorf("log = %q, want the download's failure and its reason", out)
	}
	for _, line := range strings.Split(out, "\n") {
		if strings.Contains(line, "s3cr3t-token") {
			t.Errorf("a log line names a tokenized address: %q", line)
		}
	}
}

// A chapters document's address can carry its feed's token too, so a
// failed read of one logs its host and what went wrong, never the address,
// at every level: a dead host, a redirect to a scheme the fetch refuses,
// and a host's error status.
func TestAChaptersFailureLogsNoAddress(t *testing.T) {
	var logged lockedBuffer
	_, svc, _, _ := openServiceAt(t, t.TempDir(), func(cfg *Config) {
		cfg.AllowPrivateFeedHosts = true
		cfg.Logger = slog.New(slog.NewTextHandler(&logged, &slog.HandlerOptions{Level: slog.LevelDebug}))
	})
	withOpenShows(svc)
	closed, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	dead := "http://" + closed.Addr().String()
	closed.Close()
	refusing := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "ftp://"+r.Host+"/s3cr3t-path/x.json?auth=s3cr3t-token", http.StatusFound)
	}))
	t.Cleanup(refusing.Close)
	missing := httptest.NewServer(http.NotFoundHandler())
	t.Cleanup(missing.Close)
	for i, c := range []struct{ base, cause string }{
		{dead, "cause=dial"},
		{refusing.URL, `cause="redirect refused"`},
		{missing.URL, `cause="status 404"`},
	} {
		before := len(logged.String())
		ep := chaptersEpisode(fmt.Sprintf("ep-%d", i), c.base+"/s3cr3t-path/chapters.json?auth=s3cr3t-token")
		if got := svc.fetchedChapters(context.Background(), "", ep); len(got) != 0 {
			t.Errorf("%s gave chapters %+v", c.base, got)
		}
		if line := logged.String()[before:]; !strings.Contains(line, "chapters") || !strings.Contains(line, c.cause) {
			t.Errorf("log for %s = %q, want a chapters line with %s", c.base, line, c.cause)
		}
	}
	for _, line := range strings.Split(logged.String(), "\n") {
		if strings.Contains(line, "s3cr3t") {
			t.Errorf("a log line names a chapters address: %q", line)
		}
	}
}

// Every web address in a catalog log line is cut to its scheme and host,
// in the message, a value, an error, a group or an attribute set once.
func TestTheCatalogsLogKeepsHostsOnly(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{
		"netsafe.Do: http://u:p@a.example:8080/s3cr3t/feed.xml?k=s3cr3t returned HTTP 403": "netsafe.Do: http://a.example:8080 returned HTTP 403",
		`Get "https://a.example/s3cr3t": dial tcp: connection refused`:                     `Get "https://a.example": dial tcp: connection refused`,
		"https://a.example/x and http://b.example/y":                                       "https://a.example and http://b.example",
		"https://a.example":  "https://a.example",
		"no address in here": "no address in here",
	} {
		if got := hostOnly(in); got != want {
			t.Errorf("hostOnly(%q) = %q, want %q", in, got, want)
		}
	}
	var logged lockedBuffer
	log := slog.New(hostOnlyHandler{slog.NewTextHandler(&logged, &slog.HandlerOptions{Level: slog.LevelDebug})})
	log.With("feed", "https://a.example/s3cr3t/feed.xml").Debug("fetching https://a.example/s3cr3t/x",
		"url", "https://a.example/s3cr3t/cover.png",
		"err", fmt.Errorf("netsafe.Do: %s returned HTTP 404", "https://a.example/s3cr3t/cover.png"),
		slog.Group("page", "next", "https://a.example/s3cr3t?page=2"))
	if out := logged.String(); strings.Contains(out, "s3cr3t") || !strings.Contains(out, "https://a.example") {
		t.Errorf("log = %q, want every address at its host", out)
	}
}

type nilPtrErr struct{ msg string }

func (e *nilPtrErr) Error() string { return e.msg }

type nilPtrStringer struct{ s string }

func (s *nilPtrStringer) String() string { return s.s }

// The cutter takes an address whatever its scheme's case, keeps the
// punctuation after it, and never panics a log line: a typed nil prints
// as the plain handler prints it.
func TestTheAddressCutterTakesEveryShape(t *testing.T) {
	t.Parallel()
	for in, want := range map[string]string{
		"HTTPS://A.EXAMPLE/s3cr3t/feed.xml":                        "HTTPS://A.EXAMPLE",
		"Http://a.example/s3cr3t":                                  "Http://a.example",
		"see (https://a.example/x?y=s3cr3t).":                      "see (https://a.example).",
		"https://a.example/s3cr3t, then https://b.example/s3cr3t;": "https://a.example, then https://b.example;",
		"[https://a.example/s3cr3t]!":                              "[https://a.example]!",
		"https://":                                                 "https://",
		"https:///s3cr3t":                                          "https://",
		"http://[::1]":                                             "http://[::1]",
		"(http://[::1])":                                           "(http://[::1])",
		"http://[::1].":                                            "http://[::1].",
		"[http://[::1]/s3cr3t]":                                    "[http://[::1]]",
	} {
		if got := hostOnly(in); got != want {
			t.Errorf("hostOnly(%q) = %q, want %q", in, got, want)
		}
	}
	var typedNilErr *nilPtrErr
	var typedNilStringer *nilPtrStringer
	page, _ := url.Parse("https://a.example/s3cr3t?k=s3cr3t")
	var plain, cut lockedBuffer
	opts := &slog.HandlerOptions{Level: slog.LevelDebug}
	base := slog.New(slog.NewTextHandler(&plain, opts))
	wrapped := slog.New(hostOnlyHandler{slog.NewTextHandler(&cut, opts)})
	args := []any{"err", typedNilErr, "who", typedNilStringer}
	base.Warn("typed nils", args...)
	func() {
		defer func() {
			if r := recover(); r != nil {
				t.Errorf("a typed nil panicked the log line: %v", r)
			}
		}()
		wrapped.Warn("typed nils", args...)
		wrapped.Warn("an address by value", "page", *page)
	}()
	if want := strings.SplitN(plain.String(), "level=", 2)[1]; !strings.Contains(cut.String(), want) {
		t.Errorf("cut log = %q, want the plain handler's %q", cut.String(), want)
	}
	if strings.Contains(cut.String(), "s3cr3t") {
		t.Errorf("cut log = %q, want an address by value cut too", cut.String())
	}
}

// Whatever text a line carries, cutting it never panics and leaves no
// address's path, query or user part behind.
func TestTheAddressCutterLeavesNoPathBehind(t *testing.T) {
	t.Parallel()
	schemes := []string{"http://", "https://", "HTTPS://", "Http://", "hTtPs://"}
	hosts := []string{"a.example", "a.example:8080", "u:s3cr3t@a.example", "127.0.0.1:4420", "[::1]:80", "[::1]", ""}
	tails := []string{"", "/", "/s3cr3t", "/s3cr3t/feed.xml", "?k=s3cr3t", "/x?k=s3cr3t#s3cr3t", "/%zz/s3cr3t", "/a(s3cr3t)"}
	gaps := []string{"", " ", ".", ",", ";", ":", ")", "]", "}", "!", "?", "\"", "'", "<", ">", "(", "\n", "x"}
	rng := rand.New(rand.NewPCG(1, 2))
	pick := func(from []string) string { return from[rng.IntN(len(from))] }
	// A handler that writes, so every line goes through Handle.
	var written strings.Builder
	log := slog.New(hostOnlyHandler{slog.NewTextHandler(&written, &slog.HandlerOptions{Level: slog.LevelDebug})})
	for range 20_000 {
		var b strings.Builder
		for range 1 + rng.IntN(4) {
			b.WriteString(pick(gaps))
			b.WriteString(pick(schemes) + pick(hosts) + pick(tails))
			b.WriteString(pick(gaps))
		}
		in := b.String()
		var out string
		written.Reset()
		func() {
			defer func() {
				if r := recover(); r != nil {
					t.Fatalf("cutting or logging %q panicked: %v", in, r)
				}
			}()
			out = hostOnly(in)
			log.Info(in, "text", in, "err", errors.New(in), slog.Group("g", "text", in))
		}()
		if strings.Contains(out, "s3cr3t") {
			t.Fatalf("hostOnly(%q) = %q, a path, query or user part survived", in, out)
		}
		if again := hostOnly(out); again != out {
			t.Fatalf("hostOnly(%q) = %q, and cutting that again gives %q", in, out, again)
		}
		if line := written.String(); line == "" || strings.Contains(line, "s3cr3t") {
			t.Fatalf("the log line for %q = %q, want one with no path, query or user part", in, line)
		}
	}
}

// A sync that fails keeps why in the feed's state without the address,
// which can be the feed's own credential.
func TestAFailedSyncKeepsNoAddress(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := openPodcastFixture(t)
	var down atomic.Bool
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if down.Load() {
			http.Error(w, "down", http.StatusServiceUnavailable)
			return
		}
		w.Header().Set("Content-Type", "application/rss+xml")
		fmt.Fprint(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Kept</title>
<item><title>One</title><guid>kept-1</guid></item></channel></rss>`)
	}))
	t.Cleanup(ts.Close)
	sub, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: ts.URL + "/s3cr3t-token/feed.xml"})
	if err != nil {
		t.Fatal(err)
	}
	down.Store(true)
	_, bare, _ := parseAPIPID(sub.Show.PID)
	if _, err := svc.syncShow(ctx, bare, syncOwn); FeedFailureReason(err) != reasonHostError {
		t.Fatalf("sync = %v, want the host's error", err)
	}
	st, err := svc.db.FeedStateFor(ctx, string(bare))
	if err != nil || st.LastError == "" || strings.Contains(st.LastError, "s3cr3t") || strings.Contains(st.LastError, "://") {
		t.Fatalf("feed state = %+v (%v), want why without the address", st, err)
	}
}

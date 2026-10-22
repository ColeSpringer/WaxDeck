package service

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"path/filepath"
	"strings"
	"sync"
	"testing"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/podcast"
	"github.com/colespringer/waxbin/source"
	"github.com/colespringer/waxbin/waxerr"
)

// feedHost answers each path the way a misbehaving feed host does.
func feedHost(t *testing.T) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/html", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/html")
		io.WriteString(w, "<!doctype html><html><body>a web page</body></html>")
	})
	mux.HandleFunc("/png", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/png")
		w.Write([]byte("\x89PNG\r\n\x1a\n"))
	})
	mux.HandleFunc("/json", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		io.WriteString(w, "<html>not json</html>")
	})
	mux.HandleFunc("/huge", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/rss+xml")
		io.WriteString(w, `<?xml version="1.0"?><rss version="2.0"><channel><title>Big</title><!--`)
		io.WriteString(w, strings.Repeat("x", 16<<20))
		io.WriteString(w, `--></channel></rss>`)
	})
	mux.HandleFunc("/loop", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "/loop", http.StatusFound)
	})
	for _, code := range []int{401, 403, 404, 410, 429, 500, 503} {
		mux.HandleFunc(fmt.Sprintf("/status/%d", code), func(w http.ResponseWriter, r *http.Request) {
			http.Error(w, http.StatusText(code), code)
		})
	}
	ts := httptest.NewServer(mux)
	t.Cleanup(ts.Close)
	return ts
}

// closedAddress is a loopback address nothing listens on.
func closedAddress(t *testing.T) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	addr := ln.Addr().String()
	ln.Close()
	return addr
}

func openFeedClients(t *testing.T, allowPrivate bool) (context.Context, *Library) {
	t.Helper()
	dir := t.TempDir()
	ctx, svc, _, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = allowPrivate
	})
	return ctx, svc
}

// The reason comes off what the clients actually raise: WaxBin's feed
// client through AddSource, and WaxDeck's own transcript fetch. Its
// netsafe package is internal and words these failures without a type to
// test, so a change of wording there fails here.
func TestFeedFailureReasonOfTheRealClients(t *testing.T) {
	t.Parallel()
	host := feedHost(t)
	dead := "http://" + closedAddress(t)
	ctx, svc := openFeedClients(t, true)
	_, guarded := openFeedClients(t, false)

	feeds := []struct {
		name string
		lib  *Library
		url  string
		want string
	}{
		{"a web page", svc, host.URL + "/html", reasonNotAFeed},
		{"an image", svc, host.URL + "/png", reasonNotAFeed},
		{"a feed over the size cap", svc, host.URL + "/huge", reasonTooLarge},
		{"a private address", guarded, host.URL + "/html", reasonBlockedAddress},
		{"a 401", svc, host.URL + "/status/401", reasonHostRefused},
		{"a 403", svc, host.URL + "/status/403", reasonHostRefused},
		{"a 404", svc, host.URL + "/status/404", reasonHostMissing},
		{"a 410", svc, host.URL + "/status/410", reasonHostMissing},
		{"a 429", svc, host.URL + "/status/429", reasonHostError},
		{"a 500", svc, host.URL + "/status/500", reasonHostError},
		{"a 503", svc, host.URL + "/status/503", reasonHostError},
		{"a redirect loop", svc, host.URL + "/loop", reasonHostError},
		{"nothing listening", svc, dead + "/feed.xml", reasonUnreachable},
	}
	for _, c := range feeds {
		_, err := c.lib.lib.Podcasts().AddSource(ctx, c.url, model.SourceRSS, podcast.AddOptions{})
		if err == nil {
			t.Errorf("%s: subscribed", c.name)
			continue
		}
		if !feedAtFault(ctx, err) {
			t.Errorf("%s: %v is not the feed's failure", c.name, err)
		}
		reason, sentence := feedFailureReason(err)
		if reason != c.want {
			t.Errorf("%s: reason %q from %q, want %q", c.name, reason, err, c.want)
		}
		if sentence != feedSentences[c.want] {
			t.Errorf("%s: sentence %q, want %q", c.name, sentence, feedSentences[c.want])
		}
	}

	transcripts := []struct {
		name string
		lib  *Library
		url  string
		want string
	}{
		{"a document that is not one", svc, host.URL + "/json", reasonNotAFeed},
		{"a private address", guarded, host.URL + "/status/403", reasonBlockedAddress},
		{"a 403", svc, host.URL + "/status/403", reasonHostRefused},
		{"a 404", svc, host.URL + "/status/404", reasonHostMissing},
		{"a 503", svc, host.URL + "/status/503", reasonHostError},
		{"a document over the size cap", svc, host.URL + "/huge", reasonTooLarge},
		{"a redirect loop", svc, host.URL + "/loop", reasonHostError},
		{"nothing listening", svc, dead + "/t.vtt", reasonUnreachable},
	}
	for _, c := range transcripts {
		_, err := c.lib.fetchTranscript(ctx, c.url, "", feedLogin{})
		if err == nil {
			t.Errorf("transcript %s: fetched", c.name)
			continue
		}
		if reason, _ := feedFailureReason(hostFailure(ctx, "test", err)); reason != c.want {
			t.Errorf("transcript %s: reason %q from %q, want %q", c.name, reason, err, c.want)
		}
	}
}

// What the real clients cannot be made to raise in a test, worded the way
// they word it.
func TestFeedFailureReasonOfTheRarerFailures(t *testing.T) {
	t.Parallel()
	pe := func(err error) error {
		return &source.ProviderError{SourceType: model.SourceRSS, Op: "enumerate", Err: err}
	}
	fetching := func(err error) error {
		return pe(waxerr.Wrapf(waxerr.CodeIO, "netsafe.Do", &url.Error{Op: "Get", URL: "https://feed.example/rss", Err: err},
			"fetching %s", "https://feed.example/rss"))
	}
	// What net/http itself answers for a pointer it cannot even ask.
	_, notAURL := http.NewRequest(http.MethodGet, "://transcript", nil)
	_, otherScheme := http.DefaultClient.Get("ftp://feeds.example/t.vtt")
	_, relative := http.DefaultClient.Get("transcripts/t.vtt")
	for _, c := range []struct {
		name string
		err  error
		want string
	}{
		{"a name that does not resolve", fetching(&net.OpError{Op: "dial", Net: "tcp",
			Err: &net.DNSError{Err: "no such host", Name: "feed.example", IsNotFound: true}}), reasonUnreachable},
		{"a host that never answers", fetching(timeoutError{}), reasonUnreachable},
		{"a connection cut mid-body", pe(waxerr.Wrap(waxerr.CodeIO, "netsafe.read", io.ErrUnexpectedEOF)), reasonUnreachable},
		{"a status the client stopped at", pe(waxerr.New(waxerr.CodeIO, "netsafe.Do", "https://feed.example/rss returned HTTP 304")), reasonHostError},
		{"a 451", pe(waxerr.New(waxerr.CodeIO, "netsafe.Do", "https://feed.example/rss returned HTTP 451")), reasonHostRefused},
		{"a not-modified nobody asked for", pe(waxerr.New(waxerr.CodeIO, "podcast.AddSource", "feed returned not-modified to an unconditional request")), reasonHostError},
		{"neither a feed nor not-modified", pe(waxerr.New(waxerr.CodeIO, "podcast.AddSource", "provider returned neither a feed nor not-modified")), reasonHostError},
		{"a provider's own failure", pe(errors.New("bridge went away")), reasonHostError},
		{"a transcript pointer that is no URL", hostFailure(context.Background(), "t", fmt.Errorf("bad transcript url: %w", notAURL)), reasonNotAFeed},
		{"a transcript pointer on another scheme", hostFailure(context.Background(), "t", otherScheme), reasonNotAFeed},
		{"a relative transcript pointer", hostFailure(context.Background(), "t", relative), reasonNotAFeed},
	} {
		if reason, _ := feedFailureReason(c.err); reason != c.want {
			t.Errorf("%s: reason %q, want %q", c.name, reason, c.want)
		}
	}
}

type timeoutError struct{}

func (timeoutError) Error() string   { return "i/o timeout" }
func (timeoutError) Timeout() bool   { return true }
func (timeoutError) Temporary() bool { return true }

// A host's error or a host out of reach can pass on its own; the rest
// answer the same way until somebody changes the address or the server.
func TestFeedFailureReasonsThatCanPass(t *testing.T) {
	t.Parallel()
	for reason, sentence := range feedSentences {
		want := reason != reasonHostError && reason != reasonUnreachable
		if got := feedReasonPermanent(reason); got != want {
			t.Errorf("%s permanent = %v, want %v", reason, got, want)
		}
		if transcriptSentences[reason] == "" || transcriptSentences[reason] == sentence {
			t.Errorf("%s has no transcript wording of its own", reason)
		}
		for _, s := range []string{sentence, transcriptSentences[reason]} {
			if strings.Contains(s, "http") || strings.Contains(s, "provider") || strings.Contains(s, "podcast.") {
				t.Errorf("%s says %q", reason, s)
			}
		}
	}
	if len(feedSentences) != 7 {
		t.Errorf("reasons = %d, want the closed set of seven", len(feedSentences))
	}
}

// Every reason is worded for every document a fetch can fail on: the
// feed, an episode's transcript and its audio, each in words of its own.
func TestEveryFeedReasonIsWordedForEveryDocument(t *testing.T) {
	t.Parallel()
	for name, sentences := range map[string]map[string]string{
		"transcript": transcriptSentences, "download": downloadSentences,
	} {
		if len(sentences) != len(feedSentences) {
			t.Errorf("%s sentences = %d, want one for each of the %d reasons", name, len(sentences), len(feedSentences))
		}
		for reason, feed := range feedSentences {
			if s := sentences[reason]; s == "" || s == feed {
				t.Errorf("%s has no %s wording of its own: %q", reason, name, s)
			}
		}
	}
}

// lockedBuffer is a log sink tests can read while the service writes.
type lockedBuffer struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *lockedBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *lockedBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// A feed URL can be its own credential, so the log of a failed fetch
// names the host and the reason, never the path a token rides in, at
// the levels a server runs with.
func TestAFeedFailureLogsNoFeedURL(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	dir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
		cfg.Logger = slog.New(slog.NewTextHandler(&logged, &slog.HandlerOptions{Level: slog.LevelInfo}))
	})
	host := feedHost(t)
	secret := host.URL + "/status/404/s3cr3t-token"
	_, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: secret})
	if FeedFailureReason(err) != reasonHostMissing {
		t.Fatalf("subscribe = %v, want host-missing", err)
	}
	out := logged.String()
	if !strings.Contains(out, "host-missing") {
		t.Errorf("log = %q, want the reason", out)
	}
	if strings.Contains(out, "s3cr3t-token") {
		t.Errorf("log names the feed's path: %q", out)
	}
}

// A feed failure's log line says what went wrong in words that carry no
// URL: the host's status, or the kind of network failure.
func TestAFeedFailureLogsItsCause(t *testing.T) {
	t.Parallel()
	var logged lockedBuffer
	dir := t.TempDir()
	ctx, svc, uc, _ := openServiceAt(t, dir, func(cfg *Config) {
		cfg.PodcastDir = filepath.Join(dir, "podcasts")
		cfg.PodcastRootName = "podcasts"
		cfg.AllowPrivateFeedHosts = true
		cfg.Logger = slog.New(slog.NewTextHandler(&logged, &slog.HandlerOptions{Level: slog.LevelInfo}))
	})
	host := feedHost(t)
	tlsHost := httptest.NewTLSServer(http.NotFoundHandler())
	t.Cleanup(tlsHost.Close)
	closed, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	refused := "http://" + closed.Addr().String()
	closed.Close()
	for _, c := range []struct{ url, cause string }{
		{host.URL + "/status/503?token=s3cr3t", `cause="status 503"`},
		{refused + "/s3cr3t/feed.xml", "cause=dial"},
		{tlsHost.URL + "/s3cr3t/feed.xml", "cause=tls"},
	} {
		before := len(logged.String())
		if _, _, err := svc.Subscribe(ctx, uc, SubscribeRequest{URL: c.url}); FeedFailureReason(err) == "" {
			t.Fatalf("subscribe to %s = %v, want a feed-side failure", c.cause, err)
		}
		line := logged.String()[before:]
		if !strings.Contains(line, c.cause) {
			t.Errorf("log = %q, want %s", line, c.cause)
		}
		if strings.Contains(line, "s3cr3t") {
			t.Errorf("log names the feed's address: %q", line)
		}
	}
}

// What an import entry or an inbox row says about a failed subscribe is
// a sentence of the service's own: a feed's reason with it, nothing a
// wrapped error said, and an acronym spelled as one.
func TestSubscribeFailureSaysOnlyTheServicesWords(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name         string
		err          error
		want, reason string
	}{
		{"a feed's failure", feedUnreachable(pe404()), feedSentences[reasonHostMissing], reasonHostMissing},
		{"an internal failure", &Error{Kind: KindInternal, Err: errors.New("sqlite: disk I/O error")}, "The feed could not be subscribed.", ""},
		{"a bare error", errors.New("sqlite: disk I/O error"), "The feed could not be subscribed.", ""},
		{"a refused address", errInvalid("url must be http or https"), "URL must be http or https.", ""},
		{"a refusal of the account", requirePodcastManagement(&UserCtx{}), "This account cannot manage podcasts.", ""},
		{"a catalog refusal", classify(waxerr.New(waxerr.CodeInvalid, "podcast.AddSource", "feed has no usable identity (url or guid)")),
			"Feed has no usable identity (url or guid).", ""},
	} {
		sentence, reason := subscribeFailure(c.err)
		if sentence != c.want || reason != c.reason {
			t.Errorf("%s: (%q, %q), want (%q, %q)", c.name, sentence, reason, c.want, c.reason)
		}
		if strings.Contains(sentence, "sqlite") || strings.Contains(sentence, "podcast.") {
			t.Errorf("%s: says %q", c.name, sentence)
		}
	}
}

func pe404() error {
	return &source.ProviderError{SourceType: model.SourceRSS, Op: "enumerate",
		Err: waxerr.New(waxerr.CodeNotFound, "netsafe.Do", "https://feed.example/rss returned HTTP 404")}
}

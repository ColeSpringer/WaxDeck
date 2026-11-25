package providers

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/art"
)

func TestCoreThrottledSentinel(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusTooManyRequests)
	}))
	defer srv.Close()

	mb := NewMusicBrainz(MusicBrainzConfig{
		BaseURL:     srv.URL,
		HTTPClient:  srv.Client(),
		MinInterval: time.Nanosecond,
	})
	_, err := mb.ReleaseByMBID(context.Background(), "rel-1")
	if !errors.Is(err, ErrThrottled) {
		t.Fatalf("want ErrThrottled, got %v", err)
	}
}

func TestCoreServiceUnavailableThrottled(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer srv.Close()

	c := newCore(srv.Client(), "test-agent", time.Nanosecond)
	_, _, err := c.get(context.Background(), srv.URL+"/x", 0)
	if !errors.Is(err, ErrThrottled) {
		t.Fatalf("want ErrThrottled, got %v", err)
	}
}

func TestCoreUserAgent(t *testing.T) {
	var got atomic.Value
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got.Store(r.Header.Get("User-Agent"))
		w.Write([]byte("{}"))
	}))
	defer srv.Close()

	c := newCore(srv.Client(), "test-agent/1.0", time.Nanosecond)
	if _, _, err := c.get(context.Background(), srv.URL+"/x", 0); err != nil {
		t.Fatal(err)
	}
	if ua, _ := got.Load().(string); ua != "test-agent/1.0" {
		t.Fatalf("User-Agent = %q, want test-agent/1.0", ua)
	}
}

func TestCorePaceRespectsContext(t *testing.T) {
	c := newCore(nil, "test-agent", time.Hour)
	if err := c.pace(context.Background(), "h"); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if err := c.pace(ctx, "h"); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("want DeadlineExceeded, got %v", err)
	}
}

func TestFetchImageRequiresHTTPS(t *testing.T) {
	c := newCore(nil, "test-agent", time.Nanosecond)
	_, _, err := fetchImage(context.Background(), c, "http://example.com/cover.jpg")
	if err == nil || !strings.Contains(err.Error(), "https required") {
		t.Fatalf("want https-required error, got %v", err)
	}
}

func TestFetchImageContentType(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch r.URL.Path {
		case "/cover.webp":
			w.Header().Set("Content-Type", "image/webp; charset=binary")
			w.Write([]byte("RIFFxxxxWEBP"))
		case "/cover.svg":
			w.Header().Set("Content-Type", "image/svg+xml")
			w.Write([]byte(`<svg xmlns="http://www.w3.org/2000/svg"><script/></svg>`))
		default:
			w.Header().Set("Content-Type", "text/html")
			w.Write([]byte("<html>not an image</html>"))
		}
	}))
	defer srv.Close()

	c := newCore(srv.Client(), "test-agent", time.Nanosecond)
	data, mediaType, err := fetchImage(context.Background(), c, srv.URL+"/cover.webp")
	if err != nil {
		t.Fatal(err)
	}
	if mediaType != "image/webp" {
		t.Fatalf("media type = %q, want image/webp", mediaType)
	}
	if !bytes.Equal(data, []byte("RIFFxxxxWEBP")) {
		t.Fatalf("unexpected image bytes %q", data)
	}
	if got := art.NormalizeFormat(mediaType); got != "webp" {
		t.Fatalf("NormalizeFormat = %q, want webp", got)
	}

	if _, _, err := fetchImage(context.Background(), c, srv.URL+"/page.html"); err == nil ||
		!strings.Contains(err.Error(), "not an image") {
		t.Fatalf("want non-image content type error, got %v", err)
	}

	// An image type by the letter and a document in fact. Nothing here
	// decodes one, and it would be stored under the remote's own word for
	// it and served back from WaxDeck's origin, so it stops at the door.
	if _, _, err := fetchImage(context.Background(), c, srv.URL+"/cover.svg"); err == nil ||
		!strings.Contains(err.Error(), "is markup") {
		t.Fatalf("want markup content type error, got %v", err)
	}
}

func TestFetchImageSizeCap(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/jpeg")
		w.Write(make([]byte, maxImageBytes+1))
	}))
	defer srv.Close()

	c := newCore(srv.Client(), "test-agent", time.Nanosecond)
	// Too large now is too large next pass: a miss, not a failure.
	if _, _, err := fetchImage(context.Background(), c, srv.URL+"/big.jpg"); err == nil ||
		!strings.Contains(err.Error(), "exceeds") || !errors.Is(err, errImageGone) {
		t.Fatalf("want size cap error, got %v", err)
	}
}

// A URL that does not parse keeps its parse error for the log, and is a
// miss: it comes back the same.
func TestFetchImageKeepsTheParseError(t *testing.T) {
	c := newCore(http.DefaultClient, "test-agent", time.Nanosecond)
	_, _, err := fetchImage(context.Background(), c, "https://bad host/cover.jpg")
	if err == nil || !errors.Is(err, errImageGone) || !strings.Contains(err.Error(), "invalid character") {
		t.Fatalf("want the parse error kept beside the miss, got %v", err)
	}
}

func TestFetchImageRefusesNonHTTPSRedirect(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "http://insecure.example/cover.jpg", http.StatusFound)
	}))
	defer srv.Close()

	c := newCore(srv.Client(), "test-agent", time.Nanosecond)
	// The same redirect comes back next pass: a miss, not a failure.
	if _, _, err := fetchImage(context.Background(), c, srv.URL+"/redir"); err == nil ||
		!strings.Contains(err.Error(), "non-https") || !errors.Is(err, errImageGone) {
		t.Fatalf("want non-https redirect error, got %v", err)
	}
}

// The response cache is bounded by what it holds as well as by how many: a
// few large bodies must not sit in memory for the days a provider keeps them.
func TestCoreCacheIsBoundedByBytes(t *testing.T) {
	body := bytes.Repeat([]byte("x"), 1000)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/huge" {
			w.Write(bytes.Repeat([]byte("y"), 5000))
			return
		}
		w.Write(body)
	}))
	defer srv.Close()

	c := newCore(srv.Client(), "test", time.Nanosecond)
	c.maxBytes = 4000
	get := func(path string) {
		t.Helper()
		if _, status, err := c.get(context.Background(), srv.URL+path, time.Hour); err != nil || status != 200 {
			t.Fatalf("get %s: status %d, %v", path, status, err)
		}
	}
	held := func() (n, size int) {
		for k, e := range c.cache {
			n, size = n+1, size+len(k)+len(e.body)
		}
		return n, size
	}
	for i := range 10 {
		get(fmt.Sprintf("/%d", i))
		if _, size := held(); size > c.maxBytes || size != c.cacheBytes {
			t.Fatalf("after %d bodies the cache holds %d bytes (counted %d), over its bound of %d", i+1, size, c.cacheBytes, c.maxBytes)
		}
	}
	// The newest stay, the oldest went.
	n, _ := held()
	if _, ok := c.cached(srv.URL+"/9", time.Hour); !ok || n != 3 {
		t.Fatalf("cache holds %d entries (newest kept %v), want the three newest that fit", n, ok)
	}
	if _, ok := c.cached(srv.URL+"/0", time.Hour); ok {
		t.Fatal("the oldest body is still cached")
	}
	// A body larger than the whole bound is answered and not kept.
	get("/huge")
	if _, ok := c.cached(srv.URL+"/huge", time.Hour); ok {
		t.Fatal("a body larger than the bound was cached")
	}
	// Forgetting gives the bytes back.
	c.forgetPrefix(srv.URL)
	if n, size := held(); n != 0 || size != 0 || c.cacheBytes != 0 {
		t.Fatalf("after forgetting: %d entries, %d bytes, counted %d", n, size, c.cacheBytes)
	}
}

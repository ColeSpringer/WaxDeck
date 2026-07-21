package providers

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
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
	if got := imageFormat(mediaType); got != "webp" {
		t.Fatalf("imageFormat = %q, want webp", got)
	}

	if _, _, err := fetchImage(context.Background(), c, srv.URL+"/page.html"); err == nil ||
		!strings.Contains(err.Error(), "not an image") {
		t.Fatalf("want non-image content type error, got %v", err)
	}
}

func TestFetchImageSizeCap(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "image/jpeg")
		w.Write(make([]byte, maxImageBytes+1))
	}))
	defer srv.Close()

	c := newCore(srv.Client(), "test-agent", time.Nanosecond)
	if _, _, err := fetchImage(context.Background(), c, srv.URL+"/big.jpg"); err == nil ||
		!strings.Contains(err.Error(), "exceeds") {
		t.Fatalf("want size cap error, got %v", err)
	}
}

func TestFetchImageRefusesNonHTTPSRedirect(t *testing.T) {
	srv := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "http://insecure.example/cover.jpg", http.StatusFound)
	}))
	defer srv.Close()

	c := newCore(srv.Client(), "test-agent", time.Nanosecond)
	if _, _, err := fetchImage(context.Background(), c, srv.URL+"/redir"); err == nil ||
		!strings.Contains(err.Error(), "non-https") {
		t.Fatalf("want non-https redirect error, got %v", err)
	}
}

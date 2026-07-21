// Package providers implements the network clients behind WaxDeck's
// matching and enrichment ports: MusicBrainz and AcoustID supply release
// candidates for the match engine, and Deezer, iTunes, fanart.tv, and
// Audnexus supply covers and audiobook metadata through WaxBin's enrich
// port. Every client shares one HTTP core that enforces per-host request
// pacing, an in-memory response cache, a required User-Agent, and typed
// throttle errors, so no remote service is ever hammered or fetched
// without attribution.
package providers

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"mime"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

// ErrThrottled reports a 429 or 503 from a remote service. Callers treat
// it as transient and retry on a later pass rather than failing the run.
var ErrThrottled = errors.New("throttled")

const (
	defaultUserAgent = "WaxDeck/1.0 (+https://github.com/colespringer/waxdeck)"
	defaultTimeout   = 15 * time.Second

	// maxCacheEntries bounds the in-memory response cache per client.
	maxCacheEntries = 4096
	// maxResponseBytes bounds an API response body read.
	maxResponseBytes = 16 << 20
	// maxImageBytes bounds an image download.
	maxImageBytes = 8 << 20
)

// core is the shared HTTP helper behind every client in the package. It
// paces requests per host with a minimum interval, caches 200 responses
// by URL (plus body hash for POSTs), and stamps the client's User-Agent
// on every request. Safe for concurrent use.
type core struct {
	httpClient  *http.Client
	userAgent   string
	minInterval time.Duration

	mu   sync.Mutex
	next map[string]time.Time

	cacheMu sync.Mutex
	cache   map[string]cacheEntry
}

type cacheEntry struct {
	body      []byte
	fetchedAt time.Time
}

// newCore builds a core around the injected client (a 15s-timeout default
// when nil), the required User-Agent, and the per-host minimum interval.
func newCore(client *http.Client, userAgent string, minInterval time.Duration) *core {
	if client == nil {
		client = &http.Client{Timeout: defaultTimeout}
	}
	return &core{
		httpClient:  client,
		userAgent:   userAgent,
		minInterval: minInterval,
		next:        make(map[string]time.Time),
		cache:       make(map[string]cacheEntry),
	}
}

// get performs a paced, cached GET. It returns the body and status code;
// the caller decides how to treat non-200 statuses (except 429/503, which
// surface as ErrThrottled).
func (c *core) get(ctx context.Context, rawURL string, ttl time.Duration) ([]byte, int, error) {
	return c.do(ctx, http.MethodGet, rawURL, "", nil, ttl)
}

// postForm performs a paced, cached form-encoded POST. The cache key
// includes a hash of the encoded body.
func (c *core) postForm(ctx context.Context, rawURL string, form url.Values, ttl time.Duration) ([]byte, int, error) {
	return c.do(ctx, http.MethodPost, rawURL, "application/x-www-form-urlencoded", []byte(form.Encode()), ttl)
}

func (c *core) do(ctx context.Context, method, rawURL, contentType string, reqBody []byte, ttl time.Duration) ([]byte, int, error) {
	key := rawURL
	if len(reqBody) > 0 {
		sum := sha256.Sum256(reqBody)
		key = rawURL + "#" + hex.EncodeToString(sum[:])
	}
	if body, ok := c.cached(key, ttl); ok {
		return body, http.StatusOK, nil
	}
	u, err := url.Parse(rawURL)
	if err != nil {
		return nil, 0, fmt.Errorf("providers: parse url %q: %w", rawURL, err)
	}
	if err := c.pace(ctx, u.Host); err != nil {
		return nil, 0, fmt.Errorf("providers: wait for %s: %w", u.Host, err)
	}
	var rd io.Reader
	if reqBody != nil {
		rd = bytes.NewReader(reqBody)
	}
	req, err := http.NewRequestWithContext(ctx, method, rawURL, rd)
	if err != nil {
		return nil, 0, fmt.Errorf("providers: build request for %s: %w", rawURL, err)
	}
	req.Header.Set("User-Agent", c.userAgent)
	if contentType != "" {
		req.Header.Set("Content-Type", contentType)
	}
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return nil, 0, fmt.Errorf("providers: request %s: %w", rawURL, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode == http.StatusServiceUnavailable {
		return nil, resp.StatusCode, fmt.Errorf("providers: %s: %w", u.Host, ErrThrottled)
	}
	body, err := readCapped(resp.Body, maxResponseBytes)
	if err != nil {
		return nil, resp.StatusCode, fmt.Errorf("providers: read response from %s: %w", u.Host, err)
	}
	if resp.StatusCode == http.StatusOK && ttl > 0 {
		c.store(key, body)
	}
	return body, resp.StatusCode, nil
}

// pace blocks until the host's next-allowed time, honoring context
// cancellation while waiting, then reserves the following slot.
func (c *core) pace(ctx context.Context, host string) error {
	for {
		c.mu.Lock()
		now := time.Now()
		next, ok := c.next[host]
		if !ok || !now.Before(next) {
			c.next[host] = now.Add(c.minInterval)
			c.mu.Unlock()
			return nil
		}
		delay := next.Sub(now)
		c.mu.Unlock()
		timer := time.NewTimer(delay)
		select {
		case <-ctx.Done():
			timer.Stop()
			return ctx.Err()
		case <-timer.C:
		}
	}
}

func (c *core) cached(key string, ttl time.Duration) ([]byte, bool) {
	if ttl <= 0 {
		return nil, false
	}
	c.cacheMu.Lock()
	defer c.cacheMu.Unlock()
	e, ok := c.cache[key]
	if !ok || time.Since(e.fetchedAt) >= ttl {
		return nil, false
	}
	return e.body, true
}

// store inserts a 200 response body, evicting the oldest entry when the
// cache is full (a linear scan is fine at this size).
func (c *core) store(key string, body []byte) {
	c.cacheMu.Lock()
	defer c.cacheMu.Unlock()
	if _, exists := c.cache[key]; !exists && len(c.cache) >= maxCacheEntries {
		var oldestKey string
		var oldestAt time.Time
		for k, e := range c.cache {
			if oldestKey == "" || e.fetchedAt.Before(oldestAt) {
				oldestKey, oldestAt = k, e.fetchedAt
			}
		}
		delete(c.cache, oldestKey)
	}
	c.cache[key] = cacheEntry{body: body, fetchedAt: time.Now()}
}

// fetchImage downloads cover art. Unlike the API endpoints, image URLs
// are dynamic hosts chosen by the remote service, so the fetch requires
// https, refuses redirects to non-https, caps the body at maxImageBytes,
// and refuses non-image content types. It returns the bytes and the media
// type from the Content-Type header.
func fetchImage(ctx context.Context, c *core, rawURL string) ([]byte, string, error) {
	u, err := url.Parse(rawURL)
	if err != nil {
		return nil, "", fmt.Errorf("providers: parse image url %q: %w", rawURL, err)
	}
	if u.Scheme != "https" {
		return nil, "", fmt.Errorf("providers: image url %q: https required", rawURL)
	}
	if err := c.pace(ctx, u.Host); err != nil {
		return nil, "", fmt.Errorf("providers: wait for %s: %w", u.Host, err)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, "", fmt.Errorf("providers: build image request for %s: %w", rawURL, err)
	}
	req.Header.Set("User-Agent", c.userAgent)
	// A copy of the injected client carries the redirect policy without
	// mutating shared state; the Transport is still shared.
	client := *c.httpClient
	client.CheckRedirect = func(req *http.Request, via []*http.Request) error {
		if req.URL.Scheme != "https" {
			return errors.New("redirect to non-https url")
		}
		if len(via) >= 5 {
			return errors.New("too many redirects")
		}
		return nil
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, "", fmt.Errorf("providers: fetch image %s: %w", rawURL, err)
	}
	defer resp.Body.Close()
	if resp.StatusCode == http.StatusTooManyRequests || resp.StatusCode == http.StatusServiceUnavailable {
		return nil, "", fmt.Errorf("providers: %s: %w", u.Host, ErrThrottled)
	}
	if resp.StatusCode != http.StatusOK {
		return nil, "", fmt.Errorf("providers: fetch image %s: status %d", rawURL, resp.StatusCode)
	}
	mediaType := strings.TrimSpace(resp.Header.Get("Content-Type"))
	if mt, _, err := mime.ParseMediaType(mediaType); err == nil {
		mediaType = mt
	}
	mediaType = strings.ToLower(mediaType)
	if !strings.HasPrefix(mediaType, "image/") {
		return nil, "", fmt.Errorf("providers: fetch image %s: content type %q is not an image", rawURL, mediaType)
	}
	body, err := readCapped(resp.Body, maxImageBytes)
	if err != nil {
		return nil, "", fmt.Errorf("providers: read image %s: %w", rawURL, err)
	}
	return body, mediaType, nil
}

// readCapped reads at most limit bytes and errors when the body is
// larger, so a misbehaving remote cannot exhaust memory.
func readCapped(r io.Reader, limit int64) ([]byte, error) {
	b, err := io.ReadAll(io.LimitReader(r, limit+1))
	if err != nil {
		return nil, err
	}
	if int64(len(b)) > limit {
		return nil, fmt.Errorf("body exceeds %d bytes", limit)
	}
	return b, nil
}

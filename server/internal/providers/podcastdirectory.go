package providers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// PodcastDirectoryConfig configures the podcast name search. Zero
// values take the documented defaults.
type PodcastDirectoryConfig struct {
	// BaseURL defaults to "https://itunes.apple.com" (key-free API).
	BaseURL string
	// UserAgent defaults to the WaxDeck identifying string.
	UserAgent string
	// HTTPClient defaults to a 15s-timeout client.
	HTTPClient *http.Client
	// MinInterval defaults to 500ms.
	MinInterval time.Duration
	// CacheTTL defaults to directoryCacheTTL.
	CacheTTL time.Duration
}

const (
	// directoryCacheTTL is deliberately far shorter than the enrichment
	// clients' day. Those answer "what is the cover for this known
	// release", which does not change; this answers a person typing into
	// a search box, and a show published this morning being unfindable
	// until tomorrow is the search being wrong. Long enough that the
	// keystrokes of one session share an answer, short enough that a
	// second visit is fresh.
	directoryCacheTTL = 10 * time.Minute
	// directoryCacheEntries bounds the response cache. Small, because
	// the keys are search terms rather than catalog entities: an
	// authenticated caller can mint a distinct key per request, so the
	// enrichment default of 4096 responses is a memory budget somebody
	// else gets to spend. A few hundred covers the repeat and
	// backspace traffic a real search produces.
	directoryCacheEntries = 256
	// directoryMaxQuery caps the term that reaches the upstream and the
	// cache key. Nobody searches for a show with two thousand
	// characters; the cap is what keeps a key from being one.
	directoryMaxQuery = 200
)

// PodcastDirectoryEntry is one directory match. feedURL is the point of
// the whole lookup: it is what a subscribe request takes, so a match
// without one is not a result.
type PodcastDirectoryEntry struct {
	Name         string
	FeedURL      string
	Author       string
	ArtworkURL   string
	Genre        string
	EpisodeCount int
}

// PodcastDirectory searches the iTunes podcast index by name.
//
// It sits beside the enrichment chain rather than inside it: a name
// search answers a person typing into a search box, where enrich.Provider
// answers "identify this known release", and the two share nothing but
// the transport. What they do share is the transport, which is the
// reason this is here at all -- the core underneath already paces per
// host, caches 200s, bounds the read, and turns 429 and 503 into
// ErrThrottled, so the search needs no rate limiter or cache of its
// own. What it does not inherit is the enrichment clients' cache
// settings: see directoryCacheTTL and directoryCacheEntries for why a
// search's cache wants different numbers than a lookup's.
type PodcastDirectory struct {
	base string
	ttl  time.Duration
	core *core
}

// NewPodcastDirectory builds a directory client from cfg, applying
// defaults for zero fields.
func NewPodcastDirectory(cfg PodcastDirectoryConfig) *PodcastDirectory {
	base := cfg.BaseURL
	if base == "" {
		base = "https://itunes.apple.com"
	}
	ua := cfg.UserAgent
	if ua == "" {
		ua = defaultUserAgent
	}
	interval := cfg.MinInterval
	if interval == 0 {
		interval = defaultEnrichInterval
	}
	ttl := cfg.CacheTTL
	if ttl == 0 {
		ttl = directoryCacheTTL
	}
	return &PodcastDirectory{
		base: strings.TrimRight(base, "/"),
		ttl:  ttl,
		core: newBoundedCore(cfg.HTTPClient, ua, interval, directoryCacheEntries),
	}
}

// Search returns directory matches for a show name, best first in the
// directory's own ranking.
func (d *PodcastDirectory) Search(ctx context.Context, query string, limit int) ([]PodcastDirectoryEntry, error) {
	query = strings.TrimSpace(query)
	if query == "" {
		return nil, nil
	}
	if len(query) > directoryMaxQuery {
		query = strings.TrimSpace(query[:directoryMaxQuery])
	}
	if limit <= 0 {
		limit = 25
	}
	q := url.Values{}
	q.Set("term", query)
	q.Set("entity", "podcast")
	q.Set("media", "podcast")
	q.Set("limit", fmt.Sprint(limit))
	body, status, err := d.core.get(ctx, d.base+"/search?"+q.Encode(), d.ttl)
	if err != nil {
		return nil, err
	}
	if status != http.StatusOK {
		return nil, fmt.Errorf("providers: podcast directory search: status %d", status)
	}
	var parsed struct {
		Results []struct {
			CollectionName string `json:"collectionName"`
			TrackName      string `json:"trackName"`
			ArtistName     string `json:"artistName"`
			FeedURL        string `json:"feedUrl"`
			ArtworkURL600  string `json:"artworkUrl600"`
			ArtworkURL100  string `json:"artworkUrl100"`
			Genre          string `json:"primaryGenreName"`
			TrackCount     int    `json:"trackCount"`
		} `json:"results"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode podcast directory search: %w", err)
	}
	out := make([]PodcastDirectoryEntry, 0, len(parsed.Results))
	for _, hit := range parsed.Results {
		name := hit.CollectionName
		if name == "" {
			name = hit.TrackName
		}
		// A show with no feed URL cannot be subscribed to, and the
		// directory does return some: dropping it here is what keeps an
		// unsubscribable row off the search screen.
		if name == "" || hit.FeedURL == "" {
			continue
		}
		art := hit.ArtworkURL600
		if art == "" {
			art = hit.ArtworkURL100
		}
		out = append(out, PodcastDirectoryEntry{
			Name:         name,
			FeedURL:      hit.FeedURL,
			Author:       hit.ArtistName,
			ArtworkURL:   art,
			Genre:        hit.Genre,
			EpisodeCount: hit.TrackCount,
		})
	}
	return out, nil
}

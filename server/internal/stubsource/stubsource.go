// Package stubsource implements the acquisition source port over a
// sourceserv-style manifest URL, so test stacks exercise the whole
// acquisition and playlist-sync loop - enumerate, snapshot, fetch,
// review, reconcile - without a real platform on the wire. It is wired
// behind -source-stub-url and is never a production bridge: no auth,
// no pacing, no availability model beyond what the manifest says.
package stubsource

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"path"
	"strings"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"
	"github.com/colespringer/waxbin/waxerr"

	"github.com/colespringer/waxdeck/server/internal/sourcetags"
	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

// manifest mirrors sourceserv's playlist document.
type manifest struct {
	ID      string `json:"id"`
	Title   string `json:"title"`
	Entries []struct {
		ID    string `json:"id"`
		Title string `json:"title"`
	} `json:"entries"`
}

// Provider serves one stub source rooted at a base URL.
type Provider struct {
	base   string
	client *http.Client
}

var (
	_ source.Provider        = (*Provider)(nil)
	_ syncsource.Snapshotter = (*Provider)(nil)
)

// New builds a Provider over the sourceserv base URL.
func New(baseURL string) *Provider {
	return &Provider{
		base:   strings.TrimRight(baseURL, "/"),
		client: &http.Client{Timeout: 30 * time.Second},
	}
}

// ownsURL reports whether a URL belongs to this stub's host - exact
// scheme and host, not a string prefix, which "4422.evil.example"
// would satisfy.
func (p *Provider) ownsURL(rawURL string) bool {
	base, err := url.Parse(p.base)
	if err != nil {
		return false
	}
	u, err := url.Parse(rawURL)
	if err != nil {
		return false
	}
	return u.Scheme == base.Scheme && u.Host == base.Host
}

// SourceType reports youtube so the stub slots into the same dispatch
// the real bridge uses.
func (p *Provider) SourceType() model.SourceType { return model.SourceYouTube }

func (p *Provider) audioURL(id string) string { return p.base + "/audio/" + id }

func (p *Provider) readManifest(ctx context.Context, rawURL string) (*manifest, error) {
	if !p.ownsURL(rawURL) {
		return nil, errors.New("stubsource: not this source's URL")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return nil, err
	}
	resp, err := p.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("stubsource: manifest answered %d", resp.StatusCode)
	}
	var m manifest
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&m); err != nil {
		return nil, fmt.Errorf("stubsource: manifest does not parse: %w", err)
	}
	return &m, nil
}

// Resolve probes the playlist identity.
func (p *Provider) Resolve(ctx context.Context, req source.Request) (*source.Resolved, error) {
	m, err := p.readManifest(ctx, req.URL)
	if err != nil {
		return nil, waxerr.Wrap(waxerr.CodeIO, "stubsource.Resolve", err)
	}
	return &source.Resolved{
		IdentityKey: "stub:" + m.ID,
		SourceID:    m.ID,
		SourceType:  model.SourceYouTube,
		Title:       m.Title,
	}, nil
}

// Enumerate lists the manifest as a feed.
func (p *Provider) Enumerate(ctx context.Context, req source.Request) (*source.Enumeration, error) {
	m, err := p.readManifest(ctx, req.URL)
	if err != nil {
		return nil, waxerr.Wrap(waxerr.CodeIO, "stubsource.Enumerate", err)
	}
	feed := &model.Feed{Title: m.Title}
	for _, e := range m.Entries {
		feed.Episodes = append(feed.Episodes, model.FeedEpisode{
			GUID:          e.ID,
			Title:         e.Title,
			EnclosureURL:  p.audioURL(e.ID),
			EnclosureType: "audio/mpeg",
		})
	}
	return &source.Enumeration{Feed: feed, IdentityKey: "stub:" + m.ID, SourceID: m.ID}, nil
}

// Fetch streams one entry's audio through the source tags pass.
func (p *Provider) Fetch(ctx context.Context, freq source.FetchRequest, w io.Writer) (*source.FetchResult, error) {
	return p.FetchWith(ctx, freq, w, syncsource.FetchOptions{})
}

// FetchWith lands the entry's audio in a temp file, runs the providers' source
// tags pass with the file's own ARTIST and TITLE standing for the uploader and
// the video title (the stub has no description), then streams it to w. The
// format is ignored: the stub cannot transcode. The provenance timestamp
// makes each fetch's bytes differ, as the real bridge's do.
func (p *Provider) FetchWith(ctx context.Context, freq source.FetchRequest, w io.Writer, opts syncsource.FetchOptions) (*source.FetchResult, error) {
	if !p.ownsURL(freq.URL) {
		return nil, errors.New("stubsource: not this source's URL")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, freq.URL, nil)
	if err != nil {
		return nil, err
	}
	resp, err := p.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("stubsource: audio answered %d", resp.StatusCode)
	}
	ctype := resp.Header.Get("Content-Type")
	ext := ""
	if ctype == "audio/mpeg" {
		ext = ".mp3"
	}
	n, err := sourcetags.Restamp(ctx, "", ext, resp.Body, w, sourcetags.Source{
		URL: freq.URL, ID: path.Base(freq.URL), Music: opts.Music,
	})
	if err != nil {
		return nil, err
	}
	return &source.FetchResult{Bytes: n, ContentType: ctype}, nil
}

// PlaylistSnapshot lists the manifest in playlist order. Every entry
// the manifest carries is deliverable, so availability is known.
func (p *Provider) PlaylistSnapshot(ctx context.Context, url string, opts syncsource.SnapshotOptions) (*syncsource.PlaylistSnapshot, error) {
	m, err := p.readManifest(ctx, url)
	if err != nil {
		return nil, err
	}
	snap := &syncsource.PlaylistSnapshot{
		ID:          m.ID,
		IdentityKey: "stub:" + m.ID,
		Title:       m.Title,
	}
	for i, e := range m.Entries {
		if opts.MaxEntries > 0 && i >= opts.MaxEntries {
			snap.Truncated = true
			break
		}
		snap.Entries = append(snap.Entries, syncsource.PlaylistSnapshotEntry{
			ID:                e.ID,
			Index:             i,
			URL:               p.audioURL(e.ID),
			Title:             e.Title,
			AvailabilityKnown: true,
		})
	}
	return snap, nil
}

package providers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxbin/enrich"
)

// OpenLibraryConfig configures the Open Library provider. Zero values
// take the documented defaults.
type OpenLibraryConfig struct {
	// BaseURL defaults to "https://openlibrary.org" (key-free API).
	BaseURL string
	// UserAgent defaults to the WaxDeck identifying string.
	UserAgent string
	// HTTPClient defaults to a 15s-timeout client.
	HTTPClient *http.Client
	// MinInterval defaults to 500ms.
	MinInterval time.Duration
	// CacheTTL defaults to 24h.
	CacheTTL time.Duration
}

// OpenLibrary supplies book metadata, key-free: an edition read when
// the request carries an ISBN, a name-gated title and author search
// otherwise.
type OpenLibrary struct {
	base string
	ttl  time.Duration
	core *core
}

// NewOpenLibrary builds a provider from cfg, applying defaults for zero
// fields.
func NewOpenLibrary(cfg OpenLibraryConfig) *OpenLibrary {
	base := cfg.BaseURL
	if base == "" {
		base = "https://openlibrary.org"
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
		ttl = defaultEnrichTTL
	}
	return &OpenLibrary{
		base: strings.TrimRight(base, "/"),
		ttl:  ttl,
		core: newCore(cfg.HTTPClient, ua, interval),
	}
}

// Name is the stable provenance id.
func (o *OpenLibrary) Name() string { return "openlibrary" }

// Capabilities reports audiobook metadata.
func (o *OpenLibrary) Capabilities() enrich.Capability { return enrich.CapBookMeta }

// Enrich answers a book lookup. An ISBN reads the edition directly;
// without one, the search endpoint answers under a both-names gate.
func (o *OpenLibrary) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if req.Type != enrich.TargetBook {
		return nil, nil
	}
	if isbn := cleanISBN(req.ISBN); isbn != "" {
		return o.byISBN(ctx, isbn)
	}
	if req.Title == "" {
		return nil, nil
	}
	return o.byNames(ctx, req.Title, req.Artist)
}

// byISBN reads one edition.
func (o *OpenLibrary) byISBN(ctx context.Context, isbn string) (*enrich.Candidate, error) {
	body, status, err := o.core.get(ctx, o.base+"/isbn/"+url.PathEscape(isbn)+".json", o.ttl)
	if err != nil {
		return nil, err
	}
	switch status {
	case http.StatusOK:
	case http.StatusNotFound:
		return nil, nil
	default:
		return nil, fmt.Errorf("providers: open library edition: status %d", status)
	}
	var ed struct {
		Publishers  []string `json:"publishers"`
		PublishDate string   `json:"publish_date"`
	}
	if err := json.Unmarshal(body, &ed); err != nil {
		return nil, fmt.Errorf("providers: decode open library edition: %w", err)
	}
	fields := map[string]string{}
	var publisher string
	if len(ed.Publishers) > 0 && ed.Publishers[0] != "" {
		publisher = ed.Publishers[0]
		fields["publisher"] = publisher
	}
	if y := trailingYear(ed.PublishDate); y != "" {
		fields["year"] = y
	}
	if len(fields) == 0 {
		return nil, nil
	}
	return &enrich.Candidate{Confidence: 0.6, Publisher: publisher, Fields: fields}, nil
}

// byNames searches, gated on both names. The work-level hit offers its
// first-publish year and nothing more: its `isbn` array is the union of
// every edition, printing, and translation in no defined order, and an
// arbitrary member written into the item's durable ISBN field would key
// every later identifier lookup to a different edition.
func (o *OpenLibrary) byNames(ctx context.Context, title, author string) (*enrich.Candidate, error) {
	q := url.Values{}
	q.Set("title", title)
	if author != "" {
		q.Set("author", author)
	}
	q.Set("limit", "5")
	q.Set("fields", "title,author_name,first_publish_year")
	body, status, err := o.core.get(ctx, o.base+"/search.json?"+q.Encode(), o.ttl)
	if err != nil {
		return nil, err
	}
	if status != http.StatusOK {
		return nil, fmt.Errorf("providers: open library search: status %d", status)
	}
	var parsed struct {
		Docs []struct {
			Title            string   `json:"title"`
			AuthorName       []string `json:"author_name"`
			FirstPublishYear int      `json:"first_publish_year"`
		} `json:"docs"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode open library search: %w", err)
	}
	for _, doc := range parsed.Docs {
		if !nameMatch(doc.Title, title) {
			continue
		}
		if author != "" && !authorMatch(doc.AuthorName, author) {
			continue
		}
		if doc.FirstPublishYear <= 0 {
			continue
		}
		return &enrich.Candidate{
			Confidence: 0.5,
			Fields:     map[string]string{"year": strconv.Itoa(doc.FirstPublishYear)},
		}, nil
	}
	return nil, nil
}

// trailingYear finds the four-digit year in an Open Library publish
// date, which is written either way around ("Jun 17, 2014",
// "2014-06-17"); empty when neither end carries one.
func trailingYear(d string) string {
	d = strings.TrimSpace(d)
	if y := yearString(d); y != "" {
		return y
	}
	if len(d) < 4 {
		return ""
	}
	tail := d[len(d)-4:]
	if y, err := strconv.Atoi(tail); err != nil || y <= 0 {
		return ""
	}
	return tail
}

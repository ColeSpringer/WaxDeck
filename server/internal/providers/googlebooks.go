package providers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/colespringer/waxbin/enrich"
)

// GoogleBooksConfig configures the Google Books provider. Zero values
// take the documented defaults.
type GoogleBooksConfig struct {
	// BaseURL defaults to "https://www.googleapis.com".
	BaseURL string
	// APIKey is optional: the volumes endpoint answers without one, and
	// a key only raises the quota.
	APIKey string
	// UserAgent defaults to the WaxDeck identifying string.
	UserAgent string
	// HTTPClient defaults to a 15s-timeout client.
	HTTPClient *http.Client
	// MinInterval defaults to 500ms.
	MinInterval time.Duration
	// CacheTTL defaults to 24h.
	CacheTTL time.Duration
}

// GoogleBooks supplies book metadata from the volumes search, keyed on
// ISBN when the request carries one and on a name-gated title and
// author search otherwise.
type GoogleBooks struct {
	base   string
	apiKey string
	ttl    time.Duration
	core   *core
}

// NewGoogleBooks builds a provider from cfg, applying defaults for zero
// fields.
func NewGoogleBooks(cfg GoogleBooksConfig) *GoogleBooks {
	base := cfg.BaseURL
	if base == "" {
		base = "https://www.googleapis.com"
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
	return &GoogleBooks{
		base:   strings.TrimRight(base, "/"),
		apiKey: cfg.APIKey,
		ttl:    ttl,
		core:   newCore(cfg.HTTPClient, ua, interval),
	}
}

// Name is the stable provenance id.
func (g *GoogleBooks) Name() string { return "googlebooks" }

// Capabilities reports audiobook metadata.
func (g *GoogleBooks) Capabilities() enrich.Capability { return enrich.CapBookMeta }

// Enrich answers a book lookup: by ISBN when the request carries one
// (an identifier hit needs no second guessing), otherwise by title and
// author with both names matched before anything is believed.
func (g *GoogleBooks) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if req.Type != enrich.TargetBook {
		return nil, nil
	}
	isbn := cleanISBN(req.ISBN)
	var query string
	switch {
	case isbn != "":
		query = "isbn:" + isbn
	case req.Title != "":
		query = "intitle:" + quotePhrase(req.Title)
		if req.Artist != "" {
			query += " inauthor:" + quotePhrase(req.Artist)
		}
	default:
		return nil, nil
	}
	q := url.Values{}
	q.Set("q", query)
	q.Set("maxResults", "5")
	if g.apiKey != "" {
		q.Set("key", g.apiKey)
	}
	body, status, err := g.core.get(ctx, g.base+"/books/v1/volumes?"+q.Encode(), g.ttl)
	if err != nil {
		return nil, err
	}
	if status != http.StatusOK {
		return nil, fmt.Errorf("providers: google books volumes: status %d", status)
	}
	var parsed struct {
		Items []struct {
			VolumeInfo struct {
				Title               string         `json:"title"`
				Authors             []string       `json:"authors"`
				Publisher           string         `json:"publisher"`
				PublishedDate       string         `json:"publishedDate"`
				Description         string         `json:"description"`
				IndustryIdentifiers []gbIdentifier `json:"industryIdentifiers"`
			} `json:"volumeInfo"`
		} `json:"items"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode google books volumes: %w", err)
	}
	for _, item := range parsed.Items {
		v := item.VolumeInfo
		// An ISBN query names one edition, but the search can still
		// answer related volumes around it, so the hit must carry the
		// requested identifier before anything is believed; a text query
		// must earn its hit with both names instead.
		if isbn != "" {
			if !volumeCarriesISBN(v.IndustryIdentifiers, isbn) {
				continue
			}
		} else {
			if !nameMatch(v.Title, req.Title) {
				continue
			}
			if req.Artist != "" && !authorMatch(v.Authors, req.Artist) {
				continue
			}
		}
		cand := &enrich.Candidate{
			Confidence: 0.6,
			Publisher:  v.Publisher,
		}
		if isbn == "" {
			for _, id := range v.IndustryIdentifiers {
				if id.Type == "ISBN_13" && id.Identifier != "" {
					cand.ISBN = id.Identifier
					break
				}
				if id.Type == "ISBN_10" && cand.ISBN == "" {
					cand.ISBN = id.Identifier
				}
			}
		}
		fields := map[string]string{}
		if v.Publisher != "" {
			fields["publisher"] = v.Publisher
		}
		if y := yearString(v.PublishedDate); y != "" {
			fields["year"] = y
		}
		if desc := stripHTML(v.Description); desc != "" {
			fields["description"] = desc
		}
		if len(fields) > 0 {
			cand.Fields = fields
		}
		if cand.ISBN == "" && cand.Publisher == "" && cand.Fields == nil {
			continue
		}
		return cand, nil
	}
	return nil, nil
}

// authorMatch reports whether any listed author is the requested one,
// name-folded the way every other provider matches.
func authorMatch(authors []string, want string) bool {
	for _, a := range authors {
		if nameMatch(a, want) {
			return true
		}
	}
	return false
}

// cleanISBN strips the hyphens and spaces an ISBN is routinely typed
// with, the same fold the editor's validator applies before checking
// the digits.
func cleanISBN(s string) string {
	return strings.Map(func(r rune) rune {
		if r == '-' || r == ' ' {
			return -1
		}
		return r
	}, s)
}

// gbIdentifier is one industry identifier on a volume.
type gbIdentifier struct {
	Type       string `json:"type"`
	Identifier string `json:"identifier"`
}

// volumeCarriesISBN reports whether a volume's identifiers include the
// requested (already cleaned) ISBN.
func volumeCarriesISBN(ids []gbIdentifier, isbn string) bool {
	for _, id := range ids {
		if cleanISBN(id.Identifier) == isbn {
			return true
		}
	}
	return false
}

// quotePhrase quotes a search phrase so the volumes query treats it as
// one term.
func quotePhrase(s string) string { return `"` + strings.ReplaceAll(s, `"`, "") + `"` }

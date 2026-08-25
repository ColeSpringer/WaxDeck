package providers

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/colespringer/waxbin/enrich"
)

// HardcoverConfig configures the Hardcover audiobook provider. Zero
// values take the documented defaults.
type HardcoverConfig struct {
	// BaseURL defaults to "https://api.hardcover.app/v1/graphql".
	BaseURL string
	// Token is the Hardcover API token, required for use; when empty,
	// Enrich always returns a clean miss without a network call.
	Token string
	// UserAgent defaults to the WaxDeck identifying string.
	UserAgent string
	// HTTPClient defaults to a 15s-timeout client.
	HTTPClient *http.Client
	// MinInterval defaults to 1100ms (Hardcover allows 60 requests a
	// minute per token).
	MinInterval time.Duration
	// CacheTTL defaults to 24h.
	CacheTTL time.Duration
}

// Hardcover is the ASIN-to-ISBN bridge: it resolves the Audible edition
// an audiobook's ASIN names and answers the identifiers and publisher
// Hardcover holds for it, which is what unlocks the ISBN-keyed
// providers downstream.
type Hardcover struct {
	base string
	ttl  time.Duration
	core *core
}

// NewHardcover builds a provider from cfg, applying defaults for zero
// fields. The token rides as a bearer Authorization header.
func NewHardcover(cfg HardcoverConfig) *Hardcover {
	base := cfg.BaseURL
	if base == "" {
		base = "https://api.hardcover.app/v1/graphql"
	}
	ua := cfg.UserAgent
	if ua == "" {
		ua = defaultUserAgent
	}
	interval := cfg.MinInterval
	if interval == 0 {
		interval = 1100 * time.Millisecond
	}
	ttl := cfg.CacheTTL
	if ttl == 0 {
		ttl = defaultEnrichTTL
	}
	h := &Hardcover{
		base: strings.TrimRight(base, "/"),
		ttl:  ttl,
		core: newCore(cfg.HTTPClient, ua, interval),
	}
	if cfg.Token != "" {
		h.core.authorization = "Bearer " + cfg.Token
	}
	return h
}

// Name is the stable provenance id.
func (h *Hardcover) Name() string { return "hardcover" }

// Capabilities reports audiobook metadata.
func (h *Hardcover) Capabilities() enrich.Capability { return enrich.CapBookMeta }

// hardcoverQuery is the one GraphQL document this provider sends: the
// edition matching an ASIN, with the identifiers and publisher.
const hardcoverQuery = `query ($asin: String!) {
  editions(where: {asin: {_eq: $asin}}, limit: 1) {
    isbn_13
    isbn_10
    release_date
    publisher { name }
  }
}`

// Enrich answers a book lookup by ASIN. Requests without an ASIN (or a
// token) are clean misses.
func (h *Hardcover) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if h.core.authorization == "" {
		return nil, nil
	}
	if req.Type != enrich.TargetBook || req.ASIN == "" {
		return nil, nil
	}
	payload, err := json.Marshal(map[string]any{
		"query":     hardcoverQuery,
		"variables": map[string]string{"asin": req.ASIN},
	})
	if err != nil {
		return nil, fmt.Errorf("providers: encode hardcover query: %w", err)
	}
	body, status, err := h.core.postJSON(ctx, h.base, payload, h.ttl)
	if err != nil {
		return nil, err
	}
	if status != http.StatusOK {
		return nil, fmt.Errorf("providers: hardcover editions: status %d", status)
	}
	var parsed struct {
		Data struct {
			Editions []struct {
				ISBN13      string `json:"isbn_13"`
				ISBN10      string `json:"isbn_10"`
				ReleaseDate string `json:"release_date"`
				Publisher   struct {
					Name string `json:"name"`
				} `json:"publisher"`
			} `json:"editions"`
		} `json:"data"`
		Errors []struct {
			Message string `json:"message"`
		} `json:"errors"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode hardcover editions: %w", err)
	}
	// GraphQL reports failure in-band with a 200; surfacing it keeps a
	// revoked token from reading as "Hardcover knows no audiobooks".
	if len(parsed.Errors) > 0 {
		return nil, fmt.Errorf("providers: hardcover editions: %s", parsed.Errors[0].Message)
	}
	if len(parsed.Data.Editions) == 0 {
		return nil, nil
	}
	ed := parsed.Data.Editions[0]
	cand := &enrich.Candidate{
		Confidence: 0.8,
		Publisher:  ed.Publisher.Name,
	}
	if ed.ISBN13 != "" {
		cand.ISBN = ed.ISBN13
	} else if ed.ISBN10 != "" {
		cand.ISBN = ed.ISBN10
	}
	fields := map[string]string{}
	if ed.Publisher.Name != "" {
		fields["publisher"] = ed.Publisher.Name
	}
	if y := yearString(ed.ReleaseDate); y != "" {
		fields["year"] = y
	}
	if len(fields) > 0 {
		cand.Fields = fields
	}
	if cand.ISBN == "" && cand.Publisher == "" && cand.Fields == nil {
		return nil, nil
	}
	return cand, nil
}

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

	"github.com/colespringer/waxdeck/server/internal/match"
)

// AcoustIDConfig configures the AcoustID client. Zero values take the
// documented defaults.
type AcoustIDConfig struct {
	// BaseURL defaults to "https://api.acoustid.org/v2".
	BaseURL string
	// APIKey is required for use; when empty, lookups return (nil, nil)
	// without a network call.
	APIKey string
	// UserAgent defaults to the WaxDeck identifying string.
	UserAgent string
	// HTTPClient defaults to a 15s-timeout client.
	HTTPClient *http.Client
	// MinInterval defaults to 350ms (etiquette: three requests per second).
	MinInterval time.Duration
	// CacheTTL defaults to 30 days (fingerprint results are stable).
	CacheTTL time.Duration
}

// AcoustID resolves Chromaprint fingerprints to recordings and release
// groups through the AcoustID web service.
type AcoustID struct {
	base   string
	apiKey string
	ttl    time.Duration
	core   *core
}

// NewAcoustID builds a client from cfg, applying defaults for zero
// fields.
func NewAcoustID(cfg AcoustIDConfig) *AcoustID {
	base := cfg.BaseURL
	if base == "" {
		base = "https://api.acoustid.org/v2"
	}
	ua := cfg.UserAgent
	if ua == "" {
		ua = defaultUserAgent
	}
	interval := cfg.MinInterval
	if interval == 0 {
		interval = 350 * time.Millisecond
	}
	ttl := cfg.CacheTTL
	if ttl == 0 {
		ttl = 30 * 24 * time.Hour
	}
	return &AcoustID{
		base:   strings.TrimRight(base, "/"),
		apiKey: cfg.APIKey,
		ttl:    ttl,
		core:   newCore(cfg.HTTPClient, ua, interval),
	}
}

// LookupFingerprint resolves one fingerprint. It yields one hit per
// (result, recording) pair; an empty API key short-circuits to a clean
// miss so an unconfigured deployment degrades to text matching.
func (a *AcoustID) LookupFingerprint(ctx context.Context, fp match.Fingerprint) ([]match.FingerprintHit, error) {
	if a.apiKey == "" {
		return nil, nil
	}
	form := url.Values{}
	form.Set("client", a.apiKey)
	form.Set("duration", strconv.Itoa(fp.DurationSec))
	form.Set("fingerprint", fp.Value)
	form.Set("meta", "recordingids releasegroupids")
	body, status, err := a.core.postForm(ctx, a.base+"/lookup", form, a.ttl)
	if err != nil {
		return nil, err
	}
	if status != http.StatusOK {
		return nil, fmt.Errorf("providers: acoustid lookup: status %d", status)
	}
	var parsed struct {
		Status string `json:"status"`
		Error  *struct {
			Message string `json:"message"`
		} `json:"error"`
		Results []struct {
			Score      float64 `json:"score"`
			Recordings []struct {
				ID            string `json:"id"`
				ReleaseGroups []struct {
					ID string `json:"id"`
				} `json:"releasegroups"`
			} `json:"recordings"`
		} `json:"results"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode acoustid lookup: %w", err)
	}
	if parsed.Status != "ok" {
		msg := parsed.Status
		if parsed.Error != nil && parsed.Error.Message != "" {
			msg = parsed.Error.Message
		}
		return nil, fmt.Errorf("providers: acoustid lookup: %s", msg)
	}
	var hits []match.FingerprintHit
	for _, res := range parsed.Results {
		for _, rec := range res.Recordings {
			hit := match.FingerprintHit{
				RecordingMBID: rec.ID,
				Score:         res.Score,
			}
			for _, rg := range rec.ReleaseGroups {
				hit.ReleaseGroupMBIDs = append(hit.ReleaseGroupMBIDs, rg.ID)
			}
			hits = append(hits, hit)
		}
	}
	return hits, nil
}

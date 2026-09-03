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
	"github.com/colespringer/waxbin/model"
)

// FanartTVConfig configures the fanart.tv cover provider. Zero values
// take the documented defaults.
type FanartTVConfig struct {
	// BaseURL defaults to "https://webservice.fanart.tv".
	BaseURL string
	// APIKey is required for use; when empty, Enrich always returns a
	// clean miss without a network call.
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

// FanartTV supplies release-group and artist art keyed on MusicBrainz
// ids. It is the one provider WaxDeck injects that serves art by role
// natively - cdart for the disc slot, a scenic background beside an
// artist thumb - so it answers the auxiliary and artist capabilities
// alongside the front cover.
type FanartTV struct {
	base   string
	apiKey string
	ttl    time.Duration
	core   *core
}

// NewFanartTV builds a provider from cfg, applying defaults for zero
// fields.
func NewFanartTV(cfg FanartTVConfig) *FanartTV {
	base := cfg.BaseURL
	if base == "" {
		base = "https://webservice.fanart.tv"
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
	return &FanartTV{
		base:   strings.TrimRight(base, "/"),
		apiKey: cfg.APIKey,
		ttl:    ttl,
		core:   newCore(cfg.HTTPClient, ua, interval),
	}
}

// Name is the stable provenance id.
func (f *FanartTV) Name() string { return "fanarttv" }

// Capabilities reports the front cover, the auxiliary release-group
// roles, and artist art. All three come off the same two endpoints, so
// advertising them costs no extra request - only the image downloads a
// pass actually asks for.
func (f *FanartTV) Capabilities() enrich.Capability {
	return enrich.CapCover | enrich.CapAuxArt | enrich.CapArtistArt
}

// Enrich answers a release-group or artist art lookup by MusicBrainz
// id; requests without an MBID (or without an API key) are clean
// misses. Only the roles the request asks for are downloaded: an
// auxiliary pass never fetches the front cover it would discard, and a
// front pass never fetches the disc art.
func (f *FanartTV) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if f.apiKey == "" || req.MBID == "" {
		return nil, nil
	}
	switch req.Type {
	case enrich.TargetReleaseGroup:
		if !f.wantsAny(req, releaseGroupArtRoles) {
			return nil, nil
		}
		return f.enrichReleaseGroup(ctx, req)
	case enrich.TargetArtist:
		if !f.wantsAny(req, artistArtRoles) {
			return nil, nil
		}
		return f.enrichArtist(ctx, req)
	default:
		return nil, nil
	}
}

// wantsAny reports whether the request asks for any role this target
// can answer, so a pass that would discard every role never reaches the
// network. The gate belongs here rather than in candidate(): the
// endpoint read happens first, and an ask that can keep nothing is one
// keyed request per entity per pass, paced at half a second a host.
//
// The engine's identity phase is what makes this matter. It asks about
// an artist through the same passes it asks about a release group -
// Want CapCover for the front, CapAuxArt for the rest - and never
// through the artist backfill's own CapArtistArt, so a provider that
// reads only CapArtistArt for an artist answers nothing while paying
// for the lookup.
func (f *FanartTV) wantsAny(req enrich.Request, roles []model.ArtRole) bool {
	for _, role := range roles {
		if req.Wants(capabilityForArtRole(req.Type, role)) {
			return true
		}
	}
	return false
}

// The roles each endpoint can fill, in the order candidate() gathers
// them. Front first, deliberately: the error rule below keeps the
// answer when a later role fails and returns the failure when nothing
// was gathered, and a map range would decide which of those happened by
// iteration order.
var (
	releaseGroupArtRoles = []model.ArtRole{model.ArtRoleFront, model.ArtRoleDisc}
	artistArtRoles       = []model.ArtRole{model.ArtRoleFront, model.ArtRoleBackground}
)

// enrichReleaseGroup serves the album endpoint: albumcover as the
// front, cdart as the disc slot. fanart.tv has no back or booklet
// asset for an album, so those roles stay empty here.
func (f *FanartTV) enrichReleaseGroup(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	body, ok, err := f.fetch(ctx, "/v3/music/albums/"+url.PathEscape(req.MBID), "albums")
	if err != nil || !ok {
		return nil, err
	}
	var parsed struct {
		Albums map[string]struct {
			AlbumCover []fanartImage `json:"albumcover"`
			CDArt      []fanartImage `json:"cdart"`
		} `json:"albums"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode fanarttv albums: %w", err)
	}
	album, ok := parsed.Albums[req.MBID]
	if !ok {
		return nil, nil
	}
	return f.candidate(ctx, req, releaseGroupArtRoles, map[model.ArtRole][]fanartImage{
		model.ArtRoleFront: album.AlbumCover,
		model.ArtRoleDisc:  album.CDArt,
	})
}

// enrichArtist serves the artist endpoint: artistthumb as the portrait
// and artistbackground as the scenic one. Upstream's art model gives an
// artist no separate portrait role, so the thumb is the front and the
// scenic image lands under background.
func (f *FanartTV) enrichArtist(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	body, ok, err := f.fetch(ctx, "/v3/music/"+url.PathEscape(req.MBID), "artist")
	if err != nil || !ok {
		return nil, err
	}
	var parsed struct {
		ArtistThumb      []fanartImage `json:"artistthumb"`
		ArtistBackground []fanartImage `json:"artistbackground"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return nil, fmt.Errorf("providers: decode fanarttv artist: %w", err)
	}
	return f.candidate(ctx, req, artistArtRoles, map[model.ArtRole][]fanartImage{
		model.ArtRoleFront:      parsed.ArtistThumb,
		model.ArtRoleBackground: parsed.ArtistBackground,
	})
}

// fanartImage is one asset in any of fanart.tv's per-type arrays; only
// the URL is read.
type fanartImage struct {
	URL string `json:"url"`
}

// fetch runs one keyed GET, reporting ok false for the 404 that means
// "no assets for this id" so a caller can answer a clean miss.
func (f *FanartTV) fetch(ctx context.Context, path, what string) ([]byte, bool, error) {
	q := url.Values{}
	q.Set("api_key", f.apiKey)
	body, status, err := f.core.get(ctx, f.base+path+"?"+q.Encode(), f.ttl)
	if err != nil {
		return nil, false, err
	}
	switch status {
	case http.StatusOK:
		return body, true, nil
	case http.StatusNotFound:
		return nil, false, nil
	default:
		return nil, false, fmt.Errorf("providers: fanarttv %s: status %d", what, status)
	}
}

// candidate downloads the first asset of each role the request asks
// for and assembles the candidate. Roles are downloaded independently,
// so one unreachable image costs its own slot rather than the answer.
//
// order is walked rather than the map, front first: the error rule
// below - keep what was gathered, return the failure when nothing was -
// only means something when which role is tried first is fixed. Under a
// map range the same upstream state persisted two different outcomes at
// random, one of them a backfill marker over a portrait that never
// arrived.
func (f *FanartTV) candidate(ctx context.Context, req enrich.Request, order []model.ArtRole, byRole map[model.ArtRole][]fanartImage) (*enrich.Candidate, error) {
	cand := &enrich.Candidate{Confidence: 0.8}
	for _, role := range order {
		assets := byRole[role]
		if !req.Wants(capabilityForArtRole(req.Type, role)) {
			continue
		}
		if len(assets) == 0 || assets[0].URL == "" {
			continue
		}
		data, mediaType, err := fetchImage(ctx, f.core, assets[0].URL)
		if err != nil {
			// A role whose image will not come costs that role, not
			// the ones already gathered. With nothing gathered the
			// error is the answer, so a broken host is not silently a
			// miss.
			if len(cand.Art) == 0 {
				return nil, err
			}
			continue
		}
		img := coverImage(data, mediaType, assets[0].URL)
		if img == nil {
			continue
		}
		if cand.Art == nil {
			cand.Art = map[model.ArtRole]*model.ArtImage{}
		}
		cand.Art[role] = img
		if role == model.ArtRoleFront && req.Type == enrich.TargetReleaseGroup {
			// Cover is the front alias, and a consumer written before
			// the role map reads only that.
			cand.Cover = img
		}
	}
	if len(cand.Art) == 0 {
		return nil, nil
	}
	return cand, nil
}

// capabilityForArtRole names the bits that gate one role on one target,
// as a mask: Wants is any-overlap, so a role answerable under either of
// two passes names both.
//
// A release group splits the front cover from its auxiliary slots,
// which is what keeps a cover pass from downloading disc art. An artist
// is asked about twice over: the artist backfill stamps CapArtistArt
// for every role, while the identity phase reuses the release-group
// passes and stamps CapCover for the front and CapAuxArt for the rest.
// Reading only CapArtistArt there is why this provider answered nothing
// on the path that actually runs on a stock install.
func capabilityForArtRole(target enrich.TargetType, role model.ArtRole) enrich.Capability {
	if role == model.ArtRoleFront {
		if target == enrich.TargetArtist {
			return enrich.CapCover | enrich.CapArtistArt
		}
		return enrich.CapCover
	}
	if target == enrich.TargetArtist {
		return enrich.CapAuxArt | enrich.CapArtistArt
	}
	return enrich.CapAuxArt
}

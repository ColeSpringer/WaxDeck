package providers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"

	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
)

// ErrNoArtistImage reports that every configured rung answered and none
// holds a portrait for this artist. Callers treat it as a durable miss
// worth remembering; any other error is "could not ask" and worth
// retrying on a later pass.
var ErrNoArtistImage = errors.New("providers: no image for this artist")

// artistNameMatch compares two artist display names on the
// punctuation-folded form both sides of a cover match use: "AC/DC" and
// "AC - DC" are one artist, spacing and case aside. Folded-empty names
// (all punctuation) match nothing rather than everything.
func artistNameMatch(a, b string) bool {
	fa, fb := foldCoverName(a), foldCoverName(b)
	return fa != "" && fa == fb
}

// ArtistNamePlaceholder reports whether a display name is a compilation
// or unknown-artist stand-in rather than one artist. It gates every
// by-name artist lookup here: Deezer holds real pages under several of
// these, so an exact name match would put a stranger's portrait on
// every compilation in a library.
func ArtistNamePlaceholder(name string) bool {
	switch strings.ToLower(strings.Join(strings.Fields(name), " ")) {
	case "various artists", "various", "va", "unknown artist", "unknown",
		"soundtrack", "original soundtrack", "ost":
		return true
	}
	return false
}

// ArtistImage answers an artist portrait by name from the Deezer artist
// search, gated on an exact-ish name match: a by-name face applied
// catalog-wide is the risk, so a near miss is no answer at all.
func (d *Deezer) ArtistImage(ctx context.Context, name string) (TitleCoverResult, error) {
	if name == "" {
		return TitleCoverResult{}, ErrNoArtistImage
	}
	q := url.Values{}
	q.Set("q", name)
	body, status, err := d.core.get(ctx, d.base+"/search/artist?"+q.Encode(), d.ttl)
	if err != nil {
		return TitleCoverResult{}, err
	}
	if status != http.StatusOK {
		return TitleCoverResult{}, fmt.Errorf("providers: deezer artist search: status %d", status)
	}
	var parsed struct {
		Data []struct {
			Name      string `json:"name"`
			PictureXL string `json:"picture_xl"`
		} `json:"data"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return TitleCoverResult{}, fmt.Errorf("providers: decode deezer artist search: %w", err)
	}
	// An artist is routinely listed more than once, so one unusable
	// picture is not the end of the walk - the FrontCover rule, and the
	// same bookkeeping: the fetch failure only surfaces when no later
	// hit answered, so it stays a retriable failure rather than a
	// recorded miss.
	var reachErr error
	for _, hit := range parsed.Data {
		if hit.PictureXL == "" || !artistNameMatch(hit.Name, name) {
			continue
		}
		data, mediaType, err := fetchImage(ctx, d.core, hit.PictureXL)
		if err != nil {
			reachErr = err
			continue
		}
		return TitleCoverResult{
			Data: data, MIME: mediaType,
			Provider:  d.Name(),
			SourceURL: hit.PictureXL,
		}, nil
	}
	if reachErr != nil {
		return TitleCoverResult{}, reachErr
	}
	return TitleCoverResult{}, ErrNoArtistImage
}

// ArtistArtChain answers an artist portrait from the configured rungs:
// fanart.tv first when the artist has a MusicBrainz id (a hit cannot be
// the wrong artist), then Deezer by exact-ish name match. A nil rung is
// simply absent, so the chain always exists and degrades to a clean
// miss when nothing is configured.
//
// The mbid rung is here rather than only on the enrichment port because
// the sweep covers whatever the catalog's own artist pass does not, and
// on an install with no enrichment contact that is every artist,
// mbid-carrying ones included. Asking fanart.tv through its Enrich
// keeps one implementation of the lookup rather than a second one for
// this caller.
type ArtistArtChain struct {
	Fanart *FanartTV
	Deezer *Deezer
}

// ArtistImage walks the rungs. A rung's clean miss falls through; its
// reachability failure ends the walk, because the next rung answering
// "no" would be recorded as a durable miss the failed rung might have
// contradicted.
func (c ArtistArtChain) ArtistImage(ctx context.Context, name, mbid string) (TitleCoverResult, error) {
	if c.Fanart != nil && mbid != "" {
		res, err := c.Fanart.artistPortrait(ctx, mbid)
		if err == nil {
			return res, nil
		}
		if !errors.Is(err, ErrNoArtistImage) {
			return TitleCoverResult{}, err
		}
	}
	if c.Deezer != nil {
		res, err := c.Deezer.ArtistImage(ctx, name)
		if err == nil {
			return res, nil
		}
		if !errors.Is(err, ErrNoArtistImage) {
			return TitleCoverResult{}, err
		}
	}
	return TitleCoverResult{}, ErrNoArtistImage
}

// artistPortrait asks the provider's own port for an artist front and
// renders the answer in the chain's vocabulary. It goes through Enrich
// so the endpoint, the role mapping and the download policy have one
// implementation; what differs here is only the miss shape the sweep's
// memory keys on.
func (f *FanartTV) artistPortrait(ctx context.Context, mbid string) (TitleCoverResult, error) {
	cand, err := f.Enrich(ctx, enrich.Request{
		Type: enrich.TargetArtist, MBID: mbid, Want: enrich.CapArtistArt,
	})
	if err != nil {
		return TitleCoverResult{}, err
	}
	img := candidateArt(cand, model.ArtRoleFront)
	if img == nil {
		return TitleCoverResult{}, ErrNoArtistImage
	}
	return TitleCoverResult{
		Data: img.Data, MIME: img.Format,
		Provider:  f.Name(),
		SourceURL: img.SourceURL,
	}, nil
}

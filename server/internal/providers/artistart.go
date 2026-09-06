package providers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
)

// ErrNoArtistImage reports that the provider answered and holds no
// portrait for this artist, which is a fact about the provider rather
// than a failure to reach it: an enrichment walk declines the target
// on this and reports the failure on anything else.
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
// catalog-wide is the risk, so a near miss is no answer at all. It is
// the lookup behind enrichArtist, which is what the catalog's artist
// walk dispatches.
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

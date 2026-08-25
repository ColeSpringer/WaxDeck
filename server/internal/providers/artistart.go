package providers

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
)

// ErrNoArtistImage reports that every configured rung answered and none
// holds a portrait for this artist. Callers treat it as a durable miss
// worth remembering; any other error is "could not ask" and worth
// retrying on a later pass.
var ErrNoArtistImage = errors.New("providers: no image for this artist")

// ArtistThumb answers an artist portrait by MusicBrainz artist id.
// Requests without an MBID (or without an API key) are clean misses:
// fanart.tv is keyed strictly on identity, which is what makes it the
// first rung - a hit cannot be the wrong artist.
func (f *FanartTV) ArtistThumb(ctx context.Context, mbid string) (TitleCoverResult, error) {
	if f.apiKey == "" || mbid == "" {
		return TitleCoverResult{}, ErrNoArtistImage
	}
	q := url.Values{}
	q.Set("api_key", f.apiKey)
	u := f.base + "/v3/music/" + url.PathEscape(mbid) + "?" + q.Encode()
	body, status, err := f.core.get(ctx, u, f.ttl)
	if err != nil {
		return TitleCoverResult{}, err
	}
	switch status {
	case http.StatusOK:
	case http.StatusNotFound:
		return TitleCoverResult{}, ErrNoArtistImage
	default:
		return TitleCoverResult{}, fmt.Errorf("providers: fanarttv artist: status %d", status)
	}
	var parsed struct {
		ArtistThumb []struct {
			URL string `json:"url"`
		} `json:"artistthumb"`
	}
	if err := json.Unmarshal(body, &parsed); err != nil {
		return TitleCoverResult{}, fmt.Errorf("providers: decode fanarttv artist: %w", err)
	}
	if len(parsed.ArtistThumb) == 0 || parsed.ArtistThumb[0].URL == "" {
		return TitleCoverResult{}, ErrNoArtistImage
	}
	data, mediaType, err := fetchImage(ctx, f.core, parsed.ArtistThumb[0].URL)
	if err != nil {
		return TitleCoverResult{}, err
	}
	return TitleCoverResult{
		Data: data, MIME: mediaType,
		Provider:  f.Name(),
		SourceURL: parsed.ArtistThumb[0].URL,
	}, nil
}

// artistNameMatch compares two artist display names on the
// punctuation-folded form both sides of a cover match use: "AC/DC" and
// "AC - DC" are one artist, spacing and case aside. Folded-empty names
// (all punctuation) match nothing rather than everything.
func artistNameMatch(a, b string) bool {
	fa, fb := foldCoverName(a), foldCoverName(b)
	return fa != "" && fa == fb
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
// fanart.tv first, keyed on the MBID, then Deezer by exact-ish name
// match. A nil rung is simply absent, so the chain always exists and
// degrades to a clean miss when nothing is configured.
type ArtistArtChain struct {
	Fanart *FanartTV
	Deezer *Deezer
}

// ArtistImage walks the rungs. A rung's clean miss falls through; its
// reachability failure ends the walk, because the next rung answering
// "no" would be recorded as a durable miss the failed rung might have
// contradicted.
func (c ArtistArtChain) ArtistImage(ctx context.Context, name, mbid string) (TitleCoverResult, error) {
	if c.Fanart != nil {
		res, err := c.Fanart.ArtistThumb(ctx, mbid)
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

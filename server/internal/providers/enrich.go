package providers

import (
	"strings"
	"time"
	"unicode"

	"github.com/colespringer/waxbin/art"
	"github.com/colespringer/waxbin/model"
)

// Defaults shared by the enrichment providers. The keyed and key-free
// services here tolerate more than the spine services, but stay gentle:
// the WaxBin service budgets 15s per enrichment pass, so a handful of
// paced calls fits comfortably.
const (
	defaultEnrichInterval = 500 * time.Millisecond
	defaultEnrichTTL      = 24 * time.Hour
)

// nameMatch compares two display names case-insensitively on a
// whitespace-collapsed form, so cosmetic spacing and casing differences
// still count as the same album or artist.
func nameMatch(a, b string) bool {
	return strings.EqualFold(collapseSpace(a), collapseSpace(b))
}

func collapseSpace(s string) string {
	return strings.Join(strings.Fields(s), " ")
}

// imageFormat maps an image media type to the model.ArtImage format
// vocabulary (jpeg|png|webp|gif); unknown subtypes pass through so the
// ingestor can decide.
func imageFormat(mediaType string) string {
	sub := strings.TrimPrefix(strings.ToLower(mediaType), "image/")
	switch sub {
	case "jpg", "jpeg", "pjpeg":
		return "jpeg"
	default:
		return sub
	}
}

// coverImage builds the cover a provider hands back to the enrichment
// pass, content-addressed and measured.
//
// The hash is not optional and not cosmetic. The catalog's art store is
// content-addressed, and its ingest (`attachEntityArtTxChanged`) drops
// an unhashed image on the floor and reports success, so a provider
// that returns bytes without one fetches a picture over the network
// that is then silently discarded - no error, no log, a run that
// reports itself clean. Every cover a provider returns goes through
// here so that cannot happen again.
//
// Dimensions come from a header probe rather than the transport's
// media type, because that is what the store records. An ISOBMFF cover
// (AVIF/HEIC) has no pure-Go decoder and so probes as a failure while
// still being a perfectly good picture: it keeps the sniffed format and
// unknown dimensions rather than being thrown away, matching what the
// catalog's own archive provider does with one. Empty bytes are no
// cover at all, which is a nil result rather than an image that cannot
// be stored.
func coverImage(data []byte, mediaType, sourceURL string) *model.ArtImage {
	if len(data) == 0 {
		return nil
	}
	img := &model.ArtImage{
		Data:      data,
		Hash:      art.Hash(data),
		Format:    imageFormat(mediaType),
		SourceURL: sourceURL,
	}
	if format, w, h, err := art.Probe(data); err == nil {
		img.Format, img.Width, img.Height = format, w, h
	} else if format, ok := art.SniffExotic(data); ok {
		img.Format = format
	}
	return img
}

// coverNameMatch compares an upstream display name against an already
// normalized query. Looser than nameMatch because the query side has had
// its punctuation collapsed already: "Hello, Goodbye" is "hello goodbye".
func coverNameMatch(upstream, normalized string) bool {
	return foldCoverName(upstream) == foldCoverName(normalized)
}

// foldCoverName lowercases and reduces everything that is not a letter
// or a digit to single spaces, so the two sides meet in one shape
// whichever of them carries the apostrophes and commas.
func foldCoverName(s string) string {
	var b strings.Builder
	space := false
	for _, r := range strings.ToLower(s) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			if space && b.Len() > 0 {
				b.WriteByte(' ')
			}
			space = false
			b.WriteRune(r)
			continue
		}
		space = true
	}
	return b.String()
}

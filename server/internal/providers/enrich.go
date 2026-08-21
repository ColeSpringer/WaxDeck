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
// The catalog's art store derives a missing hash, format or dimensions
// from the bytes now rather than losing the write, so this is no longer
// what stands between a fetched picture and a silent discard. What it
// still adds is the transport's answer: art.Describe reports an empty
// format for bytes that neither decode nor magic-sniff, and the media
// type is the only other thing that knows what they are.
//
// That answer reaches one of the two paths a cover takes. The catalog's
// whole-library pass carries this whole value to the store, so the media
// type's format lands with it. WaxDeck's own enrich-now button hands the
// facade raw bytes, because no setter takes a stamped *model.ArtImage
// (recorded in docs/upstream-requests.md), so the store re-derives from
// the bytes alone and refuses what it cannot recognize - a truncated
// image or an exotic container this build does not sniff is a CodeInvalid
// there and a stored cover on the library pass. Empty bytes are no cover
// at all, which is a nil result rather than an image that cannot be
// stored.
func coverImage(data []byte, mediaType, sourceURL string) *model.ArtImage {
	if len(data) == 0 {
		return nil
	}
	info := art.Describe(data)
	format := info.Format
	if format == "" {
		format = imageFormat(mediaType)
	}
	return &model.ArtImage{
		Data:        data,
		Hash:        info.Hash,
		Format:      format,
		Width:       info.Width,
		Height:      info.Height,
		Attribution: model.Attribution{SourceURL: sourceURL},
	}
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

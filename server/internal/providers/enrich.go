package providers

import (
	"context"
	"strings"
	"time"
	"unicode"

	"github.com/colespringer/waxbin/art"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
)

// ScopedEnricher is the optional refinement of enrich.Provider a
// multi-capability provider implements so a caller can name the one
// capability it will actually read. The port's Request cannot carry
// that ("capability-scoped provider calls on the enrichment port" in
// upstream-requests.md is the ask that would), so without this a
// genres ask against Discogs downloads a cover nobody reads - once per
// genre-less item. WaxDeck's own per-item paths type-assert and pass
// the want; callers that cannot (the catalog's whole-library pass)
// fall back to Enrich, which answers everything.
type ScopedEnricher interface {
	// EnrichScoped is Enrich restricted to want: work whose result only
	// other capabilities would read is skipped, and a candidate empty
	// for the asked want is a clean miss.
	EnrichScoped(ctx context.Context, req enrich.Request, want enrich.Capability) (*enrich.Candidate, error)
}

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
// Both paths a cover takes now carry it. The catalog's whole-library
// pass hands the store this whole value, and WaxDeck's own enrich-now
// button passes the same format through ArtEditOptions.Format, so a
// picture that neither decodes nor sniffs stores under the same name
// either way. The fold is art.NormalizeFormat's, which is the facade's
// own, so a media type this file read and one a person typed at the
// artwork endpoint cannot land under two tokens. Empty bytes are no
// cover at all, which is a nil result rather than an image that cannot
// be stored.
func coverImage(data []byte, mediaType, sourceURL string) *model.ArtImage {
	if len(data) == 0 {
		return nil
	}
	info := art.Describe(data)
	format := info.Format
	if format == "" {
		format = art.NormalizeFormat(mediaType)
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

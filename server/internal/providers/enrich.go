package providers

import (
	"context"
	"strconv"
	"strings"
	"time"
	"unicode"

	"github.com/colespringer/waxbin/art"
	"github.com/colespringer/waxbin/enrich"
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

// releaseYear reads the leading four-digit year off a provider's
// release date, which arrives as a bare year, a date, or a full
// timestamp depending on the service. Anything else answers empty
// rather than a guess: a year is fanned across every track on an album,
// so a wrong one is not a small error.
func releaseYear(s string) string {
	s = strings.TrimSpace(s)
	if len(s) < 4 {
		return ""
	}
	year := s[:4]
	for _, r := range year {
		if r < '0' || r > '9' {
			return ""
		}
	}
	// A date before recorded music and one past the near future are both
	// a parse landing on the wrong field rather than a release.
	n, err := strconv.Atoi(year)
	if err != nil || n < 1860 || n > time.Now().Year()+2 {
		return ""
	}
	return year
}

// abs is the integer absolute value, for duration comparisons.
func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
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

// WithoutArtistArt wraps a provider so it neither offers artist art nor
// is asked for any. It is what an operator's "never fetch artist
// portraits" setting needs: a provider that also answers release-group
// covers cannot be dropped outright without losing those.
//
// Both halves are necessary, and neither alone is enough. Clearing the
// capability keeps the provider out of the artist backfill's queue,
// which is the pass that walks every artist. Refusing the artist target
// covers the other path: the identity phase asks about an artist
// through the release-group passes, stamping CapCover, which no
// capability mask can distinguish from a real cover ask.
func WithoutArtistArt(p enrich.Provider) enrich.Provider {
	return noArtistArt{Provider: p}
}

type noArtistArt struct{ enrich.Provider }

func (n noArtistArt) Capabilities() enrich.Capability {
	return n.Provider.Capabilities() &^ enrich.CapArtistArt
}

func (n noArtistArt) Enrich(ctx context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if req.Type == enrich.TargetArtist {
		return nil, nil
	}
	return n.Provider.Enrich(ctx, req)
}

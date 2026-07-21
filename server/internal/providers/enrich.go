package providers

import (
	"strings"
	"time"
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

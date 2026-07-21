package providers

import (
	"context"

	"github.com/colespringer/waxdeck/server/internal/match"
)

// Source composes MusicBrainz and AcoustID into the match engine's
// CandidateSource port: release lookups go to MusicBrainz, fingerprints
// to AcoustID. A nil Acoust (or one with an empty API key) turns
// fingerprint lookups into clean misses.
type Source struct {
	MB     *MusicBrainz
	Acoust *AcoustID
}

var _ match.CandidateSource = (*Source)(nil)

// ReleaseByMBID fetches one release with its tracklist.
func (s *Source) ReleaseByMBID(ctx context.Context, mbid string) (*match.Release, error) {
	return s.MB.ReleaseByMBID(ctx, mbid)
}

// ReleasesByGroup fetches the releases in a release group.
func (s *Source) ReleasesByGroup(ctx context.Context, rgMBID string) ([]*match.Release, error) {
	return s.MB.ReleasesByGroup(ctx, rgMBID)
}

// LookupFingerprint resolves a fingerprint through AcoustID; without a
// configured client it is a clean miss.
func (s *Source) LookupFingerprint(ctx context.Context, fp match.Fingerprint) ([]match.FingerprintHit, error) {
	if s.Acoust == nil {
		return nil, nil
	}
	return s.Acoust.LookupFingerprint(ctx, fp)
}

// SearchReleases finds releases by album artist and title text.
func (s *Source) SearchReleases(ctx context.Context, artist, album string, trackCount int) ([]*match.Release, error) {
	return s.MB.SearchReleases(ctx, artist, album, trackCount)
}

// SearchRecordings finds releases carrying a recording that matches the artist
// and track title text.
func (s *Source) SearchRecordings(ctx context.Context, artist, title string) ([]*match.Release, error) {
	return s.MB.SearchRecordings(ctx, artist, title)
}

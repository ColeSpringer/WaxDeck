// Package match is the release matching engine: it turns loose audio files
// into scored candidate releases and an apply-or-review decision. The
// pipeline is cluster (group files into album units), candidates (fetch
// plausible releases through the CandidateSource port), assign (bipartite
// track pairing per candidate), score (weighted field distances), decide
// (auto apply at or below threshold, otherwise review).
//
// The package is pure: no network, no catalog access, deterministic output
// for a given input and source. Everything the engine learns from the
// outside world arrives through CandidateSource, which keeps the evaluation
// corpus trivial to run and the engine importable in isolation.
package match

import "context"

// Track is one audio file the engine considers. Tags use canonical
// uppercase keys (TITLE, ARTIST, ALBUM, ALBUMARTIST, TRACKNUMBER,
// DISCNUMBER, DATE, MUSICBRAINZ_ALBUMID); absent keys are simply omitted.
type Track struct {
	// PID identifies the file to the caller (catalog item PID or an
	// upload id). The engine treats it as opaque.
	PID string
	// Path is the file's location, used only for directory clustering
	// when tags are missing.
	Path string
	// Tags holds the file's current metadata.
	Tags map[string]string
	// DurationSec is the decoded audio length in seconds (0 = unknown).
	DurationSec float64
	// Fingerprint is a compressed Chromaprint fingerprint, empty when
	// unavailable (no fpcalc, or the source exports none).
	Fingerprint string
	// Query, when set, is a recording search somebody supplied outright
	// for this track. Nil for everything the engine derives on its own.
	Query *TrackQuery
}

// TrackQuery is a recording search a person typed, taken verbatim per
// field: the derivation rescues titles machines wrote, and running it
// over a hand-typed one only damages it. An empty field falls back to
// the derivation for that half.
type TrackQuery struct {
	Artist string
	Title  string
}

// Unit is an album sized group of tracks that matches as one decision:
// the whole unit auto applies or the whole unit queues, never both.
type Unit struct {
	// Key is the deterministic cluster key the unit grouped under.
	Key string
	// Tracks are the members ordered by disc, track number, then path.
	Tracks []Track
}

// Release is a candidate release a unit may match.
type Release struct {
	// MBID is the MusicBrainz release id.
	MBID string
	// ReleaseGroupMBID is the release group the release belongs to.
	ReleaseGroupMBID string
	// Title and Artist are the release title and album artist.
	Title  string
	Artist string
	// Year is the original release year (0 = unknown).
	Year int
	// Media is the number of discs (0 = unknown).
	Media int
	// Country, Label, CatalogNumber and Barcode disambiguate editions.
	Country       string
	Label         string
	CatalogNumber string
	Barcode       string
	// Compilation marks a various artists release.
	Compilation bool
	// Tracks is the release tracklist in order.
	Tracks []ReleaseTrack
}

// ReleaseTrack is one track on a candidate release.
type ReleaseTrack struct {
	// RecordingMBID is the MusicBrainz recording id.
	RecordingMBID string
	// Title and Artist name the track; Artist may be empty when it
	// matches the release artist.
	Title  string
	Artist string
	// Disc and Position locate the track (1 based).
	Disc     int
	Position int
	// DurationSec is the track length in seconds (0 = unknown).
	DurationSec float64
}

// Fingerprint is the pair AcoustID lookups need.
type Fingerprint struct {
	Value       string
	DurationSec int
}

// FingerprintHit is one AcoustID result for a fingerprint.
type FingerprintHit struct {
	// RecordingMBID is the matched recording.
	RecordingMBID string
	// ReleaseGroupMBIDs are the release groups the recording appears on.
	ReleaseGroupMBIDs []string
	// Score is the provider's confidence in [0,1].
	Score float64
}

// CandidateSource supplies release candidates. Implementations own their
// rate limiting and caching; a clean miss is (nil, nil) or an empty slice,
// never an error.
type CandidateSource interface {
	// ReleaseByMBID fetches one release with its tracklist.
	ReleaseByMBID(ctx context.Context, mbid string) (*Release, error)
	// ReleasesByGroup fetches the releases in a release group, tracklists
	// included.
	ReleasesByGroup(ctx context.Context, rgMBID string) ([]*Release, error)
	// LookupFingerprint resolves an audio fingerprint to recordings and
	// release groups.
	LookupFingerprint(ctx context.Context, fp Fingerprint) ([]FingerprintHit, error)
	// SearchReleases finds releases by album artist and title text.
	SearchReleases(ctx context.Context, artist, album string, trackCount int) ([]*Release, error)
	// SearchRecordings finds releases carrying a recording that matches the
	// artist and track title text. It is the descriptive path for loose tracks
	// with no album, where a release search has nothing to key on.
	SearchRecordings(ctx context.Context, artist, title string) ([]*Release, error)
}

// Pairing links one unit track to one release track in an assignment.
type Pairing struct {
	// TrackIndex indexes Unit.Tracks, ReleaseIndex indexes Release.Tracks.
	TrackIndex   int
	ReleaseIndex int
	// Distance is the pair's own weighted distance in [0,1].
	Distance float64
}

// Component is one named contribution to a match distance, kept so the
// review queue can explain a score.
type Component struct {
	// Name is the field or penalty ("album", "artist", "year", "tracks",
	// "missing", "extra").
	Name string
	// Distance is the component's raw distance in [0,1] and Weight its
	// share of the total.
	Distance float64
	Weight   float64
}

// Match is one scored candidate for a unit.
type Match struct {
	Release *Release
	// Distance is the weighted total in [0,1]; Similarity is its
	// complement, the percentage the UI shows.
	Distance float64
	// Pairings maps unit tracks onto release tracks.
	Pairings []Pairing
	// MissingIndexes are release track indexes no file matched;
	// ExtraIndexes are unit track indexes no release track matched.
	MissingIndexes []int
	ExtraIndexes   []int
	// Components break the distance down for display.
	Components []Component
}

// Similarity returns the complement of the match distance as a fraction
// in [0,1].
func (m *Match) Similarity() float64 { return 1 - m.Distance }

// Decision is the engine's verdict for a unit.
type Decision int

const (
	// DecisionReview queues the unit with its candidates.
	DecisionReview Decision = iota
	// DecisionAutoApply applies the best candidate without review.
	DecisionAutoApply
	// DecisionNoMatch found no candidates at all.
	DecisionNoMatch
)

// String names the decision for logs and wire mapping.
func (d Decision) String() string {
	switch d {
	case DecisionAutoApply:
		return "auto-apply"
	case DecisionNoMatch:
		return "no-match"
	default:
		return "review"
	}
}

// Proposal is the engine's full answer for one unit: ranked candidates
// and the decision the thresholds produce.
type Proposal struct {
	Unit       Unit
	Candidates []Match
	Decision   Decision
}

// Best returns the top candidate or nil when there is none.
func (p *Proposal) Best() *Match {
	if len(p.Candidates) == 0 {
		return nil
	}
	return &p.Candidates[0]
}

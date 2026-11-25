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
	// when tags are missing, and for order.
	Path string
	// Sent says Path is where the file was sent from in an upload batch,
	// so its folders order the unit (CompareTracks).
	Sent bool
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
	// UploadDated says DATE is when the file was published where it was
	// downloaded from, not a release date: accept-best judges a one-track
	// unit without it.
	UploadDated bool
}

// TrackQuery is a recording search a person typed, kept as typed: the
// artist is searched as it stands and the title as the song it names
// (recordingQuery), never split into an artist. An empty field falls
// back to the derivation for that half.
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
	// with no album, where a release search has nothing to key on. title is
	// the song alone; named, when set, is the title with what names the
	// recording kept ("Song (X Remix)"): the same search asks for it too,
	// ranked above the song's other recordings, and hits titled so are
	// hydrated first (SpreadReleases). album, when set, is the album the
	// unit names: a release titled so is hydrated before any other.
	SearchRecordings(ctx context.Context, artist, title, named, album string) (RecordingSearch, error)
}

// RecordingSearch is what a recording search answered.
type RecordingSearch struct {
	// Releases are the releases it hydrated, tracklists included.
	Releases []*Release
	// Listed is every recording the search listed, hydrated or not, as the
	// listing describes it: enough to judge as a rival, not to apply.
	Listed []ListedRecording
	// Capped says the search listed releases it did not hydrate.
	Capped bool
	// Unlisted says the search counted more hits than it listed.
	Unlisted bool
}

// ListedRecording is one recording a search listed.
type ListedRecording struct {
	MBID        string
	Title       string
	Artist      string
	DurationSec float64 // 0 = unknown
	// Score is the search's relevance for the hit, 0 to 100.
	Score int
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

	// judged is the whole ranking accept-best reads, before the cut to
	// MaxCandidates, scored against judgedUnit; nil reads Candidates. found
	// is that ranking on the tags as read, Candidates before the cut. listed
	// is every recording the recording searches listed, and capped says one
	// listed releases it did not hydrate. unlisted says one counted hits past
	// its page, and pageEnd is the score its page ended at.
	judged     []Match
	found      []Match
	judgedUnit Unit
	weights    Weights
	listed     []ListedRecording
	capped     bool
	unlisted   bool
	pageEnd    int
}

// Best returns the top candidate or nil when there is none.
func (p *Proposal) Best() *Match {
	if len(p.Candidates) == 0 {
		return nil
	}
	return &p.Candidates[0]
}

package match

import (
	"context"
	"sort"
)

// Config tunes the engine. The zero value uses the defaults the
// evaluation corpus was calibrated against.
type Config struct {
	// AutoApplyThreshold is the distance at or below which the best
	// candidate applies without review. Calibrated for precision first:
	// a wrong auto apply is worse than any amount of queued review.
	AutoApplyThreshold float64
	// SinglesAutoApplyThreshold is the distance at or below which a
	// one-track unit's best candidate may auto apply. Stricter than
	// the album threshold because a lone track carries a fraction of
	// an album's evidence; defaults to half AutoApplyThreshold.
	SinglesAutoApplyThreshold float64
	// MaxCandidates caps the ranked candidates a proposal keeps.
	MaxCandidates int
	// MaxFingerprintLookups caps AcoustID lookups per unit; consensus
	// usually stops the spend well before the cap.
	MaxFingerprintLookups int
	// MinHitScore discards fingerprint hits below this confidence.
	MinHitScore float64
	// Weights tunes the distance model.
	Weights Weights
}

func (c Config) withDefaults() Config {
	if c.AutoApplyThreshold == 0 {
		c.AutoApplyThreshold = 0.08
	}
	if c.SinglesAutoApplyThreshold == 0 {
		c.SinglesAutoApplyThreshold = c.AutoApplyThreshold / 2
	}
	if c.MaxCandidates == 0 {
		c.MaxCandidates = 5
	}
	if c.MaxFingerprintLookups == 0 {
		c.MaxFingerprintLookups = 10
	}
	if c.MinHitScore == 0 {
		c.MinHitScore = 0.5
	}
	return c
}

// maxRecordingSearches caps the distinct recording-search queries one unit
// issues, bounding provider spend for a large folder of loose tracks. A single
// acquired video needs one; a mislabeled album is covered by its lead tracks.
const maxRecordingSearches = 4

// Engine runs the pipeline against one CandidateSource.
type Engine struct {
	source CandidateSource
	cfg    Config
}

// NewEngine builds an engine over a candidate source.
func NewEngine(source CandidateSource, cfg Config) *Engine {
	return &Engine{source: source, cfg: cfg.withDefaults()}
}

// Identify gathers candidates for a unit, scores them, and decides.
// Provider errors degrade softly: as long as any evidence path yielded
// candidates the engine proceeds, and only an entirely failed gather
// returns the error.
func (e *Engine) Identify(ctx context.Context, unit Unit) (*Proposal, error) {
	var (
		candidates []*Release
		seen       = make(map[string]bool)
		firstErr   error
	)
	keep := func(rs ...*Release) {
		for _, r := range rs {
			if r == nil || r.MBID == "" || seen[r.MBID] || len(r.Tracks) == 0 {
				continue
			}
			seen[r.MBID] = true
			candidates = append(candidates, r)
		}
	}

	// Tagged release id first: it is the strongest claim the files make.
	if mbid := majorityTag(unit, "MUSICBRAINZ_ALBUMID"); mbid != "" {
		r, err := e.source.ReleaseByMBID(ctx, mbid)
		if err != nil {
			firstErr = err
		}
		keep(r)
	}

	// Fingerprint consensus across the unit's members.
	groups, err := e.fingerprintConsensus(ctx, unit)
	if err != nil && firstErr == nil {
		firstErr = err
	}
	for _, rg := range groups {
		rs, err := e.source.ReleasesByGroup(ctx, rg)
		if err != nil && firstErr == nil {
			firstErr = err
		}
		keep(rs...)
	}

	// Text search from whatever the tags collectively claim.
	if album := majorityTag(unit, "ALBUM"); album != "" {
		rs, err := e.source.SearchReleases(ctx, unitAlbumArtist(unit), album, len(unit.Tracks))
		if err != nil && firstErr == nil {
			firstErr = err
		}
		keep(rs...)
	}

	// Recording search: the descriptive last resort, and the only text path for
	// loose tracks that carry a title but no album (an acquired video, a
	// mislabeled file). It runs when the album paths had nothing to key on, and
	// reads the "Artist - Track" titles and channel-style artist tags that
	// acquired content is shaped by.
	if majorityTag(unit, "ALBUM") == "" || len(candidates) == 0 {
		searched := make(map[string]bool)
		searches := 0
		for _, t := range unit.Tracks {
			if searches >= maxRecordingSearches {
				break
			}
			artist, title, ok := recordingQuery(t)
			if !ok {
				continue
			}
			key := artist + "\x00" + title
			if searched[key] {
				continue
			}
			searched[key] = true
			searches++
			rs, err := e.source.SearchRecordings(ctx, artist, title)
			if err != nil && firstErr == nil {
				firstErr = err
			}
			keep(rs...)
		}
	}

	if len(candidates) == 0 && firstErr != nil {
		return nil, firstErr
	}

	proposal := &Proposal{Unit: unit}
	for _, r := range candidates {
		proposal.Candidates = append(proposal.Candidates, Score(unit, r, e.cfg.Weights))
	}
	sort.SliceStable(proposal.Candidates, func(i, j int) bool {
		a, b := proposal.Candidates[i], proposal.Candidates[j]
		if a.Distance != b.Distance {
			return a.Distance < b.Distance
		}
		return a.Release.MBID < b.Release.MBID
	})
	minDist := 0.0
	if len(proposal.Candidates) > 0 {
		minDist = proposal.Candidates[0].Distance
	}
	if len(unit.Tracks) == 1 {
		reorderNearTies(proposal.Candidates)
	}
	if len(proposal.Candidates) > e.cfg.MaxCandidates {
		proposal.Candidates = proposal.Candidates[:e.cfg.MaxCandidates]
	}

	threshold := e.cfg.AutoApplyThreshold
	if len(unit.Tracks) == 1 {
		threshold = e.cfg.SinglesAutoApplyThreshold
	}
	switch {
	case len(proposal.Candidates) == 0:
		proposal.Decision = DecisionNoMatch
	case proposal.Candidates[0].Distance <= threshold && proposal.Candidates[0].Distance == minDist:
		// The minDist term guards the reorder: a candidate promoted
		// past a strictly closer one is a display preference, and
		// applying it unseen would spend precision on a tiebreak. An
		// exact tie still auto-applies - the promoted candidate is as
		// close as any.
		proposal.Decision = DecisionAutoApply
	default:
		proposal.Decision = DecisionReview
	}
	return proposal, nil
}

// Without the missing penalty a lone track scores nearly alike on
// every release carrying its recording - the album, each compilation,
// a single - so the top of a one-track ranking is decided by
// preference, not noise. nearTieEpsilon bounds the distance band
// treated as one tie (about a year component's worth of disagreement
// at a single's total weight); headerAgreeMax is how far a header
// component may sit from zero and still read as agreement.
const (
	nearTieEpsilon = 0.02
	headerAgreeMax = 0.1
)

// reorderNearTies stable-sorts the candidates within epsilon of the
// best by preference: header agreement with the file's tags first,
// then a plain release over a compilation. Sorting the prefix keeps
// the comparison transitive where epsilon-tolerant comparator keys
// would not, and stability preserves the distance-then-MBID order
// wherever the preferences do not separate two candidates.
func reorderNearTies(cs []Match) {
	n := 1
	for n < len(cs) && cs[n].Distance <= cs[0].Distance+nearTieEpsilon {
		n++
	}
	if n < 2 {
		return
	}
	prefix := cs[:n]
	sort.SliceStable(prefix, func(i, j int) bool {
		if a, b := headerAgreement(prefix[i]), headerAgreement(prefix[j]); a != b {
			return a > b
		}
		return !prefix[i].Release.Compilation && prefix[j].Release.Compilation
	})
}

// headerAgreement counts the album header components (artist, album,
// year) that were compared and agree. A skipped component counts for
// nothing: absence of evidence is not agreement. A compilation's
// artist zero never counts either - Score writes one for an
// album-shaped unit with no album artist tag (differing per-track
// artists are what a compilation looks like); one-track units no
// longer earn it, but the exclusion stays so a fabricated agreement
// can never beat the plain-release preference right below if this
// reorder ever widens past singles.
func headerAgreement(m Match) int {
	agree := 0
	for _, c := range m.Components {
		switch c.Name {
		case "artist":
			if !m.Release.Compilation && c.Distance <= headerAgreeMax {
				agree++
			}
		case "album", "year":
			if c.Distance <= headerAgreeMax {
				agree++
			}
		}
	}
	return agree
}

// fingerprintConsensus looks up member fingerprints until a release
// group holds a majority of the unit's votes, then returns the top
// voted groups (majority holder first, at most three). Stopping at
// majority keeps provider spend low and makes the unit's stragglers
// bind to the consensus candidate through assignment instead of issuing
// their own lookups.
func (e *Engine) fingerprintConsensus(ctx context.Context, unit Unit) ([]string, error) {
	votes := make(map[string]int)
	var firstErr error
	voters := 0
	majority := len(unit.Tracks)/2 + 1
	for _, t := range unit.Tracks {
		if t.Fingerprint == "" {
			continue
		}
		if voters >= e.cfg.MaxFingerprintLookups {
			break
		}
		voters++
		hits, err := e.source.LookupFingerprint(ctx, Fingerprint{Value: t.Fingerprint, DurationSec: int(t.DurationSec + 0.5)})
		if err != nil {
			if firstErr == nil {
				firstErr = err
			}
			continue
		}
		// One vote per release group per track, however many hits agree.
		seen := make(map[string]bool)
		for _, h := range hits {
			if h.Score < e.cfg.MinHitScore {
				continue
			}
			for _, rg := range h.ReleaseGroupMBIDs {
				if rg == "" || seen[rg] {
					continue
				}
				seen[rg] = true
				votes[rg]++
			}
		}
		if leader, count := topVote(votes); leader != "" && count >= majority {
			break
		}
	}
	if len(votes) == 0 {
		return nil, firstErr
	}
	type vote struct {
		rg    string
		count int
	}
	ranked := make([]vote, 0, len(votes))
	for rg, count := range votes {
		ranked = append(ranked, vote{rg, count})
	}
	sort.Slice(ranked, func(i, j int) bool {
		if ranked[i].count != ranked[j].count {
			return ranked[i].count > ranked[j].count
		}
		return ranked[i].rg < ranked[j].rg
	})
	const maxGroups = 3
	out := make([]string, 0, maxGroups)
	for _, v := range ranked {
		if len(out) == maxGroups {
			break
		}
		out = append(out, v.rg)
	}
	return out, firstErr
}

func topVote(votes map[string]int) (string, int) {
	best, bestCount := "", 0
	for rg, count := range votes {
		if count > bestCount || (count == bestCount && rg < best) {
			best, bestCount = rg, count
		}
	}
	return best, bestCount
}

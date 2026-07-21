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
	if len(proposal.Candidates) > e.cfg.MaxCandidates {
		proposal.Candidates = proposal.Candidates[:e.cfg.MaxCandidates]
	}

	switch {
	case len(proposal.Candidates) == 0:
		proposal.Decision = DecisionNoMatch
	case proposal.Candidates[0].Distance <= e.cfg.AutoApplyThreshold:
		proposal.Decision = DecisionAutoApply
	default:
		proposal.Decision = DecisionReview
	}
	return proposal, nil
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

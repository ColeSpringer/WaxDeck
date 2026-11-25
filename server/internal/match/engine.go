package match

import (
	"context"
	"maps"
	"slices"
	"sort"
	"strings"

	"github.com/colespringer/waxdeck/server/internal/sourcenoise"
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
	// BestMatchMaxDistance and BestMatchMargin judge a top candidate a
	// submission asked to take without review (JudgeBest).
	BestMatchMaxDistance float64
	BestMatchMargin      float64
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
	// Both at the precision edge of the evaluation corpus's safe window:
	// the floor at its farthest correct top (a single 4 s off its release),
	// the margin at its narrowest correct gap.
	if c.BestMatchMaxDistance == 0 {
		c.BestMatchMaxDistance = 0.0313
	}
	if c.BestMatchMargin == 0 {
		c.BestMatchMargin = 0.1413
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

// Config is the engine's configuration with its defaults filled in.
func (e *Engine) Config() Config { return e.cfg }

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
	album := unitAlbum(unit)
	if album != "" {
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
	// acquired content is shaped by. An album the paths found nothing for is
	// named to it: a compilation answers no search for a track's artist.
	capped, unlisted, pageEnd := false, false, 0
	var listed []ListedRecording
	if album == "" || len(candidates) == 0 {
		searched := make(map[string]bool)
		searches := 0
		for _, t := range unit.Tracks {
			if searches >= maxRecordingSearches {
				break
			}
			artist, title, named, ok := recordingQuery(t)
			if !ok {
				continue
			}
			key := artist + "\x00" + title + "\x00" + named
			if searched[key] {
				continue
			}
			searched[key] = true
			searches++
			rs, err := e.source.SearchRecordings(ctx, artist, title, named, album)
			if err != nil && firstErr == nil {
				firstErr = err
			}
			capped = capped || rs.Capped
			if rs.Unlisted && len(rs.Listed) > 0 {
				unlisted, pageEnd = true, max(pageEnd, rs.Listed[len(rs.Listed)-1].Score)
			}
			for _, l := range rs.Listed {
				if l.MBID != "" && !slices.ContainsFunc(listed, func(o ListedRecording) bool { return o.MBID == l.MBID }) {
					listed = append(listed, l)
				}
			}
			keep(rs.Releases...)
		}
	}

	if len(candidates) == 0 && firstErr != nil {
		return nil, firstErr
	}

	proposal := &Proposal{Unit: unit, capped: capped, listed: listed, unlisted: unlisted, pageEnd: pageEnd, weights: e.cfg.Weights}
	for _, r := range candidates {
		proposal.Candidates = append(proposal.Candidates, Score(unit, r, e.cfg.Weights))
	}
	rankMatches(proposal.Candidates)
	minDist := 0.0
	if len(proposal.Candidates) > 0 {
		minDist = proposal.Candidates[0].Distance
	}
	if len(unit.Tracks) == 1 {
		reorderNearTies(proposal.Candidates)
	}
	rejudged := false
	proposal.judgedUnit, rejudged = judgedUnit(unit)
	proposal.judged = e.judgedRanking(proposal.judgedUnit, rejudged, proposal.Candidates)
	// Accept-best reads the whole ranking; what is stored stops at the cut.
	proposal.found = proposal.Candidates
	if limit := e.cfg.MaxCandidates; len(proposal.Candidates) > limit {
		proposal.Candidates = proposal.Candidates[:limit:limit]
	}

	threshold := e.cfg.AutoApplyThreshold
	if len(unit.Tracks) == 1 {
		threshold = e.cfg.SinglesAutoApplyThreshold
	}
	switch {
	case len(proposal.Candidates) == 0:
		proposal.Decision = DecisionNoMatch
	case proposal.Candidates[0].Distance <= threshold && proposal.Candidates[0].Distance == minDist &&
		!proposal.topNamesMarkedCut(&proposal.Candidates[0]):
		// The minDist term guards the reorder: a candidate promoted
		// past a strictly closer one is a display preference, and
		// applying it unseen would spend precision on a tiebreak. An
		// exact tie still auto-applies - the promoted candidate is as
		// close as any. A lone track titled as another cut than the
		// top's recording (namesMarkedCut: a live take, a remix, a demo,
		// an edit) is reviewed however close it scores.
		proposal.Decision = DecisionAutoApply
	default:
		proposal.Decision = DecisionReview
	}
	return proposal, nil
}

func rankMatches(ms []Match) {
	sort.SliceStable(ms, func(i, j int) bool {
		a, b := ms[i], ms[j]
		if a.Distance != b.Distance {
			return a.Distance < b.Distance
		}
		return a.Release.MBID < b.Release.MBID
	})
}

// judgedUnit is the unit accept-best judges: a one-track unit re-read as
// judgedTrack derives it (an upload titled "Artist - Title" under a channel's
// name reads far from every release as tagged, and a download's date is its
// upload's), any other as it is. changed says the re-reading differs.
func judgedUnit(unit Unit) (judged Unit, changed bool) {
	if len(unit.Tracks) != 1 {
		return unit, false
	}
	if t, ok := judgedTrack(unit.Tracks[0]); ok {
		return Unit{Key: unit.Key, Tracks: []Track{t}}, true
	}
	return unit, false
}

// judgedRanking is the whole ranking accept-best judges, re-scored on judged
// where that differs from the unit (rejudged). The stored ranking and the
// matcher's own decision stay on the tags as read.
func (e *Engine) judgedRanking(judged Unit, rejudged bool, ranked []Match) []Match {
	if !rejudged {
		return slices.Clone(ranked)
	}
	out := make([]Match, len(ranked))
	for i, m := range ranked {
		out[i] = Score(judged, m.Release, e.cfg.Weights)
	}
	rankMatches(out)
	reorderNearTies(out)
	return out
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

// BestVerdict says whether a proposal's top candidate may be taken
// without review, and why not.
type BestVerdict int

const (
	// BestAcceptable: the top is within the floor and every candidate
	// naming another recording trails it by the margin.
	BestAcceptable BestVerdict = iota
	// BestNoCandidates: nothing was found.
	BestNoCandidates
	// BestBelowFloor: the top is farther than the floor, or its recording
	// is titled as another cut of the song.
	BestBelowFloor
	// BestAmbiguous: nothing rules another recording out. One a candidate
	// or a listing names is within the margin of the top or closer; another
	// track of a one-track unit's top release, under the same title, scores
	// within the margin in its place; the top names no recording beside
	// other candidates; a search hydrated one recording and left releases
	// out, or its page ended inside the top's score; or no artist was
	// compared.
	BestAmbiguous
)

// String names the verdict for logs and wire mapping.
func (v BestVerdict) String() string {
	switch v {
	case BestNoCandidates:
		return "no-candidates"
	case BestBelowFloor:
		return "below-floor"
	case BestAmbiguous:
		return "ambiguous"
	default:
		return "acceptable"
	}
}

// bestEpsilon absorbs float noise in the margin comparison, so a gap of
// exactly the margin passes.
const bestEpsilon = 1e-9

// JudgeBest judges the ranked top as a best match to take without
// review, on the whole ranking the gather found (re-scored on the derived
// artist and title for a one-track unit). The margin is measured on
// identity, not edition: a lone track scores nearly alike on every release
// carrying its recording, and that choice is the near-tie reorder's, so only
// a candidate naming another recording can make the top ambiguous -
// including one strictly closer than a promoted top, a recording a search
// listed without hydrating (listedRivals), one it counted past its page
// (pastThePage), and another track of the top's own release under the same
// title (twinTrackWithin). So can no evidence of identity: a top naming no
// recording beside other candidates, a capped recording search where nothing
// names another recording, or no artist on one side (comparesArtists). A top
// whose recording is titled as another cut of the song than the unit
// (topNamesAnotherCut) is outside the floor whatever its distance: a word
// prefix, a "[Bonus Track]" or "(Album Version)" note and a continuation
// ("II", "(Take 2)") all count, since taking a match unseen errs toward
// waiting. The match returned is scored on the tags as read, as a stored
// candidate is, and may sit past the stored cut: it is what gets applied.
func (p *Proposal) JudgeBest(cfg Config) (*Match, BestVerdict) {
	cfg = cfg.withDefaults()
	ranked := p.judged
	if ranked == nil {
		ranked = p.Candidates
	}
	if len(ranked) == 0 {
		return nil, BestNoCandidates
	}
	top := &ranked[0]
	if top.Distance > cfg.BestMatchMaxDistance+bestEpsilon || p.topNamesAnotherCut(top) {
		return nil, BestBelowFloor
	}
	if !p.comparesArtists(top) || (len(ranked) > 1 && len(pairedRecordings(top)) == 0) ||
		p.twinTrackWithin(top, cfg.BestMatchMargin-bestEpsilon) {
		return nil, BestAmbiguous
	}
	rival := false
	others := append(slices.Clone(ranked[1:]), p.listedRivals(top)...)
	for i := range others {
		other := &others[i]
		if namesDifferentRecording(top, other) {
			if other.Distance-top.Distance < cfg.BestMatchMargin-bestEpsilon {
				return nil, BestAmbiguous
			}
			rival = true
		}
	}
	if p.pastThePage(top) || (!rival && p.capped) {
		return nil, BestAmbiguous
	}
	stored := p.storedFor(top)
	if stored == nil {
		return nil, BestAmbiguous
	}
	return stored, BestAcceptable
}

// listedRivals scores each recording a search listed but did not hydrate as
// if it stood alone on top's release in place of the track top pairs (the
// header kept, the other tracks gone, so the scorer cannot pair the upload
// elsewhere), so only what the listing knows of it (title, artist, length)
// differs from top. A popular song lists more same-titled recordings (live
// takes, sessions, alternates, titled as the song) than a search hydrates.
// One-track units only.
func (p *Proposal) listedRivals(top *Match) []Match {
	if len(p.listed) == 0 || len(p.judgedUnit.Tracks) != 1 || len(top.Pairings) != 1 {
		return nil
	}
	j := top.Pairings[0].ReleaseIndex
	own := top.Release.Tracks[j].RecordingMBID
	var out []Match
	for _, l := range p.listed {
		if l.MBID == own {
			continue
		}
		rel := *top.Release
		rel.Tracks = []ReleaseTrack{top.Release.Tracks[j]}
		rt := &rel.Tracks[0]
		rt.RecordingMBID, rt.Title, rt.DurationSec, rt.Artist = l.MBID, l.Title, l.DurationSec, ""
		if l.Artist != "" && !rel.Compilation {
			rel.Artist = l.Artist
		} else if l.Artist != rel.Artist {
			rt.Artist = l.Artist
		}
		out = append(out, Score(p.judgedUnit, &rel, p.weights))
	}
	return out
}

// pastThePage reports whether a recording search counted hits it did not
// list while its page ended at a score as good as the top recording's, or
// without listing that recording at all: a recording past the page may be
// closer than the top, and the margin never saw it. One-track units only, as
// listedRivals.
func (p *Proposal) pastThePage(top *Match) bool {
	if !p.unlisted || len(p.judgedUnit.Tracks) != 1 {
		return false
	}
	if len(top.Pairings) == 1 {
		if own := top.Release.Tracks[top.Pairings[0].ReleaseIndex].RecordingMBID; own != "" {
			for _, l := range p.listed {
				if l.MBID == own {
					return p.pageEnd >= l.Score
				}
			}
		}
	}
	return true
}

// storedFor is the candidate as the gather scored it, on the tags as read,
// holding m's release and pairing the same recordings; nil when that scoring
// paired it otherwise.
func (p *Proposal) storedFor(m *Match) *Match {
	found := p.found
	if found == nil {
		found = p.Candidates
	}
	want := pairedRecordings(m)
	for i := range found {
		c := &found[i]
		if c.Release.MBID == m.Release.MBID {
			if maps.Equal(pairedRecordings(c), want) {
				return c
			}
			return nil
		}
	}
	return nil
}

// judgedAs is the unit accept-best reads: judgedUnit where Identify set one.
func (p *Proposal) judgedAs() Unit {
	if len(p.judgedUnit.Tracks) > 0 {
		return p.judgedUnit
	}
	return p.Unit
}

// comparesArtists reports whether an artist of the unit was set against one
// of top's release. Without one on both sides a title and a length are all
// that agree, and every artist's recording of the title shares those.
func (p *Proposal) comparesArtists(top *Match) bool {
	unit := p.judgedAs()
	if unitAlbumArtist(unit) == "" {
		return false
	}
	if !top.Release.Compilation {
		return top.Release.Artist != ""
	}
	for _, pr := range top.Pairings {
		if unit.Tracks[pr.TrackIndex].Tags["ARTIST"] == "" || top.Release.Tracks[pr.ReleaseIndex].Artist == "" {
			return false
		}
	}
	return len(top.Pairings) > 0
}

// twinTrackWithin reports whether another track of top's release, titled as
// the one top pairs and another recording, scores within margin of it: a
// release prints a title twice (mono and stereo, a bonus take under the plain
// title), and found by its album no listing names the second. The twin is
// scored in the paired track's place, header and all. One-track units only.
func (p *Proposal) twinTrackWithin(top *Match, margin float64) bool {
	unit := p.judgedAs()
	if len(unit.Tracks) != 1 || len(top.Pairings) != 1 {
		return false
	}
	j := top.Pairings[0].ReleaseIndex
	own := top.Release.Tracks[j]
	for k, rt := range top.Release.Tracks {
		if k == j || (own.RecordingMBID != "" && rt.RecordingMBID == own.RecordingMBID) || titleDist(rt.Title, own.Title) != 0 {
			continue
		}
		d, weight := pairDist(unit.Tracks[0], rt, k, top.Release.Compilation, p.weights.withDefaults())
		var num, den float64
		for _, c := range top.Components {
			if c.Name == "tracks" {
				c.Distance, c.Weight = d, weight
			}
			num += c.Distance * c.Weight
			den += c.Weight
		}
		if den > 0 && num/den-top.Distance < margin {
			return true
		}
	}
	return false
}

// namesDifferentRecording reports whether other pairs some unit track with
// a recording other than the one top pairs it with, or with none where
// top names one. A track top leaves unnamed constrains nothing.
func namesDifferentRecording(top, other *Match) bool {
	theirs := pairedRecordings(other)
	for track, rec := range pairedRecordings(top) {
		if theirs[track] != rec {
			return true
		}
	}
	return false
}

// pairedRecordings maps each unit track a match pairs to the recording it
// names; tracks paired with a release track carrying no recording id are
// left out.
func pairedRecordings(m *Match) map[int]string {
	out := make(map[int]string, len(m.Pairings))
	for _, p := range m.Pairings {
		if rec := m.Release.Tracks[p.ReleaseIndex].RecordingMBID; rec != "" {
			out[p.TrackIndex] = rec
		}
	}
	return out
}

// topNamesAnotherCut is namesAnotherCut for the title a one-track unit is
// judged on and the title of the recording top pairs it with. A search asks
// for the song alone, so a live or clean upload reaches the studio recording
// by design; this is what keeps accept-best from taking it for it. The
// matcher's own decision reads the narrower topNamesMarkedCut.
func (p *Proposal) topNamesAnotherCut(top *Match) bool {
	return p.oneTrackTitles(top, namesAnotherCut)
}

// topNamesMarkedCut is namesMarkedCut for the same two titles.
func (p *Proposal) topNamesMarkedCut(top *Match) bool {
	return p.oneTrackTitles(top, namesMarkedCut)
}

// oneTrackTitles applies differ to a one-track unit's judged title and the
// title of the recording top pairs it with; false for any other unit.
func (p *Proposal) oneTrackTitles(top *Match, differ func(judged, listed string) bool) bool {
	if len(p.judgedUnit.Tracks) != 1 || len(top.Pairings) != 1 {
		return false
	}
	return differ(trackTitle(p.judgedUnit.Tracks[0]), top.Release.Tracks[top.Pairings[0].ReleaseIndex].Title)
}

// namesAnotherCut reports whether two titles name different recordings or
// cuts of a song, however close the strings are: edit distance spreads a
// "(Live)" over the whole title, and a long one carries it under the floor.
// They do when what each holds past the song (a group or tail naming a
// recording, a cut mark; guest credits, upload and remaster notes aside) is
// not the same words, or when one song title only continues the other
// ("(Take 2)", "II"). Titles that differ inside the song are the distance's
// to judge.
func namesAnotherCut(judged, listed string) bool {
	js, jr := songAndRest(judged)
	ls, lr := songAndRest(listed)
	if !slices.Equal(jr, lr) {
		return true
	}
	if len(js) > len(ls) {
		js, ls = ls, js
	}
	return len(js) > 0 && len(js) < len(ls) && slices.Equal(ls[:len(js)], js)
}

// namesMarkedCut is the matcher's own cut check for one file: the titles
// differ in a group after the song that names a cut (sourcenoise.NamesCut),
// a live take, a remix, a demo, an edit, a clean or 8D cut that only one of
// them names or each names otherwise. A continuation, a bonus track, album
// version, explicit or original mix note and a remaster note leave the
// distance to judge.
func namesMarkedCut(judged, listed string) bool {
	return !slices.Equal(cutGroups(judged), cutGroups(listed))
}

// cutGroups is what follows the song in a title, read as songAndRest reads
// one, group by group: the groups naming a cut, normalized and sorted.
func cutGroups(title string) []string {
	s := judgedTitle(sourcenoise.VersionTails(stripFeat(title)))
	core := sourcenoise.CoreTitle(s)
	if !strings.HasPrefix(s, core) {
		return nil
	}
	rest := strings.TrimSpace(s[len(core):])
	var out []string
	for rest != "" {
		start, inner, ok := sourcenoise.TrailingGroup(rest)
		if !ok {
			inner, start = rest, 0
		}
		if sourcenoise.NamesCut(inner) {
			out = append(out, normalize(inner))
		}
		rest = strings.TrimSpace(rest[:start])
	}
	slices.Sort(out)
	return out
}

// songAndRest splits a title, read as judgedTitle reads one, into the words
// of the song itself (sourcenoise.CoreTitle) and of what follows it.
func songAndRest(title string) (song, rest []string) {
	s := judgedTitle(sourcenoise.VersionTails(stripFeat(title)))
	core := sourcenoise.CoreTitle(s)
	if !strings.HasPrefix(s, core) {
		core = s
	}
	return strings.Fields(normalize(core)), strings.Fields(normalize(s[len(core):]))
}

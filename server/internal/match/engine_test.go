package match

import (
	"context"
	"errors"
	"slices"
	"sort"
	"strings"
	"testing"
)

// fakeSource is a scriptable CandidateSource for engine tests.
type fakeSource struct {
	releases     map[string]*Release
	groups       map[string][]*Release
	fingerprints map[string][]FingerprintHit
	searchHits   []*Release
	// recordingHits keys releases on the "artist\x00title" the engine queries;
	// a bare "" key answers any recording search, which lists recordingListed
	// and says recordingCapped and recordingUnlisted.
	recordingHits     map[string][]*Release
	recordingListed   []ListedRecording
	recordingCapped   bool
	recordingUnlisted bool

	lookupCalls      int
	searchCalls      int
	recordingCalls   int
	recordingQueries []string
	recordingNamed   []string
	recordingAlbums  []string
	failAll          bool
}

func (f *fakeSource) ReleaseByMBID(_ context.Context, mbid string) (*Release, error) {
	if f.failAll {
		return nil, errors.New("provider down")
	}
	return f.releases[mbid], nil
}

func (f *fakeSource) ReleasesByGroup(_ context.Context, rg string) ([]*Release, error) {
	if f.failAll {
		return nil, errors.New("provider down")
	}
	return f.groups[rg], nil
}

func (f *fakeSource) LookupFingerprint(_ context.Context, fp Fingerprint) ([]FingerprintHit, error) {
	f.lookupCalls++
	if f.failAll {
		return nil, errors.New("provider down")
	}
	return f.fingerprints[fp.Value], nil
}

func (f *fakeSource) SearchReleases(_ context.Context, artist, album string, _ int) ([]*Release, error) {
	f.searchCalls++
	if f.failAll {
		return nil, errors.New("provider down")
	}
	return f.searchHits, nil
}

func (f *fakeSource) SearchRecordings(_ context.Context, artist, title, named, album string) (RecordingSearch, error) {
	f.recordingAlbums = append(f.recordingAlbums, album)
	f.recordingCalls++
	f.recordingQueries = append(f.recordingQueries, artist+"\x00"+title)
	f.recordingNamed = append(f.recordingNamed, named)
	if f.failAll {
		return RecordingSearch{}, errors.New("provider down")
	}
	if rs, ok := f.recordingHits[artist+"\x00"+title]; ok {
		return RecordingSearch{Releases: rs}, nil
	}
	return RecordingSearch{Releases: f.recordingHits[""], Listed: f.recordingListed, Capped: f.recordingCapped, Unlisted: f.recordingUnlisted}, nil
}

func engineUnit() Unit {
	return unitFor("Artist", "Album", "One", "Two", "Three")
}

func TestIdentifyByTaggedMBID(t *testing.T) {
	r := release("Artist", "Album", 0, "One", "Two", "Three")
	u := engineUnit()
	for i := range u.Tracks {
		u.Tracks[i].Tags["MUSICBRAINZ_ALBUMID"] = r.MBID
	}
	src := &fakeSource{releases: map[string]*Release{r.MBID: r}}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
	if err != nil {
		t.Fatal(err)
	}
	if p.Decision != DecisionAutoApply {
		t.Fatalf("clean tagged unit should auto apply, got %v (best %+v)", p.Decision, p.Best())
	}
	if p.Best().Release.MBID != r.MBID {
		t.Fatalf("wrong release: %v", p.Best().Release.MBID)
	}
}

func TestIdentifyBySearch(t *testing.T) {
	r := release("Artist", "Album", 0, "One", "Two", "Three")
	src := &fakeSource{searchHits: []*Release{r}}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), engineUnit())
	if err != nil {
		t.Fatal(err)
	}
	if p.Decision != DecisionAutoApply || p.Best().Release.MBID != r.MBID {
		t.Fatalf("search candidate should win: %v %+v", p.Decision, p.Best())
	}
}

func TestIdentifyNoEvidence(t *testing.T) {
	src := &fakeSource{}
	u := Unit{Tracks: []Track{{PID: "1", Path: "/x/01 - Something.flac"}}}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
	if err != nil {
		t.Fatal(err)
	}
	if p.Decision != DecisionNoMatch {
		t.Fatalf("no candidates should be no match, got %v", p.Decision)
	}
	if src.searchCalls != 0 {
		t.Fatalf("no album tag should mean no search, got %d calls", src.searchCalls)
	}
}

func TestIdentifyFingerprintConsensusStopsEarly(t *testing.T) {
	r := release("Artist", "Album", 0, "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine", "Ten")
	r.ReleaseGroupMBID = "rg-1"
	titles := make([]string, 10)
	for i, rt := range r.Tracks {
		titles[i] = rt.Title
	}
	u := Unit{}
	for i, title := range titles {
		u.Tracks = append(u.Tracks, Track{
			PID: "t" + title, Path: "/rip/" + itoa(i+1) + " - " + title + ".flac",
			DurationSec: 180 + float64(i), Fingerprint: "fp-" + title,
		})
	}
	fps := make(map[string][]FingerprintHit)
	for _, title := range titles {
		fps["fp-"+title] = []FingerprintHit{{RecordingMBID: "rec-" + title, ReleaseGroupMBIDs: []string{"rg-1"}, Score: 0.95}}
	}
	src := &fakeSource{fingerprints: fps, groups: map[string][]*Release{"rg-1": {r}}}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
	if err != nil {
		t.Fatal(err)
	}
	if p.Decision != DecisionAutoApply || p.Best().Release.MBID != r.MBID {
		t.Fatalf("consensus should auto apply: %v %+v", p.Decision, p.Best())
	}
	// Majority of ten is six: consensus must stop the spend there.
	if src.lookupCalls != 6 {
		t.Fatalf("expected 6 lookups before consensus, got %d", src.lookupCalls)
	}
}

func TestIdentifyDegradesOnPartialFailure(t *testing.T) {
	r := release("Artist", "Album", 0, "One", "Two", "Three")
	u := engineUnit()
	for i := range u.Tracks {
		u.Tracks[i].Tags["MUSICBRAINZ_ALBUMID"] = "unknown-mbid"
	}
	src := &fakeSource{searchHits: []*Release{r}}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
	if err != nil {
		t.Fatal(err)
	}
	if p.Decision != DecisionAutoApply {
		t.Fatalf("missing tagged release should not sink the search path: %v", p.Decision)
	}
}

func TestIdentifyTotalFailureReturnsError(t *testing.T) {
	src := &fakeSource{failAll: true}
	if _, err := NewEngine(src, Config{}).Identify(context.Background(), engineUnit()); err == nil {
		t.Fatal("all paths failing with no candidates should error")
	}
}

func TestIdentifyRanksAndCaps(t *testing.T) {
	var hits []*Release
	for _, title := range []string{"Album", "Albun", "Wrong One", "Very Different", "Another", "Yet Another", "Last"} {
		hits = append(hits, release("Artist", title, 0, "One", "Two", "Three"))
	}
	src := &fakeSource{searchHits: hits}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), engineUnit())
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Candidates) != 5 {
		t.Fatalf("candidates should cap at 5, got %d", len(p.Candidates))
	}
	if p.Best().Release.Title != "Album" {
		t.Fatalf("exact title should rank first, got %q", p.Best().Release.Title)
	}
	if !sort.SliceIsSorted(p.Candidates, func(i, j int) bool {
		return p.Candidates[i].Distance < p.Candidates[j].Distance
	}) {
		// Equal distances are fine; verify non decreasing explicitly.
		for i := 1; i < len(p.Candidates); i++ {
			if p.Candidates[i].Distance < p.Candidates[i-1].Distance {
				t.Fatalf("candidates not ranked: %+v", p.Candidates)
			}
		}
	}
}

// TestIdentifyRecordingSearchSurfacesLooseTrack is the acquired-video case: one
// track with no album, a channel-style artist tag, and the performer packed into
// an "Artist - Track" title. The release search has nothing to key on, so the
// recording search is what surfaces the real release for review.
func TestIdentifyRecordingSearchSurfacesLooseTrack(t *testing.T) {
	rel := release("Amir Obe", "Detrimental", 0, "Drugs & Cam'ron")
	u := Unit{Tracks: []Track{{
		PID:  "up-1",
		Path: "/staging/up-1/Amir Obe - Drugs.opus",
		Tags: map[string]string{
			"ARTIST": "Mixtapes best",
			"TITLE":  "Amir Obe (Phreshy Duzit) - Drugs & Cam'ron",
		},
		DurationSec: 200,
	}}}
	src := &fakeSource{recordingHits: map[string][]*Release{
		"Amir Obe\x00Drugs & Cam'ron": {rel},
	}}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
	if err != nil {
		t.Fatal(err)
	}
	// The channel-style artist and the "Artist - Track" title are read into a
	// clean recording query.
	if len(src.recordingQueries) != 1 || src.recordingQueries[0] != "Amir Obe\x00Drugs & Cam'ron" {
		t.Fatalf("recording query = %v, want [Amir Obe\\x00Drugs & Cam'ron]", src.recordingQueries)
	}
	if p.Best() == nil || p.Best().Release.MBID != rel.MBID {
		t.Fatalf("real release should surface as a candidate, got %+v", p.Best())
	}
	if p.Decision == DecisionNoMatch {
		t.Fatal("a surfaced candidate must not be no-match")
	}
}

// TestIdentifyRecordingSearchGatedByAlbum locks the gate: a unit that already
// matched a release through the album path never spends a recording search.
func TestIdentifyRecordingSearchGatedByAlbum(t *testing.T) {
	r := release("Artist", "Album", 0, "One", "Two", "Three")
	src := &fakeSource{searchHits: []*Release{r}}
	if _, err := NewEngine(src, Config{}).Identify(context.Background(), engineUnit()); err != nil {
		t.Fatal(err)
	}
	if src.recordingCalls != 0 {
		t.Fatalf("album match should gate off recording search, got %d calls", src.recordingCalls)
	}
}

// TestIdentifySingleAutoAppliesWhenConfident: with the missing penalty
// gone, a clean single can reach auto-apply at the engine level (the
// service still gates it behind the per-library switch).
func TestIdentifySingleAutoAppliesWhenConfident(t *testing.T) {
	r := release("Artist", "Album", 0, "One")
	src := &fakeSource{searchHits: []*Release{r}}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), unitFor("Artist", "Album", "One"))
	if err != nil {
		t.Fatal(err)
	}
	if p.Decision != DecisionAutoApply || p.Best().Release.MBID != r.MBID {
		t.Fatalf("clean single should auto apply: %v %+v", p.Decision, p.Best())
	}
}

// TestIdentifySingleStricterThreshold: a distance an album would auto
// apply at queues a single for review, because a lone track carries a
// fraction of the evidence.
func TestIdentifySingleStricterThreshold(t *testing.T) {
	cfg := Config{}.withDefaults()
	r := release("Artist", "Album", 0, "One")
	u := unitFor("Artist", "Album", "One")
	// A 7s duration skew lands the distance between the two thresholds.
	u.Tracks[0].DurationSec = r.Tracks[0].DurationSec + 7
	src := &fakeSource{searchHits: []*Release{r}}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
	if err != nil {
		t.Fatal(err)
	}
	if d := p.Best().Distance; d > cfg.AutoApplyThreshold || d <= cfg.SinglesAutoApplyThreshold {
		t.Fatalf("fixture needs a distance between the singles (%v) and album (%v) thresholds, got %v",
			cfg.SinglesAutoApplyThreshold, cfg.AutoApplyThreshold, d)
	}
	if p.Decision != DecisionReview {
		t.Fatalf("single inside the album threshold must still review, got %v", p.Decision)
	}
}

// TestIdentifySingleCompilationEarnsNoFreeArtist: an untagged single's
// candidates must not tilt toward a compilation. Score fabricates a
// zero-distance artist component for a VA release when no album artist
// tag exists; charged to a one-file unit it dilutes the compilation's
// distance below the album's for identical track evidence, far enough
// to auto-apply the compilation while the album queues.
func TestIdentifySingleCompilationEarnsNoFreeArtist(t *testing.T) {
	cfg := Config{}.withDefaults()
	album := release("Artist", "Album", 0, "One", "Two")
	album.MBID = "rel-zzz"
	comp := release("Various Artists", "Hits of the Year", 0, "One", "Zed")
	comp.MBID = "rel-aaa"
	comp.Compilation = true
	comp.Tracks[0].Artist = "Artist"
	u := Unit{Tracks: []Track{{
		PID: "1", Path: "/x/One.flac",
		Tags: map[string]string{"TITLE": "One"},
		// A 4s skew: with the fabricated zero, the compilation scored
		// 5/8 of the album's distance here - under the singles
		// threshold while the album sat over it.
		DurationSec: album.Tracks[0].DurationSec + 4,
	}}}
	src := &fakeSource{recordingHits: map[string][]*Release{"": {album, comp}}}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Candidates) != 2 || p.Candidates[0].Distance != p.Candidates[1].Distance {
		t.Fatalf("identical track evidence must tie, got %+v", p.Candidates)
	}
	if p.Best().Release.MBID != "rel-zzz" {
		t.Fatalf("the tie must prefer the plain release, got %v", p.Best().Release.MBID)
	}
	if p.Decision == DecisionAutoApply {
		t.Fatalf("distance %v is over the singles threshold %v and must review",
			p.Best().Distance, cfg.SinglesAutoApplyThreshold)
	}
}

// TestIdentifySingleNearTiePrefersHeaderAgreement: two editions within
// the tie band; the one whose headers corroborate the file's tags must
// win even when the other edges it on raw distance and MBID order.
func TestIdentifySingleNearTiePrefersHeaderAgreement(t *testing.T) {
	agreeing := release("Artist", "Album", 1994, "One")
	agreeing.MBID = "rel-zzz"
	closer := release("Artist", "Album", 1995, "One")
	closer.MBID = "rel-aaa"
	u := unitFor("Artist", "Album", "One")
	u.Tracks[0].Tags["DATE"] = "1994"
	// The file's duration sides with the wrong-year edition, so the
	// year-agreeing one scores slightly worse - but within the band.
	u.Tracks[0].DurationSec = 184
	closer.Tracks[0].DurationSec = 184
	src := &fakeSource{searchHits: []*Release{agreeing, closer}}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Candidates) != 2 {
		t.Fatalf("want both editions ranked, got %+v", p.Candidates)
	}
	if p.Candidates[0].Distance < p.Candidates[1].Distance {
		t.Fatalf("case needs the agreeing edition distance-behind, got %v then %v",
			p.Candidates[0].Distance, p.Candidates[1].Distance)
	}
	if p.Best().Release.MBID != "rel-zzz" {
		t.Fatalf("header agreement should top a near-tie, got %v", p.Best().Release.MBID)
	}
	// The promotion moved a strictly farther candidate to the top, so
	// even inside the threshold this is a person's call, not an apply.
	if p.Decision == DecisionAutoApply {
		t.Fatal("a preference-promoted candidate must not auto apply")
	}
}

// TestIdentifySingleNearTiePrefersAlbumOverCompilation: an untagged
// single ties exactly across a plain release and a compilation carrying
// the same track; the plain release must win despite the compilation's
// MBID sorting first and its fabricated zero-distance artist component.
func TestIdentifySingleNearTiePrefersAlbumOverCompilation(t *testing.T) {
	album := release("Artist", "Album", 0, "One", "Two")
	album.MBID = "rel-zzz"
	comp := release("Various Artists", "Hits of the Year", 0, "One", "Zed")
	comp.MBID = "rel-aaa"
	comp.Compilation = true
	comp.Tracks[0].Artist = "Artist"
	u := Unit{Tracks: []Track{{
		PID: "1", Path: "/x/One.flac",
		Tags:        map[string]string{"TITLE": "One"},
		DurationSec: 180,
	}}}
	src := &fakeSource{recordingHits: map[string][]*Release{"": {album, comp}}}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Candidates) != 2 || p.Candidates[0].Distance != p.Candidates[1].Distance {
		t.Fatalf("case needs an exact tie, got %+v", p.Candidates)
	}
	if p.Best().Release.MBID != "rel-zzz" {
		t.Fatalf("plain release should top a tied compilation, got %v", p.Best().Release.MBID)
	}
}

func TestIdentifyDeterministicTieBreak(t *testing.T) {
	a := release("Artist", "Album", 0, "One", "Two", "Three")
	a.MBID = "rel-aaa"
	b := release("Artist", "Album", 0, "One", "Two", "Three")
	b.MBID = "rel-bbb"
	src := &fakeSource{searchHits: []*Release{b, a}}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), engineUnit())
	if err != nil {
		t.Fatal(err)
	}
	if p.Best().Release.MBID != "rel-aaa" {
		t.Fatalf("ties must break on MBID for determinism, got %v", p.Best().Release.MBID)
	}
}

func TestIdentifyPlaceholderAlbumRunsRecordingSearch(t *testing.T) {
	rel := release("Band", "Real Album", 0, "Song")
	u := Unit{Tracks: []Track{{
		PID:  "up-1",
		Path: "/staging/up-1/Song.opus",
		Tags: map[string]string{
			"ARTIST": "Band", "TITLE": "Song", "ALBUM": "Song - Single",
		},
		DurationSec: 200,
	}}}
	src := &fakeSource{
		searchHits:    []*Release{release("Band", "Song - Single", 0, "Song")},
		recordingHits: map[string][]*Release{"Band\x00Song": {rel}},
	}
	if _, err := NewEngine(src, Config{}).Identify(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	if src.recordingCalls == 0 {
		t.Fatal("a placeholder album must not gate off the recording search")
	}
	if src.searchCalls != 0 {
		t.Fatalf("a placeholder album is no album search term, got %d album searches", src.searchCalls)
	}
}

// ranked builds a scored candidate pairing unit track i with release track
// i, which names recs[i]; an empty rec leaves that track unpaired.
func ranked(mbid string, dist float64, recs ...string) Match {
	r := &Release{MBID: mbid, Artist: "Artist"}
	m := Match{Release: r, Distance: dist}
	for i, rec := range recs {
		r.Tracks = append(r.Tracks, ReleaseTrack{RecordingMBID: rec, Position: i + 1})
		if rec != "" {
			m.Pairings = append(m.Pairings, Pairing{TrackIndex: i, ReleaseIndex: i})
		}
	}
	return m
}

// judgedProposal is a proposal of scored candidates for a unit naming its
// artist, as JudgeBest reads one.
func judgedProposal(candidates ...Match) *Proposal {
	return &Proposal{Unit: unitFor("Artist", "", "One", "Two"), Candidates: candidates}
}

func TestJudgeBest(t *testing.T) {
	cfg := Config{BestMatchMaxDistance: 0.15, BestMatchMargin: 0.05}
	cases := []struct {
		name       string
		candidates []Match
		want       string // the accepted release, "" for none
		verdict    BestVerdict
	}{
		{
			name:       "clear winner",
			candidates: []Match{ranked("a", 0.05, "r1"), ranked("b", 0.30, "r2")},
			want:       "a", verdict: BestAcceptable,
		},
		{
			name:       "outside the floor",
			candidates: []Match{ranked("a", 0.20, "r1")},
			verdict:    BestBelowFloor,
		},
		{
			name:       "outside the floor and ambiguous reads as the floor",
			candidates: []Match{ranked("a", 0.20, "r1"), ranked("b", 0.21, "r2")},
			verdict:    BestBelowFloor,
		},
		{
			name:       "promoted near-tie past a strictly closer recording",
			candidates: []Match{ranked("a", 0.06, "r1"), ranked("b", 0.05, "r2")},
			verdict:    BestAmbiguous,
		},
		{
			name: "near-ties all on the same recording take the reordered top",
			candidates: []Match{
				ranked("a", 0.06, "r1"), ranked("b", 0.05, "r1"), ranked("c", 0.30, "r2"),
			},
			want: "a", verdict: BestAcceptable,
		},
		{
			name:       "a different recording inside the margin",
			candidates: []Match{ranked("a", 0.05, "r1"), ranked("b", 0.08, "r2")},
			verdict:    BestAmbiguous,
		},
		{
			name:       "a different recording exactly the margin behind",
			candidates: []Match{ranked("a", 0.05, "r1"), ranked("b", 0.10, "r2")},
			want:       "a", verdict: BestAcceptable,
		},
		{
			name:       "none",
			candidates: nil,
			verdict:    BestNoCandidates,
		},
		{
			name:       "an album differing on one track is a different recording",
			candidates: []Match{ranked("a", 0.05, "r1", "r2"), ranked("b", 0.07, "r1", "r3")},
			verdict:    BestAmbiguous,
		},
		{
			name:       "an album leaving unpaired a track the top names",
			candidates: []Match{ranked("a", 0.05, "r1", "r2"), ranked("b", 0.07, "r1", "")},
			verdict:    BestAmbiguous,
		},
		{
			name:       "an album naming a track the top leaves unpaired is the same",
			candidates: []Match{ranked("a", 0.05, "r1", ""), ranked("b", 0.06, "r1", "r9")},
			want:       "a", verdict: BestAcceptable,
		},
		{
			name:       "a top naming no recording beside another candidate",
			candidates: []Match{ranked("a", 0.05, ""), ranked("b", 0.30, "r2")},
			verdict:    BestAmbiguous,
		},
		{
			name:       "a top naming no recording alone",
			candidates: []Match{ranked("a", 0.05, "")},
			want:       "a", verdict: BestAcceptable,
		},
		{
			name:       "an album agreeing on every track is the same",
			candidates: []Match{ranked("a", 0.05, "r1", "r2"), ranked("b", 0.06, "r1", "r2")},
			want:       "a", verdict: BestAcceptable,
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got, v := judgedProposal(c.candidates...).JudgeBest(cfg)
			switch {
			case c.want == "" && got != nil:
				t.Fatalf("accepted %s, want none", got.Release.MBID)
			case c.want != "" && (got == nil || got.Release.MBID != c.want):
				t.Fatalf("accepted %v, want %s", got, c.want)
			}
			if v != c.verdict {
				t.Fatalf("verdict %v, want %v", v, c.verdict)
			}
		})
	}
}

// TestJudgeBestDefaults: the zero Config judges with the shipped floor and
// margin.
func TestJudgeBestDefaults(t *testing.T) {
	cfg := Config{}.withDefaults()
	if cfg.BestMatchMaxDistance <= 0 || cfg.BestMatchMargin <= 0 {
		t.Fatalf("defaults floor %v margin %v, want both set", cfg.BestMatchMaxDistance, cfg.BestMatchMargin)
	}
	if m, _ := judgedProposal(ranked("a", cfg.BestMatchMaxDistance, "r1")).JudgeBest(Config{}); m == nil {
		t.Fatal("a top at the default floor is not accepted")
	}
	if m, _ := judgedProposal(ranked("a", cfg.BestMatchMaxDistance+0.01, "r1")).JudgeBest(Config{}); m != nil {
		t.Fatal("a top past the default floor is accepted")
	}
}

// looseSong is one acquired file: ARTIST and TITLE as given, no album.
func looseSong(artist, title string, dur float64) Unit {
	return Unit{Tracks: []Track{{
		PID: "up-1", Path: "/staging/up-1/" + title + ".opus",
		Tags:        map[string]string{"ARTIST": artist, "TITLE": title},
		DurationSec: dur, Fingerprint: "fp-1",
	}}}
}

// songOn is a one-track release of the recording rec.
func songOn(mbid, artist, title, rec string, dur float64) *Release {
	return &Release{MBID: mbid, Title: "Album " + mbid, Artist: artist, Tracks: []ReleaseTrack{{
		RecordingMBID: rec, Title: title, Disc: 1, Position: 1, DurationSec: dur,
	}}}
}

// A rival recording ranked past the stored candidates still makes the top
// ambiguous: accept-best is judged on everything the gather found.
func TestAcceptBestJudgesPastTheCandidateCap(t *testing.T) {
	var editions []*Release
	for _, id := range []string{"e1", "e2", "e3", "e4", "e5"} {
		editions = append(editions, songOn(id, "Band", "Song", "r1", 200))
	}
	src := &fakeSource{
		fingerprints:  map[string][]FingerprintHit{"fp-1": {{RecordingMBID: "r1", ReleaseGroupMBIDs: []string{"g1"}, Score: 1}}},
		groups:        map[string][]*Release{"g1": editions},
		recordingHits: map[string][]*Release{"": {songOn("rival", "Band", "Song", "r2", 204)}},
	}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), looseSong("Band", "Song", 200))
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Candidates) != 5 {
		t.Fatalf("stored %d candidates, want the cap of 5", len(p.Candidates))
	}
	if m, v := p.JudgeBest(Config{}); m != nil || v != BestAmbiguous {
		t.Fatalf("verdict %v (match %v), want ambiguous: the rival recording is 0.03 behind", v, m != nil)
	}
}

// A recording search that listed releases it did not hydrate, all of one
// recording, is no evidence any other recording was looked at; the provider
// says so, whatever the hydration kept.
func TestAcceptBestWithholdsACappedSearchOfOneRecording(t *testing.T) {
	for _, c := range []struct {
		n      int
		capped bool
		want   BestVerdict
	}{
		{4, false, BestAcceptable},
		{5, false, BestAcceptable},
		{5, true, BestAmbiguous},
		{4, true, BestAmbiguous}, // a hydration lost one release
	} {
		var hits []*Release
		for i := range c.n {
			hits = append(hits, songOn("e"+itoa(i+1), "Band", "Song", "r1", 200))
		}
		src := &fakeSource{recordingHits: map[string][]*Release{"": hits}, recordingCapped: c.capped}
		p, err := NewEngine(src, Config{}).Identify(context.Background(), looseSong("Band", "Song", 200))
		if err != nil {
			t.Fatal(err)
		}
		if _, v := p.JudgeBest(Config{}); v != c.want {
			t.Fatalf("%d releases of one recording, capped %v: verdict %v, want %v", c.n, c.capped, v, c.want)
		}
	}
}

// A recording the search listed but did not hydrate is a rival on what the
// listing knows of it: titled as the song, a session two seconds off the
// upload makes the top ambiguous; a live take half a minute longer does not.
func TestAcceptBestJudgesListedRecordings(t *testing.T) {
	for _, c := range []struct {
		name   string
		listed ListedRecording
		want   BestVerdict
	}{
		{"a session at the length", ListedRecording{MBID: "r2", Title: "Song", Artist: "Band", DurationSec: 202}, BestAmbiguous},
		{"a session with no length", ListedRecording{MBID: "r2", Title: "Song", Artist: "Band"}, BestAmbiguous},
		{"a longer live take", ListedRecording{MBID: "r2", Title: "Song", Artist: "Band", DurationSec: 230}, BestAcceptable},
		{"another band's cover", ListedRecording{MBID: "r2", Title: "Song", Artist: "Strangers Collective", DurationSec: 200}, BestAcceptable},
		{"the top's own recording", ListedRecording{MBID: "r1", Title: "Song", Artist: "Band", DurationSec: 200}, BestAcceptable},
	} {
		t.Run(c.name, func(t *testing.T) {
			src := &fakeSource{
				recordingHits:   map[string][]*Release{"": {songOn("album", "Band", "Song", "r1", 200)}},
				recordingListed: []ListedRecording{{MBID: "r1", Title: "Song", Artist: "Band", DurationSec: 200}, c.listed},
			}
			p, err := NewEngine(src, Config{}).Identify(context.Background(), looseSong("Band", "Song", 200))
			if err != nil {
				t.Fatal(err)
			}
			if _, v := p.JudgeBest(Config{}); v != c.want {
				t.Fatalf("verdict %v, want %v", v, c.want)
			}
		})
	}
}

// A typed title, often pre-filled from the suggestion, searches as the
// derived one would: its upload note or cut mark is not a search term.
func TestATypedTitleSearchesClean(t *testing.T) {
	for _, typed := range []string{"Song (Clean)", "Song (Official Video)"} {
		src := &fakeSource{recordingHits: map[string][]*Release{"Band\x00Song": {songOn("album", "Band", "Song", "r1", 200)}}}
		unit := looseSong("Some Channel", "Some Channel - Whatever", 200)
		unit.Tracks[0].Query = &TrackQuery{Artist: "Band", Title: typed}
		p, err := NewEngine(src, Config{}).Identify(context.Background(), unit)
		if err != nil {
			t.Fatal(err)
		}
		if p.Best() == nil || p.Best().Release.MBID != "album" {
			t.Fatalf("typed %q: searched %q, best %v; want the canned recording found", typed, src.recordingQueries, p.Best())
		}
		if unit.Tracks[0].Query.Title != typed {
			t.Fatalf("typed %q became %q", typed, unit.Tracks[0].Query.Title)
		}
	}
}

// A search pre-filled from the suggestion asks for the song: the suggestion
// keeps what names the recording ("(Live at Sin-e)"), which MusicBrainz
// titles by the song alone, so the phrase as suggested finds nothing.
func TestASeededSuggestionSearchesTheSong(t *testing.T) {
	for _, title := range []string{"Song (Live at Sin-\u00e9)", "Song - Live at the BBC", "Song (X Remix)", "Song - Radio Edit (Clean)"} {
		upload := looseSong("Band", title, 200)
		artist, suggested, ok := SuggestedQuery(upload.Tracks[0])
		if !ok || suggested == "Song" {
			t.Fatalf("%q: suggested %q (%v), want what names the recording kept", title, suggested, ok)
		}
		for _, seeded := range []bool{false, true} {
			src := &fakeSource{recordingHits: map[string][]*Release{"Band\x00Song": {songOn("album", "Band", "Song", "r1", 200)}}}
			unit := looseSong("Band", title, 200)
			if seeded {
				unit.Tracks[0].Query = &TrackQuery{Artist: artist, Title: suggested}
			}
			p, err := NewEngine(src, Config{}).Identify(context.Background(), unit)
			if err != nil {
				t.Fatal(err)
			}
			if p.Best() == nil || p.Best().Release.MBID != "album" {
				t.Fatalf("%q (seeded %v): searched %q, best %v; want the canned recording found", title, seeded, src.recordingQueries, p.Best())
			}
			if seeded && unit.Tracks[0].Query.Title != suggested {
				t.Fatalf("typed %q became %q", suggested, unit.Tracks[0].Query.Title)
			}
		}
	}
}

// The search finds the song; the judged title keeps "(X Remix)" and picks
// the remix among what was found, and never takes the original for it.
func TestARemixUploadJudgesToTheRemix(t *testing.T) {
	original := songOn("album", "Band", "Song", "r1", 200)
	remix := songOn("remix", "Band", "Song (X Remix)", "r2", 200)
	for _, c := range []struct {
		name, title string
		found       []*Release
		want        string
		wantVerdict BestVerdict
		wantNamed   string
	}{
		{"the remix beside the original", "Song (X Remix)", []*Release{original, remix}, "remix", BestAcceptable, "Song (X Remix)"},
		{"a remix the search does not hold", "Song (X Remix)", []*Release{original}, "", BestBelowFloor, "Song (X Remix)"},
		{"the original beside the remix", "Song", []*Release{original, remix}, "album", BestAcceptable, ""},
	} {
		t.Run(c.name, func(t *testing.T) {
			src := &fakeSource{recordingHits: map[string][]*Release{"Band\x00Song": c.found}}
			p, err := NewEngine(src, Config{}).Identify(context.Background(), looseSong("Band", c.title, 200))
			if err != nil {
				t.Fatal(err)
			}
			if len(src.recordingNamed) != 1 || src.recordingNamed[0] != c.wantNamed {
				t.Fatalf("searched %q named %q, want (Band, Song) named %q", src.recordingQueries, src.recordingNamed, c.wantNamed)
			}
			m, v := p.JudgeBest(Config{})
			got := ""
			if m != nil {
				got = m.Release.MBID
			}
			if v != c.wantVerdict || got != c.want {
				t.Fatalf("verdict %v on %q, want %v on %q", v, got, c.wantVerdict, c.want)
			}
		})
	}
}

// A search that counted more hits than it listed hides recordings the
// margin never sees: when the listed page ends at a score as good as the
// top recording's, an unlisted one may be the closer recording.
func TestAcceptBestJudgesThePageEdge(t *testing.T) {
	take := func(mbid string, score int) ListedRecording {
		return ListedRecording{MBID: mbid, Title: "Song", Artist: "Band", DurationSec: 240, Score: score}
	}
	own := func(score int) ListedRecording {
		return ListedRecording{MBID: "r1", Title: "Song", Artist: "Band", DurationSec: 200, Score: score}
	}
	for _, c := range []struct {
		name     string
		listed   []ListedRecording
		unlisted bool
		want     BestVerdict
	}{
		{"the page ends inside the top's score", []ListedRecording{own(100), take("r2", 100), take("r3", 100)}, true, BestAmbiguous},
		{"the page ends below the top's score", []ListedRecording{own(100), take("r2", 100), take("r3", 82)}, true, BestAcceptable},
		{"nothing past the page", []ListedRecording{own(100), take("r2", 100), take("r3", 100)}, false, BestAcceptable},
		{"the top's recording is not on the page", []ListedRecording{take("r2", 100), take("r3", 60)}, true, BestAmbiguous},
	} {
		t.Run(c.name, func(t *testing.T) {
			src := &fakeSource{
				recordingHits:     map[string][]*Release{"": {songOn("album", "Band", "Song", "r1", 200)}},
				recordingListed:   c.listed,
				recordingUnlisted: c.unlisted,
			}
			p, err := NewEngine(src, Config{}).Identify(context.Background(), looseSong("Band", "Song", 200))
			if err != nil {
				t.Fatal(err)
			}
			if _, v := p.JudgeBest(Config{}); v != c.want {
				t.Fatalf("verdict %v, want %v", v, c.want)
			}
		})
	}
}

// A search that names the recording boosts the hits holding the name, so the
// page's scores fall from them to the song's other recordings. The page-edge
// rule reads the same: a page ending among the plain takes ended below the
// named top, and one ending among hits scored as the top did not.
func TestAcceptBestJudgesThePageEdgeOfANamedSearch(t *testing.T) {
	remix := func(mbid string, dur float64) ListedRecording {
		return ListedRecording{MBID: mbid, Title: "Song (X Remix)", Artist: "Band", DurationSec: dur, Score: 100}
	}
	plain := func(mbid string) ListedRecording {
		return ListedRecording{MBID: mbid, Title: "Song", Artist: "Band", DurationSec: 200, Score: 24}
	}
	for _, c := range []struct {
		name   string
		listed []ListedRecording
		want   BestVerdict
	}{
		{"the page ends among the plain takes", []ListedRecording{remix("r1", 200), plain("r2"), plain("r3")}, BestAcceptable},
		{"the page ends among hits holding the name", []ListedRecording{remix("r1", 200), remix("r2", 260), remix("r3", 280)}, BestAmbiguous},
	} {
		t.Run(c.name, func(t *testing.T) {
			src := &fakeSource{
				recordingHits:     map[string][]*Release{"": {songOn("remix", "Band", "Song (X Remix)", "r1", 200)}},
				recordingListed:   c.listed,
				recordingUnlisted: true,
			}
			p, err := NewEngine(src, Config{}).Identify(context.Background(), looseSong("Band", "Song (X Remix)", 200))
			if err != nil {
				t.Fatal(err)
			}
			if got := src.recordingNamed; len(got) != 1 || got[0] != "Song (X Remix)" {
				t.Fatalf("named %q, want the search to name the remix", got)
			}
			if _, v := p.JudgeBest(Config{}); v != c.want {
				t.Fatalf("verdict %v, want %v", v, c.want)
			}
		})
	}
}

// A listed rival is judged against the top's release holding it alone in
// place of the top's track: on a release carrying the top's recording twice,
// the scorer must not pair the upload with the second copy and lose the rival.
func TestAcceptBestJudgesAListedRivalOnItsOwnTrack(t *testing.T) {
	for _, twice := range []bool{false, true} {
		rel := songOn("album", "Band", "Song", "r1", 200)
		if twice {
			rel.Tracks = append(rel.Tracks, ReleaseTrack{RecordingMBID: "r1", Title: "Song", Disc: 1, Position: 2, DurationSec: 200})
		}
		src := &fakeSource{
			recordingHits: map[string][]*Release{"": {rel}},
			recordingListed: []ListedRecording{
				{MBID: "r1", Title: "Song", Artist: "Band", DurationSec: 200},
				{MBID: "r2", Title: "Song", Artist: "Band", DurationSec: 207},
			},
		}
		p, err := NewEngine(src, Config{}).Identify(context.Background(), looseSong("Band", "Song", 200))
		if err != nil {
			t.Fatal(err)
		}
		if _, v := p.JudgeBest(Config{}); v != BestAmbiguous {
			t.Fatalf("top's recording twice on its release %v: verdict %v, want ambiguous: a rival 7 s off", twice, v)
		}
	}
}

// An "Artist - Title" upload under the band's channel is judged on the split
// title and artist; the stored ranking and the matcher's own decision stay on
// the tags as read.
func TestAcceptBestJudgesTheDerivedTitle(t *testing.T) {
	rel := songOn("album", "The Band", "Song", "r1", 200)
	src := &fakeSource{recordingHits: map[string][]*Release{"": {rel, songOn("live", "The Band", "Song (Live)", "r2", 231)}}}
	for _, title := range []string{"The Band - Song", "Song - Remastered 2020"} {
		p, err := NewEngine(src, Config{}).Identify(context.Background(), looseSong("The Band", title, 200))
		if err != nil {
			t.Fatal(err)
		}
		cfg := Config{}.withDefaults()
		if p.Best() == nil || p.Best().Distance <= cfg.BestMatchMaxDistance || p.Decision == DecisionAutoApply {
			t.Fatalf("%q: raw top %+v decision %v, want the raw score past the floor", title, p.Best(), p.Decision)
		}
		m, v := p.JudgeBest(Config{})
		if v != BestAcceptable || m == nil || m.Release.MBID != "album" || m != &p.Candidates[0] {
			t.Fatalf("%q: verdict %v match %v, want the stored album candidate accepted", title, v, m)
		}
	}
}

// Edit distance spreads a short group over a long title, so accept-best also
// reads what each title names past the song: a difference there is another
// recording or cut however close the strings are.
func TestNamesAnotherCut(t *testing.T) {
	const long = "Nocturne for the Lighthouse Keeper Who Never Saw the Morning Come Ashore"
	for _, c := range []struct {
		judged, listed string
		want           bool
	}{
		{"Song", "Song", false},
		{"Song", "song!", false},
		{"Sogn Title", "Song Title", false},
		{"Song (Live)", "Song (live)", false},
		{"Song (Live)", "Song - Live", false},
		{"Song (X Remix)", "Song (X remix)", false},
		{"Song (feat. Guest)", "Song", false},
		{"Song (feat. Guest) (Live)", "Song (live)", false},
		{"Song (Part 2)", "Song (Part 2)", false},
		{long, long, false},
		{long + " (Live 1979)", long + " (live 1979)", false},
		{"Song (Live)", "Song", true},
		{"Song", "Song (live)", true},
		{long + " (Live)", long, true},
		{long + " (Demo)", long, true},
		{long + " (Clean)", long, true},
		{long, long + " (acoustic)", true},
		{long + " (Live 1977)", long + " (Live 1979)", true},
		{long + " (Live)", long + " (Demo)", true},
		{long + " (X Remix)", long + " (Y Remix)", true},
		{"Song (feat. Guest) (Live)", "Song (feat. Guest)", true},
		// A group the search does not know still continues the title.
		{long + " (Take 2)", long, true},
		{long, long + " II", true},
		{long, long + ", Pt. 2", true},
		{long + " [Bonus Track]", long, true},
		{long + " (Album Version)", long, true},
		{long + " (Explicit)", long, true},
		{long + " [Explicit]", long, true},
		{long + " (Original Mix)", long, true},
		// Parts are the song's own title, which a search asks for whole;
		// telling them apart is the distance's.
		{long + " (Part 1)", long + " (Part 2)", false},
		// The same recording under a remaster note.
		{long, long + " (2011 Remaster)", false},
		{long, long + " - Remastered 2011", false},
		{long + " (Live)", long + " - Live (2011 Remaster)", false},
	} {
		if got := namesAnotherCut(c.judged, c.listed); got != c.want {
			t.Errorf("namesAnotherCut(%q, %q) = %v, want %v", c.judged, c.listed, got, c.want)
		}
	}
}

// A store single of several tracks names a real album, so it is searched for
// and scored as one; carried by one track alone the same album is not.
func TestIdentifyAStoreSingleSearchesItsAlbum(t *testing.T) {
	rel := release("Band", "Song - Single", 0, "Song", "Song (Acoustic)")
	u := unitFor("Band", "Song - Single", "Song", "Song (Acoustic)")
	src := &fakeSource{searchHits: []*Release{rel}}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
	if err != nil {
		t.Fatal(err)
	}
	if src.searchCalls != 1 || src.recordingCalls != 0 {
		t.Fatalf("%d album searches, %d recording searches; want the single searched as an album", src.searchCalls, src.recordingCalls)
	}
	if p.Best() == nil || !slices.ContainsFunc(p.Best().Components, func(c Component) bool { return c.Name == "album" && c.Distance == 0 }) {
		t.Fatalf("best = %+v, want the album compared and agreeing", p.Best())
	}
	if p.Decision != DecisionAutoApply {
		t.Fatalf("decision %v at %.3f, want the two-track single applied as one unit", p.Decision, p.Best().Distance)
	}
}

// Nothing rules another artist's recording out when either side names no
// artist: a title and a length are all that was compared.
func TestAcceptBestNeedsAnArtistOnBothSides(t *testing.T) {
	for _, c := range []struct {
		name           string
		artist, credit string
		compilation    bool
		trackArtist    string
		want           BestVerdict
	}{
		{"both name one", "Someone", "Someone", false, "", BestAcceptable},
		{"the file names none", "", "Someone", false, "", BestAmbiguous},
		{"the release names none", "Someone", "", false, "", BestAmbiguous},
		{"a compilation crediting the track", "Someone", "Various Artists", true, "Someone", BestAcceptable},
		{"a compilation crediting no track artist", "Someone", "Various Artists", true, "", BestAmbiguous},
		{"a compilation and a file naming none", "", "Various Artists", true, "Someone", BestAmbiguous},
	} {
		t.Run(c.name, func(t *testing.T) {
			rel := songOn("rel-x", c.credit, "Xylophone Dreams", "rec-x", 200)
			rel.Compilation = c.compilation
			rel.Tracks[0].Artist = c.trackArtist
			u := looseSong(c.artist, "Xylophone Dreams", 200)
			if c.artist == "" {
				delete(u.Tracks[0].Tags, "ARTIST")
			}
			src := &fakeSource{
				recordingHits: map[string][]*Release{"": {rel}},
				recordingListed: []ListedRecording{
					{MBID: "rec-x", Title: "Xylophone Dreams", Artist: "Someone", DurationSec: 200},
					{MBID: "rec-y", Title: "Xylophone Dreams", Artist: "Another", DurationSec: 230},
					{MBID: "rec-z", Title: "Xylophone Dreams", Artist: "A Third", DurationSec: 260},
				},
			}
			p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
			if err != nil {
				t.Fatal(err)
			}
			if m, v := p.JudgeBest(Config{}); v != c.want || (m != nil) != (c.want == BestAcceptable) {
				t.Fatalf("verdict %v (match %v) at %.4f, want %v", v, m != nil, p.Best().Distance, c.want)
			}
		})
	}
}

// A plain download's DATE is the day it was published where it came from,
// years after the release as a rule: accept-best judges it without the year,
// and the matcher's own score keeps it.
func TestAcceptBestJudgesAnUploadDatedTrackWithoutItsYear(t *testing.T) {
	for _, c := range []struct {
		name        string
		title, date string
		uploadDated bool
		want        BestVerdict
	}{
		{"an upload date five years on", "Song", "2016-03-04", true, BestAcceptable},
		{"an upload date under a split title", "The Band - Song (Official Video)", "2019", true, BestAcceptable},
		{"a release date five years off", "Song", "2016", false, BestBelowFloor},
		{"a release date that agrees", "Song", "2011", false, BestAcceptable},
	} {
		t.Run(c.name, func(t *testing.T) {
			rel := songOn("album", "The Band", "Song", "r1", 200)
			rel.Year = 2011
			u := looseSong("The Band", c.title, 200)
			u.Tracks[0].Tags["DATE"] = c.date
			u.Tracks[0].UploadDated = c.uploadDated
			src := &fakeSource{recordingHits: map[string][]*Release{"": {rel}}}
			p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
			if err != nil {
				t.Fatal(err)
			}
			m, v := p.JudgeBest(Config{})
			if v != c.want || (m != nil) != (c.want == BestAcceptable) {
				t.Fatalf("verdict %v (match %v), want %v", v, m != nil, c.want)
			}
			raw := Score(u, rel, Weights{})
			if p.Best().Distance != raw.Distance {
				t.Fatalf("stored top at %.4f, want the raw score %.4f: the matcher's own ranking keeps the year", p.Best().Distance, raw.Distance)
			}
			if c.date != "2011" && (p.Best().Distance <= Config{}.withDefaults().SinglesAutoApplyThreshold || p.Decision == DecisionAutoApply) {
				t.Fatalf("raw top at %.4f decision %v, want the year still counted by the matcher's own decision", p.Best().Distance, p.Decision)
			}
		})
	}
}

// printedSingle is one file found by its fingerprint, every tag agreeing with
// the release but the title as given.
func printedSingle(fileTitle, listedTitle string) (Unit, *fakeSource) {
	rel := &Release{MBID: "rel-1", ReleaseGroupMBID: "rg-1", Title: "Album", Artist: "Artist", Year: 1894,
		Tracks: []ReleaseTrack{{RecordingMBID: "rec-1", Title: listedTitle, Disc: 1, Position: 1, DurationSec: 700}}}
	u := Unit{Tracks: []Track{{
		PID: "t1", Path: "/lib/x/01.flac", DurationSec: 700, Fingerprint: "fp-1",
		Tags: map[string]string{"ARTIST": "Artist", "ALBUM": "Album", "TITLE": fileTitle, "TRACKNUMBER": "1", "DATE": "1894"},
	}}}
	return u, &fakeSource{
		fingerprints: map[string][]FingerprintHit{"fp-1": {{RecordingMBID: "rec-1", ReleaseGroupMBIDs: []string{"rg-1"}, Score: 1}}},
		groups:       map[string][]*Release{"rg-1": {rel}},
	}
}

// The matcher's own decision for one file reads the distance alone where
// the titles mark no cut: a tag that shortens a movement, leaves an opus
// number out or adds a bonus track, album version, explicit or original mix
// note is the same recording. Accept-best, asked to go past a person, waits
// on every one.
func TestTheMatchersOwnDecisionIgnoresWhatMarksNoCut(t *testing.T) {
	const allegro = "Symphony No. 9 in E minor, Op. 95 \"From the New World\": IV. Allegro con fuoco"
	const sonata = "Piano Sonata No. 14 in C-sharp minor \"Moonlight\": I. Adagio sostenuto"
	for _, c := range []struct{ name, file, listed string }{
		{"a shortened movement", strings.TrimSuffix(allegro, " con fuoco"), allegro},
		{"an opus number left out", sonata, sonata + ", Op. 27"},
		{"a bonus track note", allegro + " [Bonus Track]", allegro},
		{"an album version note", allegro + " (Album Version)", allegro},
		{"an explicit note", allegro + " [Explicit]", allegro},
		{"an explicit note on the listed title", allegro, allegro + " (Explicit)"},
		{"an original mix note", allegro + " (Original Mix)", allegro},
	} {
		t.Run(c.name, func(t *testing.T) {
			u, src := printedSingle(c.file, c.listed)
			p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
			if err != nil {
				t.Fatal(err)
			}
			if p.Decision != DecisionAutoApply {
				t.Fatalf("decision %v at %.4f, want auto-apply: the distance is inside the singles threshold", p.Decision, p.Best().Distance)
			}
			if m, v := p.JudgeBest(Config{}); m != nil || v != BestBelowFloor {
				t.Fatalf("accept-best verdict %v (match %v), want below-floor", v, m != nil)
			}
		})
	}
}

// A release can hold a title twice (mono and stereo, a bonus take under the
// plain title): with nothing but a release search behind the candidates, the
// other track is the rival.
func TestAcceptBestJudgesAnotherTrackOfTheTopsRelease(t *testing.T) {
	for _, c := range []struct {
		name        string
		otherTitle  string
		otherRec    string
		otherDur    float64
		uploadDur   float64
		want        BestVerdict
		wantPairing string
	}{
		{"the same title three seconds on, upload at the first", "Song", "rec-b", 203, 200, BestAmbiguous, ""},
		{"upload between the two", "Song", "rec-b", 203, 202, BestAmbiguous, ""},
		{"upload at the second", "Song", "rec-b", 203, 203, BestAmbiguous, ""},
		{"the same title far longer", "Song", "rec-b", 240, 200, BestAcceptable, "rec-a"},
		{"another title at the length", "Other", "rec-b", 200, 200, BestAcceptable, "rec-a"},
		{"the same recording printed twice", "Song", "rec-a", 200, 200, BestAcceptable, "rec-a"},
	} {
		t.Run(c.name, func(t *testing.T) {
			rel := &Release{MBID: "rel-1", Title: "Album", Artist: "Band", Year: 2001, Tracks: []ReleaseTrack{
				{RecordingMBID: "rec-a", Title: "Song", Disc: 1, Position: 1, DurationSec: 200},
				{RecordingMBID: c.otherRec, Title: c.otherTitle, Disc: 1, Position: 2, DurationSec: c.otherDur},
			}}
			u := Unit{Tracks: []Track{{
				PID: "up-1", Path: "/staging/up-1/Song.opus", DurationSec: c.uploadDur,
				Tags: map[string]string{"ARTIST": "Band", "ALBUM": "Album", "TITLE": "Song", "DATE": "2001"},
			}}}
			src := &fakeSource{searchHits: []*Release{rel}}
			p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
			if err != nil {
				t.Fatal(err)
			}
			if src.recordingCalls != 0 {
				t.Fatalf("%d recording searches, want the release search alone", src.recordingCalls)
			}
			m, v := p.JudgeBest(Config{})
			if v != c.want {
				t.Fatalf("verdict %v, want %v", v, c.want)
			}
			if c.wantPairing != "" && (m == nil || pairedRecordings(m)[0] != c.wantPairing) {
				t.Fatalf("accepted %v, want the pairing with %s", m, c.wantPairing)
			}
		})
	}
}

// The stored candidates stop at the cap whatever accept-best would take: its
// top past the cut is answered by JudgeBest, for the caller that asked.
func TestIdentifyKeepsTheCandidateCap(t *testing.T) {
	hits := []*Release{songOn("album", "The Band", "Song", "r1", 200)}
	for i := range 5 {
		// Closer to the title as tagged than the song itself is.
		hits = append(hits, songOn("decoy-"+itoa(i+1), "The Band", "The Band Song", "d"+itoa(i+1), 200))
	}
	src := &fakeSource{recordingHits: map[string][]*Release{"": hits}}
	p, err := NewEngine(src, Config{}).Identify(context.Background(), looseSong("The Band", "The Band - Song", 200))
	if err != nil {
		t.Fatal(err)
	}
	if len(p.Candidates) != 5 {
		t.Fatalf("stored %d candidates, want the cap of 5", len(p.Candidates))
	}
	if slices.ContainsFunc(p.Candidates, func(m Match) bool { return m.Release.MBID == "album" }) {
		t.Fatal("fixture: the judged top is among the stored five, want it past the cut")
	}
	m, v := p.JudgeBest(Config{})
	if v != BestAcceptable || m == nil || m.Release.MBID != "album" || len(m.Pairings) != 1 {
		t.Fatalf("verdict %v match %v, want the album past the cut, scored on the tags as read", v, m)
	}
	if raw := Score(p.Unit, m.Release, Weights{}); m.Distance != raw.Distance {
		t.Fatalf("accepted match at %.4f, want the raw score %.4f a stored candidate carries", m.Distance, raw.Distance)
	}
}

// A unit naming an album no release search found says so to the recording
// search, which hydrates a release titled as it first.
func TestIdentifyNamesItsAlbumToTheRecordingSearch(t *testing.T) {
	u := unitFor("Band", "Big Hits", "Song")
	src := &fakeSource{recordingHits: map[string][]*Release{"": {songOn("comp", "Band", "Song", "r1", 180)}}}
	if _, err := NewEngine(src, Config{}).Identify(context.Background(), u); err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(src.recordingAlbums, []string{"Big Hits"}) {
		t.Fatalf("recording searches named the albums %q, want [Big Hits]", src.recordingAlbums)
	}
	src = &fakeSource{recordingHits: map[string][]*Release{"": {songOn("comp", "Band", "Song", "r1", 180)}}}
	if _, err := NewEngine(src, Config{}).Identify(context.Background(), looseSong("Band", "Song", 180)); err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(src.recordingAlbums, []string{""}) {
		t.Fatalf("recording searches named the albums %q for a file naming none", src.recordingAlbums)
	}
}

// The matcher's own decision for one file withholds only a cut the titles
// mark (a live take, a remix, a demo, an edit, a clean or 8D cut that one of
// them names): a continuation, a bonus track, album version, explicit or
// original mix note and a remaster note are the distance's to judge.
func TestNamesMarkedCut(t *testing.T) {
	const long = "Nocturne for the Lighthouse Keeper Who Never Saw the Morning Come Ashore"
	for _, c := range []struct {
		judged, listed string
		want           bool
	}{
		{long + " (Live)", long, true},
		{long, long + " (live)", true},
		{long + " (Live 1977)", long + " (Live 1979)", true},
		{long + " (Demo)", long, true},
		{long + " (Clean)", long, true},
		{long + " (8D Audio)", long, true},
		{long + " (X Remix)", long, true},
		{long + " (X Remix)", long + " (Y Remix)", true},
		{long + " (Acoustic)", long, true},
		{long + " (Radio Edit)", long, true},
		{long + " (Extended Mix)", long, true},
		{long + " - Live", long, true},
		{long + " (Live)", long + " - Live", false},
		{long + " (X Remix)", long + " (X remix)", false},
		{long, long, false},
		{long, long + " II", false},
		{long, long + ", Pt. 2", false},
		{long + " (Take 2)", long, false},
		{long + " [Bonus Track]", long, false},
		{long + " (Album Version)", long, false},
		{long + " (Single Version)", long, false},
		// An explicit note and an original mix label the plain recording.
		{long + " (Explicit)", long, false},
		{long + " [Explicit]", long, false},
		{long, long + " (Explicit)", false},
		{long + " - Explicit", long, false},
		{long + " (Explicit Version)", long, false},
		{long + " (Original Mix)", long, false},
		{long + " (Clean)", long + " (Explicit)", true},
		{long + " [Clean]", long, true},
		{long, long + " (2011 Remaster)", false},
		{long, long + " - Remastered 2011", false},
		{long + " (feat. Guest)", long, false},
		{"Symphony No. 9: IV. Allegro", "Symphony No. 9: IV. Allegro con fuoco", false},
	} {
		if got := namesMarkedCut(c.judged, c.listed); got != c.want {
			t.Errorf("namesMarkedCut(%q, %q) = %v, want %v", c.judged, c.listed, got, c.want)
		}
	}
}

// A file titled as another cut than the recording it scores closest to is
// left for a person by the matcher's own decision, however close the
// distance, and by accept-best.
func TestTheMatchersOwnDecisionWithholdsAMarkedCut(t *testing.T) {
	const allegro = "Symphony No. 9 in E minor, Op. 95 \"From the New World\": IV. Allegro con fuoco"
	for _, c := range []struct{ name, file, listed string }{
		{"a live take", allegro + " (Live)", allegro},
		{"another year's live take", allegro + " (Live 1977)", allegro + " (Live 1979)"},
		{"a demo", allegro + " (Demo)", allegro},
	} {
		t.Run(c.name, func(t *testing.T) {
			u, src := printedSingle(c.file, c.listed)
			p, err := NewEngine(src, Config{}).Identify(context.Background(), u)
			if err != nil {
				t.Fatal(err)
			}
			if p.Best().Distance > (Config{}).withDefaults().SinglesAutoApplyThreshold {
				t.Fatalf("fixture: top at %.4f, want it inside the singles threshold", p.Best().Distance)
			}
			if p.Decision != DecisionReview {
				t.Fatalf("decision %v at %.4f, want review", p.Decision, p.Best().Distance)
			}
			if m, v := p.JudgeBest(Config{}); m != nil || v != BestBelowFloor {
				t.Fatalf("accept-best verdict %v (match %v), want below-floor", v, m != nil)
			}
		})
	}
}

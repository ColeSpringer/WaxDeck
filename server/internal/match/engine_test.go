package match

import (
	"context"
	"errors"
	"sort"
	"testing"
)

// fakeSource is a scriptable CandidateSource for engine tests.
type fakeSource struct {
	releases     map[string]*Release
	groups       map[string][]*Release
	fingerprints map[string][]FingerprintHit
	searchHits   []*Release
	// recordingHits keys releases on the "artist\x00title" the engine queries;
	// a bare "" key answers any recording search.
	recordingHits map[string][]*Release

	lookupCalls      int
	searchCalls      int
	recordingCalls   int
	recordingQueries []string
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

func (f *fakeSource) SearchRecordings(_ context.Context, artist, title string) ([]*Release, error) {
	f.recordingCalls++
	f.recordingQueries = append(f.recordingQueries, artist+"\x00"+title)
	if f.failAll {
		return nil, errors.New("provider down")
	}
	if rs, ok := f.recordingHits[artist+"\x00"+title]; ok {
		return rs, nil
	}
	return f.recordingHits[""], nil
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

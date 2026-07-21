package match

import (
	"context"
	"fmt"
	"math/rand"
	"sort"
	"testing"
)

// The evaluation corpus: labeled messy libraries against a canned
// candidate world. It gates the auto apply threshold and the distance
// weights. Precision is absolute (one wrong auto apply fails the suite);
// recall over the cases labeled shouldAuto is a ratcheted floor.

// corpusWorld is the canned provider universe shared by every case.
type corpusWorld struct {
	releases map[string]*Release
	groups   map[string][]*Release
	prints   map[string][]FingerprintHit
}

func (w *corpusWorld) add(r *Release) *Release {
	w.releases[r.MBID] = r
	if r.ReleaseGroupMBID != "" {
		w.groups[r.ReleaseGroupMBID] = append(w.groups[r.ReleaseGroupMBID], r)
	}
	for _, rt := range r.Tracks {
		if rt.RecordingMBID == "" {
			continue
		}
		fp := "fp:" + rt.RecordingMBID
		w.prints[fp] = append(w.prints[fp], FingerprintHit{
			RecordingMBID:     rt.RecordingMBID,
			ReleaseGroupMBIDs: []string{r.ReleaseGroupMBID},
			Score:             0.96,
		})
	}
	return r
}

// worldSource implements CandidateSource over the canned world with a
// naive but honest text search: candidates rank by album title distance
// and artist agreement, top eight returned.
type worldSource struct {
	w           *corpusWorld
	lookupCalls int
}

func (s *worldSource) ReleaseByMBID(_ context.Context, mbid string) (*Release, error) {
	return s.w.releases[mbid], nil
}

func (s *worldSource) ReleasesByGroup(_ context.Context, rg string) ([]*Release, error) {
	return s.w.groups[rg], nil
}

func (s *worldSource) LookupFingerprint(_ context.Context, fp Fingerprint) ([]FingerprintHit, error) {
	s.lookupCalls++
	return s.w.prints[fp.Value], nil
}

func (s *worldSource) SearchReleases(_ context.Context, artist, album string, _ int) ([]*Release, error) {
	type scored struct {
		r *Release
		d float64
	}
	var hits []scored
	for _, r := range s.w.releases {
		d := albumDist(album, r.Title)
		if artist != "" && r.Artist != "" && !r.Compilation {
			d = (d*2 + titleDist(artist, r.Artist)) / 3
		}
		if d < 0.6 {
			hits = append(hits, scored{r, d})
		}
	}
	sort.Slice(hits, func(i, j int) bool {
		if hits[i].d != hits[j].d {
			return hits[i].d < hits[j].d
		}
		return hits[i].r.MBID < hits[j].r.MBID
	})
	out := make([]*Release, 0, 8)
	for _, h := range hits {
		if len(out) == 8 {
			break
		}
		out = append(out, h.r)
	}
	return out, nil
}

// SearchRecordings returns the releases carrying a track whose title matches,
// with artist agreement when both sides name one. It mirrors the recording
// search the real provider runs for loose, albumless tracks.
func (s *worldSource) SearchRecordings(_ context.Context, artist, title string) ([]*Release, error) {
	type scored struct {
		r *Release
		d float64
	}
	var hits []scored
	for _, r := range s.w.releases {
		best := 1.0
		for _, tr := range r.Tracks {
			d := titleDist(title, tr.Title)
			ra := tr.Artist
			if ra == "" {
				ra = r.Artist
			}
			if artist != "" && ra != "" {
				d = (d*2 + titleDist(artist, ra)) / 3
			}
			if d < best {
				best = d
			}
		}
		if best < 0.4 {
			hits = append(hits, scored{r, best})
		}
	}
	sort.Slice(hits, func(i, j int) bool {
		if hits[i].d != hits[j].d {
			return hits[i].d < hits[j].d
		}
		return hits[i].r.MBID < hits[j].r.MBID
	})
	out := make([]*Release, 0, 5)
	for _, h := range hits {
		if len(out) == 5 {
			break
		}
		out = append(out, h.r)
	}
	return out, nil
}

// mkRelease builds a canned release with deterministic durations.
func mkRelease(mbid, rg, artist, title string, year int, titles ...string) *Release {
	r := &Release{
		MBID: mbid, ReleaseGroupMBID: rg, Artist: artist, Title: title, Year: year, Media: 1,
	}
	for i, t := range titles {
		r.Tracks = append(r.Tracks, ReleaseTrack{
			RecordingMBID: mbid + "-rec-" + itoa(i+1),
			Title:         t,
			Disc:          1,
			Position:      i + 1,
			DurationSec:   float64(150 + 17*i + len(t)),
		})
	}
	return r
}

func buildWorld() *corpusWorld {
	w := &corpusWorld{
		releases: map[string]*Release{},
		groups:   map[string][]*Release{},
		prints:   map[string][]FingerprintHit{},
	}

	w.add(mkRelease("rel-neon", "rg-neon", "The Cardinal Waves", "Neon Meridian", 2011,
		"Signal Fires", "Glass Coast", "Meridian", "Undertow", "Paper Lanterns",
		"Northern Static", "Half Light", "The Long Pier", "Salt and Circuitry", "Afterglow"))
	deluxe := mkRelease("rel-neon-dx", "rg-neon", "The Cardinal Waves", "Neon Meridian (Deluxe Edition)", 2012,
		"Signal Fires", "Glass Coast", "Meridian", "Undertow", "Paper Lanterns",
		"Northern Static", "Half Light", "The Long Pier", "Salt and Circuitry", "Afterglow",
		"Signal Fires (Demo)", "Meridian (Live)")
	// Deluxe reuses the standard recordings for the shared tracks.
	for i := 0; i < 10; i++ {
		deluxe.Tracks[i].RecordingMBID = "rel-neon-rec-" + itoa(i+1)
	}
	w.add(deluxe)
	w.add(mkRelease("rel-live", "rg-live", "The Cardinal Waves", "Live at Greyfield", 2013,
		"Signal Fires (Live)", "Glass Coast (Live)", "Undertow (Live)", "Half Light (Live)",
		"The Long Pier (Live)", "Afterglow (Live)", "Encore Jam", "Greyfield Goodnight"))
	w.add(mkRelease("rel-hollow", "rg-hollow", "Marrow and Pine", "Hollow Harbor", 2018,
		"Driftwood", "Cartographer", "Low Tide Hymn", "The Anchorage", "Foglines",
		"Second Winter", "Harbor Lights", "Wooden Bones", "Last Ferry Out"))
	w.add(mkRelease("rel-lantern", "rg-lantern", "Marrow and Pine", "Winter Lanterns EP", 2016,
		"Winter Lanterns", "Snowfield", "The Quiet Year", "Ember Days", "White Pines"))
	w.add(mkRelease("rel-salt-hollow", "rg-salt-hollow", "The Salt Collective", "Hollow Harbor", 2009,
		"Rust and Rope", "The Breakwater", "Ninth Wave", "Gullsong", "Ballast",
		"Mooring", "Tidewrack", "Old Harbor Bell", "Come About"))
	va := mkRelease("rel-nowthat", "rg-nowthat", "Various Artists", "Now That Is Noise 7", 2004,
		"Bubblegum Sunrise", "Motorway Heart", "Clocktower", "Dance Alone Together",
		"Radio Ghost", "Sugar Static", "Neon Rain", "Last Summer Anthem",
		"Midnight Arcade", "Tiny Revolutions", "Gold Chrome", "Fade Out Forever")
	va.Compilation = true
	vaArtists := []string{
		"The Prisms", "Motor City Echo", "Bellhaven", "Disco Antler", "Ghostradio",
		"Sugarcane Riot", "Neon Palms", "The Anthem Society", "Arcade Youth",
		"Tiny Rebellion", "Chromatique", "The Fadeaways",
	}
	for i := range va.Tracks {
		va.Tracks[i].Artist = vaArtists[i]
	}
	w.add(va)
	w.add(mkRelease("rel-symphony", "rg-symphony", "Anna Vestergaard", "Symphony No. 3 in D minor", 2007,
		"Symphony No. 3 in D minor: I. Kraftig. Entschieden",
		"Symphony No. 3 in D minor: II. Tempo di Menuetto",
		"Symphony No. 3 in D minor: III. Comodo. Scherzando",
		"Symphony No. 3 in D minor: IV. Sehr langsam. Misterioso",
		"Symphony No. 3 in D minor: V. Lustig im Tempo",
		"Symphony No. 3 in D minor: VI. Langsam. Ruhevoll. Empfunden"))
	w.add(mkRelease("rel-tokyo", "rg-tokyo", "灰色クラブ", "東京の夜", 2020,
		"始発列車", "ネオンの雨", "静かな部屋", "午前三時", "さよならのかわりに"))
	// Search noise: nearby but wrong answers.
	w.add(mkRelease("rel-noise-1", "rg-noise-1", "The Cardinal Waves", "Neon Meridian Remixed", 2013,
		"Signal Fires (Rework)", "Meridian (Club Edit)", "Undertow (Dub)", "Afterglow (Slowed)"))
	w.add(mkRelease("rel-noise-2", "rg-noise-2", "Cardinal Sin", "Neon Nights", 1999,
		"Neon Nights", "Velvet Rope", "City Limits", "Wasted Dawn"))
	return w
}

// ripRelease turns a release into a perfect set of files, which case
// mutators then mess up.
func ripRelease(r *Release, dir string) []Track {
	var tracks []Track
	for i, rt := range r.Tracks {
		artist := rt.Artist
		if artist == "" {
			artist = r.Artist
		}
		tracks = append(tracks, Track{
			PID:  fmt.Sprintf("%s-%02d", r.MBID, i+1),
			Path: fmt.Sprintf("%s/%02d - %s.flac", dir, i+1, rt.Title),
			Tags: map[string]string{
				"TITLE": rt.Title, "ARTIST": artist, "ALBUM": r.Title,
				"ALBUMARTIST": r.Artist, "TRACKNUMBER": itoa(rt.Position),
				"DATE": itoa4(r.Year),
			},
			DurationSec: rt.DurationSec,
			Fingerprint: "fp:" + rt.RecordingMBID,
		})
	}
	return tracks
}

func itoa4(n int) string { return fmt.Sprintf("%d", n) }

type mutator func([]Track) []Track

func dropTags(keys ...string) mutator {
	return func(ts []Track) []Track {
		for i := range ts {
			for _, k := range keys {
				delete(ts[i].Tags, k)
			}
		}
		return ts
	}
}

func dropFingerprints(ts []Track) []Track {
	for i := range ts {
		ts[i].Fingerprint = ""
	}
	return ts
}

func untagged(ts []Track) []Track {
	for i := range ts {
		ts[i].Tags = map[string]string{}
	}
	return ts
}

func setTag(key, value string) mutator {
	return func(ts []Track) []Track {
		for i := range ts {
			ts[i].Tags[key] = value
		}
		return ts
	}
}

func shuffleFiles(seed int64) mutator {
	return func(ts []Track) []Track {
		rng := rand.New(rand.NewSource(seed))
		rng.Shuffle(len(ts), func(i, j int) { ts[i], ts[j] = ts[j], ts[i] })
		// Renumber sequentially so the numbers now lie about order.
		for i := range ts {
			ts[i].Tags["TRACKNUMBER"] = itoa(i + 1)
		}
		return ts
	}
}

func dropTracks(idx ...int) mutator {
	return func(ts []Track) []Track {
		drop := map[int]bool{}
		for _, i := range idx {
			drop[i] = true
		}
		var out []Track
		for i, t := range ts {
			if !drop[i] {
				out = append(out, t)
			}
		}
		return out
	}
}

func addJunkTrack(title string) mutator {
	return func(ts []Track) []Track {
		album := ts[0].Tags["ALBUM"]
		artist := ts[0].Tags["ARTIST"]
		return append(ts, Track{
			PID:  "junk-" + title,
			Path: fmt.Sprintf("/rip/junk/%s.mp3", title),
			Tags: map[string]string{
				"TITLE": title, "ARTIST": artist, "ALBUM": album,
				"TRACKNUMBER": itoa(len(ts) + 1),
			},
			DurationSec: 214,
		})
	}
}

type evalCase struct {
	name  string
	files []Track
	// shouldAuto cases count toward the recall floor; mustNotAuto cases
	// fail the suite if they auto apply at all.
	shouldAuto  bool
	mustNotAuto bool
	// wantTop is the release the top candidate must be whenever any
	// candidates exist ("" skips the check).
	wantTop string
	// wantUnits asserts the clustering shape (0 skips).
	wantUnits int
}

func corpusCases(w *corpusWorld) []evalCase {
	neon := w.releases["rel-neon"]
	deluxe := w.releases["rel-neon-dx"]
	hollow := w.releases["rel-hollow"]
	saltHollow := w.releases["rel-salt-hollow"]
	va := w.releases["rel-nowthat"]
	symphony := w.releases["rel-symphony"]
	tokyo := w.releases["rel-tokyo"]

	apply := func(ts []Track, ms ...mutator) []Track {
		for _, m := range ms {
			ts = m(ts)
		}
		return ts
	}

	return []evalCase{
		{
			name:       "clean tags",
			files:      apply(ripRelease(neon, "/rip/neon"), dropFingerprints),
			shouldAuto: true, wantTop: "rel-neon", wantUnits: 1,
		},
		{
			name:       "tagged release mbid",
			files:      apply(ripRelease(neon, "/rip/neon"), dropFingerprints, setTag("MUSICBRAINZ_ALBUMID", "rel-neon")),
			shouldAuto: true, wantTop: "rel-neon",
		},
		{
			name: "misspelled album and artist",
			files: apply(ripRelease(neon, "/rip/neon"), dropFingerprints,
				setTag("ALBUM", "Neon Meridien"), setTag("ALBUMARTIST", "Cardinal Waves"), setTag("ARTIST", "Cardinal Waves")),
			shouldAuto: true, wantTop: "rel-neon",
		},
		{
			name:       "missing track numbers",
			files:      apply(ripRelease(neon, "/rip/neon"), dropFingerprints, dropTags("TRACKNUMBER")),
			shouldAuto: true, wantTop: "rel-neon",
		},
		{
			name:       "shuffled files with lying numbers",
			files:      apply(ripRelease(neon, "/rip/neon"), dropFingerprints, shuffleFiles(11)),
			shouldAuto: true, wantTop: "rel-neon",
		},
		{
			name:       "deluxe rip picks deluxe",
			files:      apply(ripRelease(deluxe, "/rip/neondx"), dropFingerprints, setTag("ALBUM", "Neon Meridian")),
			shouldAuto: true, wantTop: "rel-neon-dx",
		},
		{
			name:    "standard rip tagged deluxe picks standard",
			files:   apply(ripRelease(neon, "/rip/neon"), dropFingerprints, setTag("ALBUM", "Neon Meridian (Deluxe Edition)")),
			wantTop: "rel-neon",
		},
		{
			name:       "untagged with fingerprints",
			files:      apply(ripRelease(neon, "/rip/untagged"), untagged),
			shouldAuto: true, wantTop: "rel-neon", wantUnits: 1,
		},
		{
			name:        "untagged no fingerprints",
			files:       apply(ripRelease(neon, "/rip/untagged"), untagged, dropFingerprints),
			mustNotAuto: true,
		},
		{
			name:       "compilation with per track artists",
			files:      apply(ripRelease(va, "/rip/nowthat"), dropFingerprints, dropTags("ALBUMARTIST")),
			shouldAuto: true, wantTop: "rel-nowthat", wantUnits: 1,
		},
		{
			name:       "classical multi movement stays one unit",
			files:      apply(ripRelease(symphony, "/rip/symphony"), dropFingerprints),
			shouldAuto: true, wantTop: "rel-symphony", wantUnits: 1,
		},
		{
			name: "live bootleg must not auto apply",
			files: func() []Track {
				var ts []Track
				titles := []string{"Intro (Red Rocks)", "Signal Fires", "Glass Coast", "New Song (Untitled)",
					"Undertow", "Banter", "Meridian", "Afterglow", "Outro Jam"}
				for i, title := range titles {
					ts = append(ts, Track{
						PID:  "boot-" + itoa(i+1),
						Path: fmt.Sprintf("/rip/bootleg/%02d %s.mp3", i+1, title),
						Tags: map[string]string{
							"TITLE": title, "ARTIST": "The Cardinal Waves",
							"ALBUM": "Live at Red Rocks 2019", "TRACKNUMBER": itoa(i + 1),
						},
						DurationSec: float64(200 + 31*i),
					})
				}
				return ts
			}(),
			mustNotAuto: true,
		},
		{
			name: "wrong mbid tag recovers by evidence",
			files: apply(ripRelease(neon, "/rip/neon"), dropFingerprints,
				setTag("MUSICBRAINZ_ALBUMID", "rel-hollow")),
			wantTop: "rel-neon", shouldAuto: true,
		},
		{
			name:       "same album title different artist",
			files:      apply(ripRelease(saltHollow, "/rip/salthollow"), dropFingerprints),
			shouldAuto: true, wantTop: "rel-salt-hollow",
		},
		{
			name:       "extra junk track",
			files:      apply(ripRelease(neon, "/rip/neon"), dropFingerprints, addJunkTrack("Hidden Track")),
			wantTop:    "rel-neon",
			shouldAuto: false,
		},
		{
			name:        "half an album goes to review",
			files:       apply(ripRelease(hollow, "/rip/hollow"), dropFingerprints, dropTracks(4, 5, 6, 7, 8)),
			mustNotAuto: true, wantTop: "rel-hollow",
		},
		{
			name:       "non latin exact tags",
			files:      apply(ripRelease(tokyo, "/rip/tokyo"), dropFingerprints),
			shouldAuto: true, wantTop: "rel-tokyo",
		},
		{
			name: "fingerprint consensus with junk tags",
			files: apply(ripRelease(neon, "/rip/neon"),
				setTag("ALBUM", "Downloaded Music 2024"), setTag("ARTIST", "Unknown Artist"),
				setTag("ALBUMARTIST", ""), dropTags("ALBUMARTIST", "DATE")),
			wantTop: "rel-neon", mustNotAuto: false,
		},
	}
}

func TestEvalCorpus(t *testing.T) {
	world := buildWorld()
	var (
		autoRight, autoWrong int
		shouldAutoTotal      int
		shouldAutoHit        int
	)
	for _, c := range corpusCases(world) {
		t.Run(c.name, func(t *testing.T) {
			src := &worldSource{w: world}
			units := Cluster(c.files)
			if c.wantUnits > 0 && len(units) != c.wantUnits {
				t.Fatalf("clustered into %d units, want %d", len(units), c.wantUnits)
			}
			if len(units) != 1 {
				// Every corpus case is a single album worth of files.
				t.Fatalf("corpus case must cluster to one unit, got %d", len(units))
			}
			p, err := NewEngine(src, Config{}).Identify(context.Background(), units[0])
			if err != nil {
				t.Fatal(err)
			}
			if c.wantTop != "" {
				if p.Best() == nil {
					t.Fatalf("no candidates, want top %s", c.wantTop)
				}
				if got := p.Best().Release.MBID; got != c.wantTop {
					t.Errorf("top candidate %s (distance %.3f), want %s", got, p.Best().Distance, c.wantTop)
				}
			}
			if c.mustNotAuto && p.Decision == DecisionAutoApply {
				t.Errorf("must not auto apply, but did (top %s at %.3f)",
					p.Best().Release.MBID, p.Best().Distance)
			}
			if p.Decision == DecisionAutoApply {
				if c.wantTop != "" && p.Best().Release.MBID == c.wantTop {
					autoRight++
				} else if c.wantTop != "" {
					autoWrong++
				}
			}
			if c.shouldAuto {
				shouldAutoTotal++
				if p.Decision == DecisionAutoApply && p.Best().Release.MBID == c.wantTop {
					shouldAutoHit++
				} else {
					t.Logf("labeled shouldAuto but got %v (best %v at %.3f)",
						p.Decision, bestMBID(p), bestDistance(p))
				}
			}
		})
	}
	// Precision is absolute: a wrong auto apply is the one unforgivable
	// outcome.
	if autoWrong > 0 {
		t.Fatalf("%d wrong auto applies (precision %.2f)", autoWrong,
			float64(autoRight)/float64(autoRight+autoWrong))
	}
	// Recall floor, ratcheted as the corpus and weights improve.
	const recallFloor = 0.85
	recall := float64(shouldAutoHit) / float64(shouldAutoTotal)
	t.Logf("corpus recall %.2f (%d of %d shouldAuto cases)", recall, shouldAutoHit, shouldAutoTotal)
	if recall < recallFloor {
		t.Fatalf("recall %.2f below floor %.2f", recall, recallFloor)
	}
}

func bestMBID(p *Proposal) string {
	if p.Best() == nil {
		return "none"
	}
	return p.Best().Release.MBID
}

func bestDistance(p *Proposal) float64 {
	if p.Best() == nil {
		return 1
	}
	return p.Best().Distance
}

package match

import (
	"context"
	"fmt"
	"math"
	"math/rand"
	"slices"
	"sort"
	"strings"
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
// and artist agreement, top eight returned. Like the provider's, its artist
// clause reads the release's own credit, so a compilation answers only a
// search naming no artist or Various Artists.
type worldSource struct {
	w           *corpusWorld
	lookupCalls int
	flipTies    bool
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
		if d > 0.5 || (artist != "" && r.Compilation && normalize(artist) != "various artists") {
			continue
		}
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

// SearchRecordings mirrors the provider's recording search: the recordings
// whose title (and artist, when both sides name one) match rank like search
// hits with a score, a page of RecordingSearchPage listed with title, artist,
// length and score, and whether more were counted; each lists the releases
// carrying it, plain releases before compilations, and the first under each
// album title; and SpreadReleases picks what is hydrated, as the provider
// does. The match is fuzzier than the
// provider's phrase (a near title is listed, the harsher test), and like the
// phrase it lists every title holding the words asked for, however much else
// the title holds. A title holding named's words as well is boosted as the
// provider's second phrase boosts it: it ranks above every hit that does not,
// and scores are relative to the best hit, so the others' fall to a quarter.
// Hits that tie keep the index's order, which nothing promises, so flipTies
// reverses it.
func (s *worldSource) SearchRecordings(_ context.Context, artist, title, named, album string) (RecordingSearch, error) {
	type hit struct {
		listed   ListedRecording
		d        float64
		boosted  bool
		releases []*Release
	}
	byRec := map[string]*hit{}
	for _, r := range s.w.releases {
		for _, tr := range r.Tracks {
			if tr.RecordingMBID == "" {
				continue
			}
			d := titleDist(title, tr.Title)
			if holdsPhrase(tr.Title, title) {
				d = min(d, 0.39)
			}
			ra := tr.Artist
			if ra == "" {
				ra = r.Artist
			}
			if artist != "" && ra != "" {
				d = (d*2 + titleDist(artist, ra)) / 3
			}
			h := byRec[tr.RecordingMBID]
			if h == nil || d < h.d {
				if h == nil {
					h = &hit{d: d}
					byRec[tr.RecordingMBID] = h
				}
				h.d = d
				h.boosted = named != "" && holdsPhrase(tr.Title, named)
				h.listed = ListedRecording{MBID: tr.RecordingMBID, Title: tr.Title, Artist: ra, DurationSec: tr.DurationSec}
			}
			if !slices.Contains(h.releases, r) {
				h.releases = append(h.releases, r)
			}
		}
	}
	var hits []*hit
	anyBoosted := false
	for _, h := range byRec {
		if h.d < 0.4 {
			hits = append(hits, h)
			anyBoosted = anyBoosted || h.boosted
		}
	}
	sort.Slice(hits, func(i, j int) bool {
		if hits[i].boosted != hits[j].boosted {
			return hits[i].boosted
		}
		if hits[i].d != hits[j].d {
			return hits[i].d < hits[j].d
		}
		return (hits[i].listed.MBID < hits[j].listed.MBID) != s.flipTies
	})
	var res RecordingSearch
	if len(hits) > RecordingSearchPage {
		hits, res.Unlisted = hits[:RecordingSearchPage], true
	}
	ids := make([]SearchHit, len(hits))
	listedReleases := map[string]bool{}
	for i, h := range hits {
		l := h.listed
		l.Score = int(math.Round(100 * (1 - h.d)))
		if anyBoosted && !h.boosted {
			l.Score = int(math.Round(25 * (1 - h.d)))
		} else if h.boosted {
			l.Score = 100
		}
		res.Listed = append(res.Listed, l)
		sort.Slice(h.releases, func(a, b int) bool {
			ra, rb := h.releases[a], h.releases[b]
			if ra.Compilation != rb.Compilation {
				return !ra.Compilation
			}
			return ra.MBID < rb.MBID
		})
		ids[i].Title, ids[i].Albums = l.Title, map[string]string{}
		for _, r := range h.releases {
			ids[i].Releases = append(ids[i].Releases, r.MBID)
			listedReleases[r.MBID] = true
			if key := AlbumKey(r.Title); ids[i].Albums[key] == "" {
				ids[i].Albums[key] = r.MBID
			}
		}
	}
	picked := SpreadReleases(ids, named, album)
	res.Capped = len(listedReleases) > len(picked)
	for _, id := range picked {
		res.Releases = append(res.Releases, s.w.releases[id])
	}
	return res, nil
}

// holdsPhrase reports whether title holds phrase's words as one run.
func holdsPhrase(title, phrase string) bool {
	tw, pw := strings.Fields(normalize(title)), strings.Fields(normalize(phrase))
	for i := 0; len(pw) > 0 && i+len(pw) <= len(tw); i++ {
		if slices.Equal(tw[i:i+len(pw)], pw) {
			return true
		}
	}
	return false
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
	// MusicBrainz titles a live take as the song (the difference is in the
	// disambiguation), and a live take runs longer than the studio cut.
	live := mkRelease("rel-live", "rg-live", "The Cardinal Waves", "Live at Greyfield", 2013,
		"Signal Fires", "Glass Coast", "Undertow", "Half Light",
		"The Long Pier", "Afterglow", "Encore Jam", "Greyfield Goodnight")
	for i := range live.Tracks {
		live.Tracks[i].DurationSec += 40
	}
	w.add(live)
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
	// A compilation carrying a standard-release recording: the shared
	// print is what makes a lone acquired track's candidates near-tie
	// across the album and the compilation.
	anthems := mkRelease("rel-anthems", "rg-anthems", "Various Artists", "Big Hits of 2011", 2011,
		"Signal Fires", "Motor Chrome", "Gold Winter")
	anthems.Compilation = true
	anthems.Tracks[0].RecordingMBID = "rel-neon-rec-1"
	anthems.Tracks[0].Artist = "The Cardinal Waves"
	w.add(anthems)
	// Another band's cover of a standard-release song: the same title on a
	// different recording, which a lone acquired track must not be taken
	// as unless its artist says so.
	cover := mkRelease("rel-cover-signal", "rg-cover-signal", "The Salt Collective", "Signal Fires", 2015,
		"Signal Fires")
	cover.Tracks[0].DurationSec = 191
	w.add(cover)
	// The band's own re-recording of a standard-release song under the
	// same title, a few seconds longer: a different recording a lone file
	// can barely be told from the original by.
	rerecord := mkRelease("rel-glass-2020", "rg-glass-2020", "The Cardinal Waves", "Glass Coast (2020)", 2020,
		"Glass Coast")
	rerecord.Tracks[0].DurationSec = w.releases["rel-neon"].Tracks[1].DurationSec + 5
	w.add(rerecord)
	// Popular recordings sit on more releases than a recording search keeps:
	// singles and compilations carrying the original and the re-recording.
	// Group ids sort past rg-neon so a lone print's three voted groups still
	// reach the album.
	neon := w.releases["rel-neon"]
	carry := func(mbid, rg, title string, year int, from *Release, track int, comp bool) {
		r := mkRelease(mbid, rg, from.Artist, title, year, from.Tracks[track].Title)
		r.Tracks[0].RecordingMBID = from.Tracks[track].RecordingMBID
		r.Tracks[0].DurationSec = from.Tracks[track].DurationSec
		if comp {
			r.Artist, r.Compilation = "Various Artists", true
			r.Tracks[0].Artist = from.Artist
		}
		w.add(r)
	}
	carry("rel-signal-single", "rg-signal-single", "Signal Fires", 2011, neon, 0, false)
	carry("rel-sunset-anthems", "rg-sunset-anthems", "Sunset Anthems", 2014, neon, 0, true)
	carry("rel-tidal-drive", "rg-tidal-drive", "Tidal Drive", 2016, neon, 0, true)
	carry("rel-shore-hits", "rg-shore-hits", "Shoreline Hits", 2013, neon, 1, true)
	carry("rel-summer-indie", "rg-summer-indie", "Summer Indie", 2012, neon, 1, true)
	carry("rel-glass-single", "rg-glass-single", "Glass Coast", 2011, neon, 1, false)
	carry("rel-y2020-best", "rg-y2020-best", "Best of 2020", 2020, rerecord, 0, true)
	carry("rel-y2021-chill", "rg-y2021-chill", "Chill Indie 2021", 2021, rerecord, 0, true)
	carry("rel-y2021-drive", "rg-y2021-drive", "Night Drive 2021", 2021, rerecord, 0, true)
	carry("rel-y2022-coast", "rg-y2022-coast", "Coastal 2022", 2022, rerecord, 0, true)
	// More recordings titled "Undertow" than a recording search hydrates,
	// tied at the same score, one a session two seconds off the studio cut:
	// in one index order the studio recording falls past the hydrated hits.
	for _, r := range []struct {
		mbid, title string
		year        int
		dur         float64
	}{
		{"rel-acoustic", "Acoustic Sessions", 2016, 251},
		{"rel-bbc-session", "BBC Sessions", 2012, 211},
		{"rel-demos", "Early Demos", 2009, 188},
		{"rel-lisbon", "Live in Lisbon", 2015, 236},
	} {
		rel := mkRelease(r.mbid, "rg-"+strings.TrimPrefix(r.mbid, "rel-"), "The Cardinal Waves", r.title, r.year, "Undertow")
		rel.Tracks[0].DurationSec = r.dur
		w.add(rel)
	}
	// More recordings titled "Foglines" than a recording search lists, tied
	// at the same score: a session three seconds off the studio cut, and a
	// hundred takes half a minute or more from both. In one index order the
	// studio cut falls past the listed page, in the other the session does.
	session := mkRelease("rel-a-fog-session", "rg-a-fog-session", "Marrow and Pine", "Harbor Sessions", 2019, "Foglines")
	session.Tracks[0].DurationSec = w.releases["rel-hollow"].Tracks[4].DurationSec + 3
	w.add(session)
	titles := make([]string, 100)
	for i := range titles {
		titles[i] = "Foglines"
	}
	takes := mkRelease("rel-fog-takes", "rg-fog-takes", "Marrow and Pine", "Every Take", 2021, titles...)
	for i := range takes.Tracks {
		takes.Tracks[i].DurationSec = w.releases["rel-hollow"].Tracks[4].DurationSec + 30 + float64(i)
	}
	w.add(takes)
	// A song as a search for its plain title lists it: a dozen recordings
	// titled "Lowlight" (the studio cut and eleven takes, tied), then the
	// remix titled with its group, past what a spread over the first hits
	// reads. The real page for "Hallelujah" by Jeff Buckley is this shape:
	// 38 plain titles before five "Hallelujah (live)".
	studio := mkRelease("rel-lowlight", "rg-lowlight", "Petrel and Finch", "Lowlight", 2017, "Lowlight")
	studio.Tracks[0].DurationSec = 200
	w.add(studio)
	titles = make([]string, 11)
	for i := range titles {
		titles[i] = "Lowlight"
	}
	lowTakes := mkRelease("rel-lowlight-takes", "rg-lowlight-takes", "Petrel and Finch", "Lowlight: The Takes", 2019, titles...)
	for i := range lowTakes.Tracks {
		lowTakes.Tracks[i].DurationSec = 240 + 10*float64(i)
	}
	w.add(lowTakes)
	remix := mkRelease("rel-lowlight-remix", "rg-lowlight-remix", "Petrel and Finch", "Lowlight (Harbor Remix)", 2018, "Lowlight (Harbor Remix)")
	remix.Tracks[0].DurationSec = 215
	w.add(remix)
	// A recording titled with its guest, as older MusicBrainz data titles
	// one: the search keeps a guest group, so this is what an upload naming
	// a live take or a remix of it after the guest reaches.
	guest := mkRelease("rel-kestrel", "rg-kestrel", "Petrel and Finch", "Kestrel Road", 2018, "Kestrel Road (feat. Ines Calder)")
	guest.Tracks[0].DurationSec = 200
	w.add(guest)
	// A song with more plain-titled recordings than a search lists: the
	// studio cut and 104 takes titled "Saltwater", tied, then a remix and a
	// live take titled with their groups, past the page of the plain title.
	// The real page for "Yesterday" by The Beatles counts 222.
	salt := mkRelease("rel-saltwater", "rg-saltwater", "Halden Row", "Saltwater", 2014, "Saltwater")
	salt.Tracks[0].DurationSec = 200
	w.add(salt)
	titles = make([]string, 104)
	for i := range titles {
		titles[i] = "Saltwater"
	}
	saltTakes := mkRelease("rel-saltwater-takes", "rg-saltwater-takes", "Halden Row", "Saltwater: Every Night of the Tour", 2016, titles...)
	for i := range saltTakes.Tracks {
		saltTakes.Tracks[i].DurationSec = 240 + float64(i)
	}
	w.add(saltTakes)
	saltRemix := mkRelease("rel-saltwater-remix", "rg-saltwater-remix", "Halden Row", "Saltwater (Dune Remix)", 2015, "Saltwater (Dune Remix)")
	saltRemix.Tracks[0].DurationSec = 228
	w.add(saltRemix)
	saltPier := mkRelease("rel-saltwater-pier", "rg-saltwater-pier", "Halden Row", "Live at the Pier", 2017, "Saltwater (Live at the Pier)")
	saltPier.Tracks[0].DurationSec = 262
	w.add(saltPier)
	// A title long enough that edit distance barely notices a group added to
	// it, and a live take of it titled with its year.
	nocturne := mkRelease("rel-nocturne", "rg-nocturne", "Orrin Vale", "Lighthouse Nocturnes", 2015, longTitle)
	nocturne.Tracks[0].DurationSec = 300
	w.add(nocturne)
	nocturneLive := mkRelease("rel-nocturne-1979", "rg-nocturne-1979", "Orrin Vale", "The 1979 Broadcast", 2019, longTitle+" (Live 1979)")
	nocturneLive.Tracks[0].DurationSec = 341
	w.add(nocturneLive)
	// A release printing one title twice, the mono and the stereo cut a few
	// seconds apart: nothing but the length tells them apart.
	twice := mkRelease("rel-paper-boats", "rg-paper-boats", "Quill and Ember", "Paper Boats", 1967, "Paper Boats", "Paper Boats")
	twice.Tracks[0].DurationSec, twice.Tracks[1].DurationSec = 200, 203
	w.add(twice)
	return w
}

// longTitle is 72 letters and spaces: a "(Live)" added to it is 5 edits in 77.
const longTitle = "Nocturne for the Lighthouse Keeper Who Never Saw the Morning Come Ashore"

func init() {
	if n := len(normalize(longTitle)); n < 60 {
		panic(fmt.Sprintf("longTitle normalizes to %d characters, want one long enough to dilute a group", n))
	}
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

// keepTracks keeps only the named indexes, so a case about unit shape
// stays that shape when a release in the world gains a track.
func keepTracks(idx ...int) mutator {
	return func(ts []Track) []Track {
		var out []Track
		for _, i := range idx {
			out = append(out, ts[i])
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
			// One tagged file: no missing penalty for the eight tracks
			// it never asked for, so the right release is reachable.
			name:       "single file with clean tags",
			files:      apply(ripRelease(hollow, "/rip/hollow"), dropFingerprints, keepTracks(1)),
			shouldAuto: true, wantTop: "rel-hollow", wantUnits: 1,
		},
		{
			// One untagged file whose print sits on the album, its
			// deluxe, and a compilation: an exact three-way tie the
			// preference must break toward the plain album.
			name:       "single acquired file prefers the plain release",
			files:      apply(ripRelease(neon, "/rip/loose"), untagged, keepTracks(0)),
			shouldAuto: true, wantTop: "rel-neon", wantUnits: 1,
		},
		{
			// The same lone file with one field arguing (a wrong year):
			// close enough for an album, not for a single. Pins the
			// stricter threshold inside the precision suite.
			name: "single with a wrong year stays queued",
			files: apply(ripRelease(hollow, "/rip/hollow"), dropFingerprints, keepTracks(1),
				setTag("DATE", "2010")),
			mustNotAuto: true, wantTop: "rel-hollow", wantUnits: 1,
		},
		{
			// A search asks for the song alone, so a live upload reaches
			// the studio recording; on a long title the group it adds is a
			// few edits in dozens, inside the singles threshold.
			name: "single live take of a long title at the studio length",
			files: acquiredTrack("corpus-long-live", 300, map[string]string{
				"ARTIST": "Orrin Vale", "TITLE": longTitle + " (Live)",
			}),
			mustNotAuto: true, wantUnits: 1,
		},
		{
			name: "single clean cut of a long title at the studio length",
			files: acquiredTrack("corpus-long-clean", 300, map[string]string{
				"ARTIST": "Orrin Vale", "TITLE": "Orrin Vale - " + longTitle + " (Clean)",
			}),
			mustNotAuto: true, wantUnits: 1,
		},
		{
			name: "single live take of another year of a long title",
			files: acquiredTrack("corpus-long-1977", 341, map[string]string{
				"ARTIST": "Orrin Vale", "TITLE": longTitle + " (Live 1977)",
			}),
			mustNotAuto: true, wantUnits: 1,
		},
		{
			name: "single live take of a movement at the studio length",
			files: acquiredTrack("corpus-movement-live", symphony.Tracks[3].DurationSec, map[string]string{
				"ARTIST": "Anna Vestergaard", "TITLE": symphony.Tracks[3].Title + " (Live)",
			}),
			mustNotAuto: true, wantUnits: 1,
		},
		{
			// The compilation is credited to Various Artists, so the release
			// search for the track's artist finds nothing and the recording
			// search has to bring it.
			name: "single tagged with the compilation it came from",
			files: uploadedTrack("corpus-compilation", neon.Tracks[0].DurationSec, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires", "ALBUM": "Sunset Anthems",
				"TRACKNUMBER": "1", "DATE": "2014",
			}),
			shouldAuto: true, wantTop: "rel-sunset-anthems", wantUnits: 1,
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

// acquiredTrack is one downloaded file as the matcher sees it after the
// providers' tag pass: the uploader as ARTIST, the video title cleaned of
// upload notes (never split), and whatever an Art Track description added.
// Only a description names an album, and it dates the file by its release or
// not at all, so a DATE beside no ALBUM is the upload's, as the service marks
// it.
func acquiredTrack(name string, durationSec float64, tags map[string]string) []Track {
	return []Track{{
		PID:         "acq-" + name,
		Path:        "/staging/acq-" + name + "/" + tags["TITLE"] + ".opus",
		Tags:        tags,
		DurationSec: durationSec,
		UploadDated: tags["DATE"] != "" && tags["ALBUM"] == "",
	}}
}

// uploadedTrack is one uploaded file: its tags as they are, its date a
// release date.
func uploadedTrack(name string, durationSec float64, tags map[string]string) []Track {
	ts := acquiredTrack(name, durationSec, tags)
	ts[0].UploadDated = false
	return ts
}

// acceptCase is one unit under accept-best: wantRecording is the recording
// a correct accept names for a single ("" with noAccept when the world
// holds no right answer); album cases reuse the corpus's wantTop.
type acceptCase struct {
	name          string
	files         []Track
	wantRecording string
	wantTop       string
	noAccept      bool
	// shouldAccept counts toward the accepted floor.
	shouldAccept bool
}

func acquisitionCases() []acceptCase {
	const signalFires = "rel-neon-rec-1"
	const driftwood = "rel-hollow-rec-1"
	const glassCoast = "rel-neon-rec-2"
	return []acceptCase{
		{
			name: "topic channel art track",
			files: acquiredTrack("topic-art", 162.4, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires",
				"ALBUM": "Neon Meridian", "DATE": "2011",
			}),
			wantRecording: signalFires, shouldAccept: true,
		},
		{
			name: "topic channel with a clean title and the upload year",
			files: acquiredTrack("topic-plain", 163, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires", "DATE": "2019",
			}),
			wantRecording: signalFires, shouldAccept: true,
		},
		{
			name: "topic channel with a clean title and no date",
			files: acquiredTrack("topic-nodate", 161.5, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires",
			}),
			wantRecording: signalFires, shouldAccept: true,
		},
		{
			name: "art track dated by a reissue",
			files: acquiredTrack("topic-reissue", 162.4, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires",
				"ALBUM": "Neon Meridian", "DATE": "2012",
			}),
			wantRecording: signalFires, shouldAccept: true,
		},
		{
			name: "topic channel a few seconds long",
			files: acquiredTrack("topic-long", 166, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires",
			}),
			wantRecording: signalFires, shouldAccept: true,
		},
		{
			name: "topic channel past the duration grace",
			files: acquiredTrack("topic-longer", 168, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires",
			}),
			wantRecording: signalFires,
		},
		{
			name: "the original beside its re-recording",
			files: acquiredTrack("glass", 179, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Glass Coast",
			}),
			wantRecording: glassCoast,
		},
		{
			name: "the original with an upload year near its re-recording",
			files: acquiredTrack("glass-upload", 180, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Glass Coast", "DATE": "2019",
			}),
			wantRecording: glassCoast,
		},
		{
			name: "the re-recording with its own year",
			files: acquiredTrack("glass-2020", 183.5, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Glass Coast", "DATE": "2020",
			}),
			wantRecording: "rel-glass-2020-rec-1",
		},
		{
			name: "official video from the band's channel at the release's own length and year",
			files: acquiredTrack("official-exact", 163, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "The Cardinal Waves - Signal Fires", "DATE": "2011",
			}),
			wantRecording: signalFires,
		},
		{
			// A video runs a few seconds past the release and is dated a year
			// off: judged at 0.046, past the floor, which a floor raised to
			// take it would leave 0.012 short of the near-title trap.
			name: "official video from the band's channel",
			files: acquiredTrack("official", 167, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "The Cardinal Waves - Signal Fires", "DATE": "2012",
			}),
			wantRecording: signalFires,
		},
		{
			name: "official video with a long intro",
			files: acquiredTrack("official-intro", 181, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "The Cardinal Waves - Signal Fires", "DATE": "2012",
			}),
			wantRecording: signalFires,
		},
		{
			name: "official video from a vevo channel",
			files: acquiredTrack("vevo", 166, map[string]string{
				"ARTIST": "CardinalWavesVEVO", "TITLE": "The Cardinal Waves - Signal Fires", "DATE": "2012",
			}),
			wantRecording: signalFires, shouldAccept: true,
		},
		{
			name: "official video with a version tail",
			files: acquiredTrack("official-remaster", 159.5, map[string]string{
				"ARTIST": "Marrow and Pine", "TITLE": "Marrow and Pine - Driftwood - Remastered 2020",
			}),
			wantRecording: driftwood, shouldAccept: true,
		},
		{
			name: "version-tailed art track",
			files: acquiredTrack("remaster", 160.5, map[string]string{
				"ARTIST": "Marrow and Pine", "TITLE": "Driftwood - Remastered 2020",
				"ALBUM": "Hollow Harbor", "DATE": "2018",
			}),
			wantRecording: driftwood, shouldAccept: true,
		},
		{
			name: "version-tailed title with no description",
			files: acquiredTrack("remaster-bare", 161, map[string]string{
				"ARTIST": "Marrow and Pine", "TITLE": "Driftwood (2020 Remaster)", "DATE": "2020",
			}),
			wantRecording: driftwood, shouldAccept: true,
		},
		{
			name: "official video of a song the world lacks with a near title",
			files: acquiredTrack("official-near", 163, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "The Cardinal Waves - Signal Flares",
			}),
			noAccept: true,
		},
		{
			name: "official video of a cover the world lacks",
			files: acquiredTrack("official-cover", 162, map[string]string{
				"ARTIST": "BellhavenVEVO", "TITLE": "Bellhaven - Signal Fires",
			}),
			noAccept: true,
		},
		{
			name: "official video of the original near its re-recording",
			files: acquiredTrack("official-glass", 180, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "The Cardinal Waves - Glass Coast", "DATE": "2019",
			}),
			wantRecording: glassCoast,
		},
		{
			name: "official video of the re-recording",
			files: acquiredTrack("official-glass-2020", 183, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "The Cardinal Waves - Glass Coast", "DATE": "2020",
			}),
			wantRecording: "rel-glass-2020-rec-1",
		},
		{
			name: "a live take tailed live",
			files: acquiredTrack("live-tail", 202, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires - Live",
			}),
			wantRecording: "rel-live-rec-1",
		},
		{
			name: "a live take the world lacks at the studio length",
			files: acquiredTrack("live-tail-len", 162, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires - Live at Red Rocks",
			}),
			noAccept: true,
		},
		{
			name: "a shorter radio edit the world lacks",
			files: acquiredTrack("radio-edit", 150, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "The Cardinal Waves - Signal Fires - Radio Edit",
			}),
			noAccept: true,
		},
		{
			name: "a radio edit the world lacks at the studio length",
			files: acquiredTrack("radio-edit-len", 162, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "The Cardinal Waves - Signal Fires - Radio Edit",
			}),
			noAccept: true,
		},
		{
			name: "a clean edit from a topic channel at the studio length",
			files: acquiredTrack("clean-topic", 162, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires (Clean)",
			}),
			noAccept: true,
		},
		{
			name: "a clean edit from the band's channel at the studio length",
			files: acquiredTrack("clean-band", 162, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "The Cardinal Waves - Signal Fires (Clean)",
			}),
			noAccept: true,
		},
		{
			name: "an 8d audio upload at the studio length",
			files: acquiredTrack("8d", 162, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "The Cardinal Waves - Signal Fires (8D Audio)",
			}),
			noAccept: true,
		},
		{
			name: "a clean cut after a remaster tail at the studio length",
			files: acquiredTrack("clean-remaster", 162, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "The Cardinal Waves - Signal Fires - 2015 Remaster (Clean)",
			}),
			noAccept: true,
		},
		{
			name: "an explicit cut after a remastered tail from a topic channel at the studio length",
			files: acquiredTrack("explicit-remastered", 162, map[string]string{
				"ARTIST": "The Cardinal Waves - Topic", "TITLE": "Signal Fires - Remastered 2011 (Explicit)",
			}),
			noAccept: true,
		},
		{
			name: "a clean cut after a bonus track tail at the studio length",
			files: acquiredTrack("clean-bonus", 162, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires - Bonus Track (Clean)",
			}),
			noAccept: true,
		},
		{
			name: "a parenthesized remaster note",
			files: acquiredTrack("remaster-group", 159.5, map[string]string{
				"ARTIST": "Marrow and Pine", "TITLE": "Driftwood (2020 Remaster)",
			}),
			wantRecording: driftwood, shouldAccept: true,
		},
		{
			name: "a parenthesized remastered note after the split",
			files: acquiredTrack("remastered-group", 179, map[string]string{
				"ARTIST": "Marrow and Pine", "TITLE": "Marrow and Pine - Cartographer (Remastered 2011)",
			}),
			wantRecording: "rel-hollow-rec-2", shouldAccept: true,
		},
		{
			name: "the studio cut beside a session at its length, past the hydrated hits",
			files: acquiredTrack("undertow", 209, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Undertow",
			}),
			wantRecording: "rel-neon-rec-4",
		},
		{
			name: "the session beside the studio cut at its length",
			files: acquiredTrack("undertow-session", 211, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Undertow",
			}),
			wantRecording: "rel-bbc-session-rec-1",
		},
		{
			name: "the studio cut beside a session at its length, one past the listed page",
			files: acquiredTrack("foglines", 226, map[string]string{
				"ARTIST": "Marrow and Pine", "TITLE": "Foglines",
			}),
			wantRecording: "rel-hollow-rec-5",
		},
		{
			name: "a version-tailed song the world lacks with a near title",
			files: acquiredTrack("remaster-near", 163, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Flares - Remastered 2020",
			}),
			noAccept: true,
		},
		{
			name: "the cover the world holds",
			files: acquiredTrack("cover", 191, map[string]string{
				"ARTIST": "The Salt Collective", "TITLE": "Signal Fires",
			}),
			wantRecording: "rel-cover-signal-rec-1", shouldAccept: true,
		},
		{
			name: "a cover the world lacks",
			files: acquiredTrack("other-cover", 204, map[string]string{
				"ARTIST": "Bellhaven", "TITLE": "Signal Fires", "DATE": "2020",
			}),
			noAccept: true,
		},
		{
			name: "a cover the world lacks, at the original's length",
			files: acquiredTrack("other-cover-len", 162, map[string]string{
				"ARTIST": "Bellhaven", "TITLE": "Signal Fires",
			}),
			noAccept: true,
		},
		{
			name: "a song the world lacks with a near title",
			files: acquiredTrack("near-title", 233, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Flares", "DATE": "2021",
			}),
			noAccept: true,
		},
		{
			name: "a song the world lacks with a near title and length",
			files: acquiredTrack("near-title-len", 163, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Flares",
			}),
			noAccept: true,
		},
		{
			name: "a live upload of a studio song",
			files: acquiredTrack("live", 205, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires (Live at Red Rocks)", "DATE": "2019",
			}),
			noAccept: true,
		},
		{
			name: "a remix the world lacks",
			files: acquiredTrack("remix", 240, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "The Cardinal Waves - Signal Fires (Club Mix)",
			}),
			noAccept: true,
		},
		{
			// The search asks for "Signal Fires" and lists the rework below
			// every plain take; the judged title picks it among them.
			name: "a remix the world holds, named by its group",
			files: acquiredTrack("rework", 171, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires (Rework)",
			}),
			wantRecording: "rel-noise-1-rec-1", shouldAccept: true,
		},
		{
			name: "a remix the world holds, at the original's length",
			files: acquiredTrack("rework-len", 162, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "The Cardinal Waves - Signal Fires (Rework) (Official Audio)",
			}),
			wantRecording: "rel-noise-1-rec-1",
		},
		{
			name: "a demo the world holds, from the band's channel",
			files: acquiredTrack("demo", 339, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "The Cardinal Waves - Signal Fires (Demo) (Official Audio)",
			}),
			wantRecording: "rel-neon-dx-rec-11", shouldAccept: true,
		},
		{
			name: "a remix the world lacks at the studio length",
			files: acquiredTrack("remix-len", 162, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires (Bellhaven Remix)",
			}),
			noAccept: true,
		},
		{
			// The world titles its live take as the song, as MusicBrainz does.
			name: "a live take the world holds, named by a live group",
			files: acquiredTrack("live-group", 202, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Signal Fires (Live at Greyfield)",
			}),
			wantRecording: "rel-live-rec-1",
		},
		{
			name: "an acoustic take named by its group at the studio length",
			files: acquiredTrack("acoustic-len", 209, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Undertow (Acoustic)",
			}),
			wantRecording: "rel-acoustic-rec-1",
		},
		{
			name: "a remix listed below a dozen plain takes",
			files: acquiredTrack("lowlight-remix", 215, map[string]string{
				"ARTIST": "Petrel and Finch", "TITLE": "Lowlight (Harbor Remix)",
			}),
			wantRecording: "rel-lowlight-remix-rec-1", shouldAccept: true,
		},
		{
			name: "a remix listed below a dozen plain takes, at the studio length",
			files: acquiredTrack("lowlight-remix-len", 200, map[string]string{
				"ARTIST": "Petrel and Finch", "TITLE": "Petrel and Finch - Lowlight (Harbor Remix) (Official Video)",
			}),
			wantRecording: "rel-lowlight-remix-rec-1",
		},
		{
			// Titled as the song in the world, as MusicBrainz titles a live
			// take: the phrase with the group finds nothing at all.
			name: "a take named by a live group, among a dozen titled as the song",
			files: acquiredTrack("lowlight-live", 260, map[string]string{
				"ARTIST": "Petrel and Finch", "TITLE": "Lowlight (Live at the Anchor)",
			}),
			wantRecording: "rel-lowlight-takes-rec-3",
		},
		{
			name: "a guest group the world titles its recording with",
			files: acquiredTrack("guest", 200, map[string]string{
				"ARTIST": "Petrel and Finch", "TITLE": "Kestrel Road (feat. Ines Calder)",
			}),
			wantRecording: "rel-kestrel-rec-1", shouldAccept: true,
		},
		{
			name: "a live group after a guest group at the studio length",
			files: acquiredTrack("guest-live", 200, map[string]string{
				"ARTIST": "Petrel and Finch", "TITLE": "Kestrel Road (feat. Ines Calder) (Live)",
			}),
			noAccept: true,
		},
		{
			name: "a remix group after a guest group at the studio length",
			files: acquiredTrack("guest-remix", 200, map[string]string{
				"ARTIST": "Petrel and Finch", "TITLE": "Kestrel Road (feat. Ines Calder) (Dune Remix)",
			}),
			noAccept: true,
		},
		{
			name: "a demo group after a guest group at the studio length",
			files: acquiredTrack("guest-demo", 200, map[string]string{
				"ARTIST": "Petrel and Finch", "TITLE": "Kestrel Road (feat. Ines Calder) (Demo)",
			}),
			noAccept: true,
		},
		{
			name: "an acoustic group after a guest group at the studio length",
			files: acquiredTrack("guest-acoustic", 200, map[string]string{
				"ARTIST": "Petrel and Finch", "TITLE": "Petrel and Finch - Kestrel Road (feat. Ines Calder) (Acoustic) (Official Video)",
			}),
			noAccept: true,
		},
		{
			name: "a clean cut after a guest group at the studio length",
			files: acquiredTrack("guest-clean", 200, map[string]string{
				"ARTIST": "Petrel and Finch - Topic", "TITLE": "Kestrel Road (feat. Ines Calder) (Clean)",
			}),
			noAccept: true,
		},
		{
			name: "a live tail after a guest group at the studio length",
			files: acquiredTrack("guest-live-tail", 200, map[string]string{
				"ARTIST": "Petrel and Finch", "TITLE": "Kestrel Road (feat. Ines Calder) - Live at the Anchor",
			}),
			noAccept: true,
		},
		{
			name: "a live group after a bare guest clause at the studio length",
			files: acquiredTrack("guest-bare-live", 200, map[string]string{
				"ARTIST": "Petrel and Finch", "TITLE": "Kestrel Road feat. Ines Calder (Live)",
			}),
			noAccept: true,
		},
		{
			// 105 recordings titled "Saltwater" fill the plain title's page
			// before the remix: only the named phrase brings it onto the page.
			name: "a remix past the plain title's page",
			files: acquiredTrack("saltwater-remix", 228, map[string]string{
				"ARTIST": "Halden Row", "TITLE": "Saltwater (Dune Remix)",
			}),
			wantRecording: "rel-saltwater-remix-rec-1", shouldAccept: true,
		},
		{
			name: "a remix the world lacks, beside one past the plain title's page at its length",
			files: acquiredTrack("saltwater-other-remix", 228, map[string]string{
				"ARTIST": "Halden Row", "TITLE": "Saltwater (Tidal Remix)",
			}),
			noAccept: true,
		},
		{
			// The world titles this take "Saltwater (Live at the Pier)": the
			// named phrase lists it, and the judged title is not its title.
			name: "a live take past the plain title's page, named by a shorter group",
			files: acquiredTrack("saltwater-live", 262, map[string]string{
				"ARTIST": "Halden Row", "TITLE": "Saltwater (Live)",
			}),
			wantRecording: "rel-saltwater-pier-rec-1",
		},
		{
			name: "a long title as the world titles it",
			files: acquiredTrack("long", 300, map[string]string{
				"ARTIST": "Orrin Vale", "TITLE": longTitle,
			}),
			wantRecording: "rel-nocturne-rec-1", shouldAccept: true,
		},
		{
			name: "a live group on a long title at the studio length",
			files: acquiredTrack("long-live", 300, map[string]string{
				"ARTIST": "Orrin Vale", "TITLE": longTitle + " (Live)",
			}),
			noAccept: true,
		},
		{
			name: "a demo group on a long title at the studio length",
			files: acquiredTrack("long-demo", 300, map[string]string{
				"ARTIST": "Orrin Vale", "TITLE": "Orrin Vale - " + longTitle + " (Demo) (Official Audio)",
			}),
			noAccept: true,
		},
		{
			name: "a live tail on a long title at the studio length",
			files: acquiredTrack("long-live-tail", 300, map[string]string{
				"ARTIST": "Orrin Vale", "TITLE": longTitle + " - Live",
			}),
			noAccept: true,
		},
		{
			name: "a clean cut of a long title at the studio length",
			files: acquiredTrack("long-clean", 300, map[string]string{
				"ARTIST": "Orrin Vale", "TITLE": longTitle + " (Clean)",
			}),
			noAccept: true,
		},
		{
			// No word of the group is one the search knows to drop.
			name: "a second take of a long title at the studio length",
			files: acquiredTrack("long-take", 300, map[string]string{
				"ARTIST": "Orrin Vale", "TITLE": longTitle + " (Take 2)",
			}),
			noAccept: true,
		},
		{
			name: "a live take of another year of a long title, at the held take's length",
			files: acquiredTrack("long-live-1977", 341, map[string]string{
				"ARTIST": "Orrin Vale", "TITLE": longTitle + " (Live 1977)",
			}),
			noAccept: true,
		},
		{
			name: "the live take the world holds of a long title",
			files: acquiredTrack("long-live-1979", 341, map[string]string{
				"ARTIST": "Orrin Vale", "TITLE": longTitle + " (Live 1979)",
			}),
			wantRecording: "rel-nocturne-1979-rec-1", shouldAccept: true,
		},
		{
			name: "a plain download two years after the release",
			files: acquiredTrack("two-years", 179, map[string]string{
				"ARTIST": "Marrow and Pine", "TITLE": "Cartographer", "DATE": "2020",
			}),
			wantRecording: "rel-hollow-rec-2", shouldAccept: true,
		},
		{
			name: "a plain download five years after the release",
			files: acquiredTrack("five-years", 159, map[string]string{
				"ARTIST": "Marrow and Pine", "TITLE": "Marrow and Pine - Driftwood", "DATE": "2023",
			}),
			wantRecording: driftwood, shouldAccept: true,
		},
		{
			// The year was never what told these apart: the lengths are.
			name: "the original uploaded in its re-recording's year, at a length between the two",
			files: acquiredTrack("glass-between", 180.5, map[string]string{
				"ARTIST": "The Cardinal Waves", "TITLE": "Glass Coast", "DATE": "2020",
			}),
			wantRecording: glassCoast,
		},
		{
			name: "the original uploaded years on, beside its re-recording",
			files: acquiredTrack("glass-late", 178, map[string]string{
				"ARTIST": "The Cardinal Waves - Topic", "TITLE": "Glass Coast", "DATE": "2024",
			}),
			wantRecording: glassCoast,
		},
		{
			name:     "an upload naming no artist, titled as a stranger's song at its length",
			files:    uploadedTrack("no-artist", 159, map[string]string{"TITLE": "Driftwood"}),
			noAccept: true,
		},
		{
			name: "an upload naming no artist under an album, titled as a stranger's song",
			files: uploadedTrack("no-artist-album", 159, map[string]string{
				"TITLE": "Driftwood", "ALBUM": "Hollow Harbor", "TRACKNUMBER": "1",
			}),
			noAccept: true,
		},
		{
			name: "an art track of a title its album prints twice, between the two lengths",
			files: acquiredTrack("twice", 201.5, map[string]string{
				"ARTIST": "Quill and Ember", "TITLE": "Paper Boats", "ALBUM": "Paper Boats", "DATE": "1967",
			}),
			noAccept: true,
		},
		{
			name: "an art track of a title its album prints twice, at the first's length",
			files: acquiredTrack("twice-first", 200, map[string]string{
				"ARTIST": "Quill and Ember", "TITLE": "Paper Boats", "ALBUM": "Paper Boats", "DATE": "1967",
			}),
			wantRecording: "rel-paper-boats-rec-1",
		},
		{
			name: "a fan upload under a stranger's channel",
			files: acquiredTrack("fan", 163, map[string]string{
				"ARTIST": "musiclover1987", "TITLE": "Signal Fires",
			}),
			wantRecording: signalFires,
		},
	}
}

// topRecording is the recording the match pairs with the unit's first
// track, "" when it pairs none.
func topRecording(m *Match) string {
	for _, p := range m.Pairings {
		if p.TrackIndex == 0 {
			return m.Release.Tracks[p.ReleaseIndex].RecordingMBID
		}
	}
	return ""
}

// judgedList is the ranking accept-best judges: the re-scored list where the
// engine kept one, else the stored candidates.
func judgedList(p *Proposal) []Match {
	if p.judged != nil {
		return p.judged
	}
	return p.Candidates
}

func listTop(ms []Match) string {
	if len(ms) == 0 {
		return "none"
	}
	return ms[0].Release.MBID
}

func listTopRecording(ms []Match) string {
	if len(ms) == 0 {
		return "none"
	}
	return topRecording(&ms[0])
}

func listTopDistance(ms []Match) float64 {
	if len(ms) == 0 {
		return 1
	}
	return ms[0].Distance
}

// differentGap is how far behind the top the nearest candidate naming
// another recording sits (1 when none does), for the calibration log.
func differentGap(ms []Match) float64 {
	gap := 1.0
	if len(ms) == 0 {
		return gap
	}
	top := &ms[0]
	for i := 1; i < len(ms); i++ {
		if namesDifferentRecording(top, &ms[i]) {
			if g := ms[i].Distance - top.Distance; g < gap {
				gap = g
			}
		}
	}
	return gap
}

// TestEvalAcceptBest is accept-best's precision check: the corpus's units
// plus acquisition-shaped singles, judged at the shipped floor and margin.
// A wrong accept fails the suite outright; the accepted share of the
// cases labelled shouldAccept is a ratcheted floor.
func TestEvalAcceptBest(t *testing.T) {
	world := buildWorld()
	var cases []acceptCase
	for _, c := range corpusCases(world) {
		cases = append(cases, acceptCase{
			name: "corpus: " + c.name, files: c.files, wantTop: c.wantTop,
			noAccept: c.wantTop == "", shouldAccept: c.shouldAuto,
		})
	}
	cases = append(cases, acquisitionCases()...)

	var wrong, shouldTotal, shouldHit int
	for _, c := range cases {
		// Every case under both orders the index may list tied hits in; an
		// accept counts only when both take the right recording.
		hit := true
		for _, flip := range []bool{false, true} {
			t.Run(fmt.Sprintf("%s/ties flipped %v", c.name, flip), func(t *testing.T) {
				units := Cluster(c.files)
				if len(units) != 1 {
					t.Fatalf("case must cluster to one unit, got %d", len(units))
				}
				p, err := NewEngine(&worldSource{w: world, flipTies: flip}, Config{}).Identify(context.Background(), units[0])
				if err != nil {
					t.Fatal(err)
				}
				got, verdict := p.JudgeBest(Config{})
				right := false
				if got != nil {
					switch {
					case c.wantRecording != "":
						right = topRecording(got) == c.wantRecording
					case c.wantTop != "":
						right = got.Release.MBID == c.wantTop
					}
				}
				j := judgedList(p)
				t.Logf("raw top %s at %.3f; judged top %s (recording %s) at %.3f, different recording %.3f behind: %v",
					bestMBID(p), bestDistance(p), listTop(j), listTopRecording(j), listTopDistance(j), differentGap(j), verdict)
				if got != nil && !right {
					wrong++
					t.Errorf("wrong accept: %s (recording %s) at %.3f", got.Release.MBID, topRecording(got), got.Distance)
				}
				hit = hit && right
			})
		}
		if c.shouldAccept {
			shouldTotal++
			if hit {
				shouldHit++
			}
		}
	}
	if wrong > 0 {
		t.Fatalf("%d wrong accepts", wrong)
	}
	const acceptFloor = 0.87
	share := float64(shouldHit) / float64(shouldTotal)
	t.Logf("accepted %d of %d shouldAccept cases (%.2f)", shouldHit, shouldTotal, share)
	if share < acceptFloor {
		t.Fatalf("accepted share %.2f below floor %.2f", share, acceptFloor)
	}
}

// A recording named by a group sits past the page of its plain title when the
// song has more plain-titled recordings than a search lists; the named phrase
// in the same search puts it on the page, so it is a candidate again.
func TestANamedRecordingPastThePlainPageIsACandidate(t *testing.T) {
	world := buildWorld()
	for _, c := range []struct {
		title string
		dur   float64
		want  string
	}{
		{"Saltwater (Dune Remix)", 228, "rel-saltwater-remix"},
		{"Saltwater (Live)", 262, "rel-saltwater-pier"},
		{"Halden Row - Saltwater - Live at the Pier", 262, "rel-saltwater-pier"},
	} {
		for _, flip := range []bool{false, true} {
			files := acquiredTrack("named", c.dur, map[string]string{"ARTIST": "Halden Row", "TITLE": c.title})
			p, err := NewEngine(&worldSource{w: world, flipTies: flip}, Config{}).Identify(context.Background(), Cluster(files)[0])
			if err != nil {
				t.Fatal(err)
			}
			var got []string
			for _, m := range p.Candidates {
				got = append(got, m.Release.MBID)
			}
			if !slices.Contains(got, c.want) {
				t.Errorf("%q (ties flipped %v): candidates %q, want %s among them", c.title, flip, got, c.want)
			}
		}
	}
}

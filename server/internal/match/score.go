package match

import (
	"path/filepath"
	"sort"
	"strconv"
	"strings"
)

// Weights are the distance model's field weights. Zero values mean "use
// the default"; the defaults are tuned against the evaluation corpus,
// with track evidence deliberately outweighing album header fields so a
// correct tracklist can overcome a renamed album and not vice versa.
type Weights struct {
	Artist        float64 // album artist vs release artist
	Album         float64 // album title vs release title
	Year          float64 // tag year vs release year
	TrackTitle    float64 // per pair title distance
	TrackArtist   float64 // per pair artist distance, compilations only
	TrackDuration float64 // per pair duration distance
	TrackPosition float64 // per pair track number distance
	Missing       float64 // per release track no file matched
	Extra         float64 // per file no release track matched
}

func (w Weights) withDefaults() Weights {
	def := func(v *float64, d float64) {
		if *v == 0 {
			*v = d
		}
	}
	def(&w.Artist, 3.0)
	def(&w.Album, 3.0)
	def(&w.Year, 1.0)
	def(&w.TrackTitle, 3.0)
	def(&w.TrackArtist, 2.0)
	def(&w.TrackDuration, 2.0)
	def(&w.TrackPosition, 1.0)
	def(&w.Missing, 0.9)
	def(&w.Extra, 0.6)
	return w
}

const (
	// durationGraceSec is slack before duration differences count at
	// all (encoder padding, rip variance); durationSpanSec is where the
	// difference saturates at maximal distance.
	durationGraceSec = 2.5
	durationSpanSec  = 12.0
)

// Score assigns the unit's tracks onto the release and computes the
// weighted match distance with its component breakdown.
func Score(unit Unit, release *Release, w Weights) Match {
	w = w.withDefaults()
	va := release.Compilation

	// Pair distances for the assignment.
	n, m := len(unit.Tracks), len(release.Tracks)
	cost := make([][]float64, n)
	for i := range cost {
		cost[i] = make([]float64, m)
		for j := range cost[i] {
			d, _ := pairDist(unit.Tracks[i], release.Tracks[j], j, va, w)
			cost[i][j] = d
		}
	}
	assigned := assign(cost)

	match := Match{Release: release}
	var num, den float64
	component := func(name string, dist, weight float64) {
		if weight <= 0 {
			return
		}
		num += dist * weight
		den += weight
		match.Components = append(match.Components, Component{Name: name, Distance: dist, Weight: weight})
	}

	// Album header evidence. Untagged sides skip their component rather
	// than fabricating agreement or disagreement.
	if va {
		// Differing per track artists are what a compilation looks
		// like, so only an explicit album artist tag argues with one.
		// One file cannot exhibit differing artists, so an untagged
		// single earns no zero here: left in, the free component
		// dilutes a compilation's distance below every plain release
		// carrying the same recording (missing no longer masks it).
		aa := majorityTag(unit, "ALBUMARTIST")
		if aa == "" {
			if n > 1 {
				component("artist", 0, w.Artist)
			}
		} else if normalize(aa) == "various artists" {
			component("artist", 0, w.Artist)
		} else {
			component("artist", titleDist(aa, release.Artist), w.Artist)
		}
	} else if unitArtist := unitAlbumArtist(unit); unitArtist != "" && release.Artist != "" {
		component("artist", titleDist(unitArtist, release.Artist), w.Artist)
	}
	if unitAlbum := majorityTag(unit, "ALBUM"); unitAlbum != "" && release.Title != "" {
		component("album", albumDist(unitAlbum, release.Title), w.Album)
	}
	if unitYear := unitYear(unit); unitYear > 0 && release.Year > 0 {
		component("year", yearDist(unitYear, release.Year), w.Year)
	}

	// Track evidence: the assigned pairs, then unmatched penalties.
	usedRelease := make([]bool, m)
	var pairNum, pairDen float64
	for i, j := range assigned {
		if j < 0 {
			match.ExtraIndexes = append(match.ExtraIndexes, i)
			continue
		}
		usedRelease[j] = true
		d, weight := pairDist(unit.Tracks[i], release.Tracks[j], j, va, w)
		match.Pairings = append(match.Pairings, Pairing{TrackIndex: i, ReleaseIndex: j, Distance: d})
		pairNum += d * weight
		pairDen += weight
	}
	if pairDen > 0 {
		component("tracks", pairNum/pairDen, pairDen)
	}
	for j := range m {
		if !usedRelease[j] {
			match.MissingIndexes = append(match.MissingIndexes, j)
		}
	}
	// A one-file unit only ever asked for one track, so the rest of the
	// release is context, not absence: the missing penalty is charged
	// to album-shaped units alone. The indexes stay recorded either way
	// so the queue can show the whole release.
	if c := len(match.MissingIndexes); c > 0 && n > 1 {
		component("missing", 1, float64(c)*w.Missing)
	}
	if c := len(match.ExtraIndexes); c > 0 {
		component("extra", 1, float64(c)*w.Extra)
	}

	if den > 0 {
		match.Distance = num / den
	} else {
		// No comparable evidence at all: maximally uncertain.
		match.Distance = 1
	}
	sort.Slice(match.Pairings, func(a, b int) bool {
		return match.Pairings[a].TrackIndex < match.Pairings[b].TrackIndex
	})
	return match
}

// pairDist is the weighted distance between one file and one release
// track, with the pair's total weight (fields missing on either side
// drop out of both sums). absIndex is the release track's zero based
// index for positionless comparison.
func pairDist(t Track, rt ReleaseTrack, absIndex int, va bool, w Weights) (float64, float64) {
	var num, den float64
	add := func(dist, weight float64) {
		num += dist * weight
		den += weight
	}
	add(titleDist(trackTitle(t), rt.Title), w.TrackTitle)
	if t.DurationSec > 0 && rt.DurationSec > 0 {
		add(durationDist(t.DurationSec, rt.DurationSec), w.TrackDuration)
	}
	if n := trackNumber(t); n > 0 {
		add(positionDist(t, rt, n, absIndex), w.TrackPosition)
	}
	if va {
		if ta := t.Tags["ARTIST"]; ta != "" && rt.Artist != "" {
			add(titleDist(ta, rt.Artist), w.TrackArtist)
		}
	}
	if den == 0 {
		return 1, w.TrackTitle
	}
	return num / den, den
}

func durationDist(a, b float64) float64 {
	diff := a - b
	if diff < 0 {
		diff = -diff
	}
	if diff <= durationGraceSec {
		return 0
	}
	d := (diff - durationGraceSec) / durationSpanSec
	if d > 1 {
		return 1
	}
	return d
}

func positionDist(t Track, rt ReleaseTrack, n, absIndex int) float64 {
	disc := trackDisc(t)
	if disc > 0 && rt.Disc > 0 {
		if n == rt.Position && disc == rt.Disc {
			return 0
		}
		if n == rt.Position {
			return 0.5
		}
		return 1
	}
	if n == rt.Position || n == absIndex+1 {
		return 0
	}
	return 1
}

func yearDist(a, b int) float64 {
	diff := a - b
	if diff < 0 {
		diff = -diff
	}
	switch {
	case diff == 0:
		return 0
	case diff == 1:
		return 0.2
	case diff <= 5:
		return 0.5
	default:
		return 1
	}
}

// trackTitle prefers the TITLE tag and falls back to a cleaned filename
// stem, which is what carries the title on untagged rips.
func trackTitle(t Track) string {
	if title := t.Tags["TITLE"]; title != "" {
		return title
	}
	stem := strings.TrimSuffix(filepath.Base(t.Path), filepath.Ext(t.Path))
	return cleanStem(stem)
}

// cleanStem strips leading track numbering ("01 - ", "1_", "03.") from a
// filename stem.
func cleanStem(stem string) string {
	s := strings.TrimSpace(stem)
	i := 0
	for i < len(s) && s[i] >= '0' && s[i] <= '9' {
		i++
	}
	if i == 0 || i > 3 {
		return s
	}
	rest := strings.TrimLeft(s[i:], " .-_")
	if rest == "" {
		return s
	}
	return rest
}

// unitAlbumArtist is the unit's majority album artist, falling back to
// the majority track artist when no album artist tag exists.
func unitAlbumArtist(u Unit) string {
	if a := majorityTag(u, "ALBUMARTIST"); a != "" {
		return a
	}
	return majorityTag(u, "ARTIST")
}

// unitYear is the unit's majority release year parsed from DATE.
func unitYear(u Unit) int {
	counts := make(map[int]int)
	best, bestCount := 0, 0
	for _, t := range u.Tracks {
		y := parseYear(t.Tags["DATE"])
		if y == 0 {
			continue
		}
		counts[y]++
		if counts[y] > bestCount || (counts[y] == bestCount && y < best) {
			best, bestCount = y, counts[y]
		}
	}
	return best
}

func parseYear(s string) int {
	s = strings.TrimSpace(s)
	if len(s) < 4 {
		return 0
	}
	y, err := strconv.Atoi(s[:4])
	if err != nil || y < 1000 || y > 3000 {
		return 0
	}
	return y
}

// majorityTag returns the most common non empty value for a tag across
// the unit, with ties broken lexically for determinism.
func majorityTag(u Unit, key string) string {
	counts := make(map[string]int)
	best, bestCount := "", 0
	for _, t := range u.Tracks {
		v := strings.TrimSpace(t.Tags[key])
		if v == "" {
			continue
		}
		counts[v]++
		if counts[v] > bestCount || (counts[v] == bestCount && v < best) {
			best, bestCount = v, counts[v]
		}
	}
	return best
}

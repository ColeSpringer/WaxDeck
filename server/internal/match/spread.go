package match

import "github.com/colespringer/waxdeck/server/internal/sourcenoise"

// RecordingSearchCap is how many releases a recording search hands back at
// most. A search answering that many may have left recordings out.
const RecordingSearchCap = 5

// RecordingSearchPage is how many hits a recording search lists, in its one
// request; every listed recording is judged as a rival. RecordingSearchSpread
// is how many hits the hydrated releases are spread over.
const (
	RecordingSearchPage   = 100
	RecordingSearchSpread = 8
)

// SearchHit is one recording a search listed, as the spread reads it: its
// title, the releases carrying it, best first, and the best release under
// each album title they carry, by AlbumKey.
type SearchHit struct {
	Title    string
	Releases []string
	Albums   map[string]string
}

// AlbumKey is an album title as the spread compares one: normalized, its
// trailing edition and remaster words dropped.
func AlbumKey(title string) string { return stripEdition(normalize(title)) }

// SpreadReleases picks the releases a recording search hydrates from its
// hits, in search order: the first RecordingSearchSpread of them, after the
// ones titled as named. A search asks for the song alone, so the recording an
// upload names ("Song (X Remix)") is listed below every plain take, past
// what the spread would otherwise read. The lead hit takes two (an edition
// choice for the likeliest recording), every further hit one, then round
// robin, so the candidates name several recordings and accept-best can see a
// near namesake. A popular song's lead recording sits on dozens of releases;
// taken in order, it would fill every slot.
//
// Before any of that, a release titled as album (the album the unit names,
// by AlbumKey) is taken from each hit carrying one, wherever the hit sits: a
// file tagged with a compilation is on a release every hit ranks last.
func SpreadReleases(hits []SearchHit, named, album string) []string {
	if named != "" {
		var first, rest []SearchHit
		for _, h := range hits {
			if sourcenoise.SameTitle(h.Title, named) {
				first = append(first, h)
			} else {
				rest = append(rest, h)
			}
		}
		hits = append(first, rest...)
	}
	var ids []string
	taken := make(map[string]bool)
	if key := AlbumKey(album); key != "" {
		for _, h := range hits {
			if id := h.Albums[key]; id != "" && !taken[id] && len(ids) < RecordingSearchCap {
				taken[id] = true
				ids = append(ids, id)
			}
		}
	}
	hits = hits[:min(len(hits), RecordingSearchSpread)]
	next := make([]int, len(hits))
	take := func(h int) bool {
		for next[h] < len(hits[h].Releases) {
			id := hits[h].Releases[next[h]]
			next[h]++
			if id != "" && !taken[id] {
				taken[id] = true
				ids = append(ids, id)
				return true
			}
		}
		return false
	}
	for round := 0; ; round++ {
		progressed := false
		for h := range hits {
			n := 1
			if h == 0 && round == 0 {
				n = 2
			}
			for range n {
				if len(ids) >= RecordingSearchCap {
					return ids
				}
				if take(h) {
					progressed = true
				}
			}
		}
		if !progressed {
			return ids
		}
	}
}

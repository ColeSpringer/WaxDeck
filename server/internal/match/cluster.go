package match

import (
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

// Cluster groups loose tracks into album units. Grouping runs in two
// passes: tracks first key on their normalized album artist plus album
// title (parent directory when both are missing), then units sharing the
// same normalized album inside the same directory merge, which is what
// holds a compilation together when every track names a different
// artist. Disc subdirectories (CD1, Disc 2) fold into their parent so a
// multi disc rip stays one unit. Output is deterministic: tracks sort by
// disc, track number, then path, and units sort by key.
func Cluster(tracks []Track) []Unit {
	keys := make([]string, len(tracks))
	for i, t := range tracks {
		keys[i] = clusterKey(t)
	}

	// Merge pass: same album title in the same folded directory means
	// one unit, whatever the per track artists say.
	parent := make(map[string]string)
	var find func(string) string
	find = func(k string) string {
		p, ok := parent[k]
		if !ok || p == k {
			parent[k] = k
			return k
		}
		root := find(p)
		parent[k] = root
		return root
	}
	union := func(a, b string) {
		ra, rb := find(a), find(b)
		if ra == rb {
			return
		}
		// Smaller key wins so the merged unit key is deterministic.
		if rb < ra {
			ra, rb = rb, ra
		}
		parent[rb] = ra
	}
	byAlbumDir := make(map[string]string)
	for i, t := range tracks {
		album := normalize(t.Tags["ALBUM"])
		if album == "" {
			continue
		}
		secondary := album + "\x00" + foldDiscDir(filepath.Dir(t.Path))
		if prior, ok := byAlbumDir[secondary]; ok {
			union(prior, keys[i])
		} else {
			byAlbumDir[secondary] = keys[i]
		}
	}

	groups := make(map[string][]Track)
	for i, t := range tracks {
		groups[find(keys[i])] = append(groups[find(keys[i])], t)
	}
	units := make([]Unit, 0, len(groups))
	for key, members := range groups {
		sort.SliceStable(members, func(i, j int) bool {
			di, dj := trackDisc(members[i]), trackDisc(members[j])
			if di != dj {
				return di < dj
			}
			ni, nj := trackNumber(members[i]), trackNumber(members[j])
			if ni != nj {
				return ni < nj
			}
			return members[i].Path < members[j].Path
		})
		units = append(units, Unit{Key: key, Tracks: members})
	}
	sort.Slice(units, func(i, j int) bool { return units[i].Key < units[j].Key })
	return units
}

var discDirPattern = regexp.MustCompile(`(?i)^(cd|dis[ck])[ ._-]*\d+$`)

// foldDiscDir folds a disc subdirectory into its parent.
func foldDiscDir(dir string) string {
	if discDirPattern.MatchString(filepath.Base(dir)) {
		return filepath.Dir(dir)
	}
	return dir
}

// clusterKey derives the first pass grouping key for one track.
func clusterKey(t Track) string {
	artist := t.Tags["ALBUMARTIST"]
	if artist == "" {
		artist = t.Tags["ARTIST"]
	}
	na, nb := normalize(artist), normalize(t.Tags["ALBUM"])
	if nb != "" {
		return "tags\x00" + na + "\x00" + nb
	}
	return "dir\x00" + foldDiscDir(filepath.Dir(t.Path))
}

// trackDisc and trackNumber parse ordering tags, tolerating the "3/12"
// total suffix form; 0 means unknown and sorts first.
func trackDisc(t Track) int { return parseOrdinal(t.Tags["DISCNUMBER"]) }

func trackNumber(t Track) int { return parseOrdinal(t.Tags["TRACKNUMBER"]) }

func parseOrdinal(s string) int {
	s = strings.TrimSpace(s)
	if i := strings.IndexByte(s, '/'); i >= 0 {
		s = s[:i]
	}
	n, err := strconv.Atoi(strings.TrimSpace(s))
	if err != nil || n < 0 {
		return 0
	}
	return n
}

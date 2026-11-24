package match

import (
	"cmp"
	"path"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"
)

// Cluster groups loose tracks into album units. Grouping runs in two
// passes: tracks first key on their normalized album artist plus album
// title (parent directory when both are missing), then units sharing the
// same normalized album inside the same directory merge, which is what
// holds a compilation together when every track names a different
// artist. Disc subdirectories (CD1, Disc 2) fold into their parent so a
// multi disc rip stays one unit. Output is deterministic: tracks sort as
// CompareTracks says, and units sort by key.
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
		secondary := album + "\x00" + trackFolder(t, discDirPattern)
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
	return sortedUnits(groups)
}

// ClusterBooks groups a book's tagged tracks by their normalized album
// alone, whatever folders they sit in: a part's artist may credit a
// narrator beside the author. An album whose tracks name different
// album artists (each a book's author) splits by album artist, a track
// naming none its own unit; one naming a single album artist, or none,
// stays whole. An album that normalizes to nothing groups by folder.
// Ordering is Cluster's.
func ClusterBooks(tracks []Track) []Unit {
	authors := make(map[string]map[string]bool)
	for _, t := range tracks {
		album := normalize(t.Tags["ALBUM"])
		if authors[album] == nil {
			authors[album] = make(map[string]bool)
		}
		if a := normalize(t.Tags["ALBUMARTIST"]); a != "" {
			authors[album][a] = true
		}
	}
	groups := make(map[string][]Track)
	for _, t := range tracks {
		album := normalize(t.Tags["ALBUM"])
		key := "dir\x00" + BookFolder(t)
		if album != "" {
			author := ""
			if len(authors[album]) > 1 {
				author = normalize(t.Tags["ALBUMARTIST"])
			}
			key = "book\x00" + album + "\x00" + author
		}
		groups[key] = append(groups[key], t)
	}
	return sortedUnits(groups)
}

// ClusterByFolder groups a book's tracks by their folder alone
// (BookFolder), whatever their tags say: the parts of one book name
// chapters, or albums of their own, and still belong together. Tracks
// with no folder are one unit. Ordering is Cluster's.
func ClusterByFolder(tracks []Track) []Unit {
	groups := make(map[string][]Track)
	for _, t := range tracks {
		key := "dir\x00" + BookFolder(t)
		groups[key] = append(groups[key], t)
	}
	return sortedUnits(groups)
}

// sortedUnits orders each group's tracks (CompareTracks) and the units
// by key.
func sortedUnits(groups map[string][]Track) []Unit {
	units := make([]Unit, 0, len(groups))
	for key, members := range groups {
		slices.SortStableFunc(members, CompareTracks)
		units = append(units, Unit{Key: key, Tracks: members})
	}
	sort.Slice(units, func(i, j int) bool { return units[i].Key < units[j].Key })
	return units
}

// discDirPattern names an album's disc subfolder (CD1, Disc 2).
var discDirPattern = regexp.MustCompile(`(?i)^(cd|dis[ck])[ ._-]*\d+$`)

// bookDirPattern names a book's disc or part subfolder (CD1, Disc 2,
// Part 3): the client's rule for an audiobook pick (add_to_library.dart
// _discFolder), so its default grouping and this fold agree. The
// separators are spelled out (space, tab, no-break space, _ . -) because
// Go's \s and Dart's differ beyond ASCII.
var bookDirPattern = regexp.MustCompile(`(?i)^(disc|disk|cd|part)[ \t\x{00A0}_.-]*\d+$`)

// FoldBookDir folds a book's disc or part subfolder (CD1, Part 2) into
// its parent. dir is a batch folder, a slash path on every OS.
func FoldBookDir(dir string) string { return foldSlashDir(dir, bookDirPattern) }

// BookFolder is the folder a book's track sits in, a disc or part
// subfolder read as its parent.
func BookFolder(t Track) string { return trackFolder(t, bookDirPattern) }

// trackFolder is the folder t sits in, a subfolder sub names read as its
// parent. A path a batch sent is a slash path on every OS; any other is
// a path on this one.
func trackFolder(t Track, sub *regexp.Regexp) string {
	if t.Sent {
		return foldSlashDir(path.Dir(t.Path), sub)
	}
	dir := filepath.Dir(t.Path)
	if sub.MatchString(filepath.Base(dir)) {
		return filepath.Dir(dir)
	}
	return dir
}

// foldSlashDir is the slash path dir, read as its parent when sub names
// its last segment.
func foldSlashDir(dir string, sub *regexp.Regexp) string {
	if sub.MatchString(path.Base(dir)) {
		return path.Dir(dir)
	}
	return dir
}

// CompareTracks is the order of a unit's files: by the disc number they
// carry, then, for files sent in an upload batch, by the folder each was
// sent from (CompareFolders), then by track number, then by path. Where
// any other file sits says nothing: a staged file sits in a folder named
// for its session.
func CompareTracks(a, b Track) int {
	if c := cmp.Compare(trackDisc(a), trackDisc(b)); c != 0 {
		return c
	}
	if c := CompareFolders(sentFolder(a), sentFolder(b)); c != 0 {
		return c
	}
	if c := cmp.Compare(trackNumber(a), trackNumber(b)); c != 0 {
		return c
	}
	return strings.Compare(a.Path, b.Path)
}

// sentFolder is the batch folder a file was sent from, empty for none.
func sentFolder(t Track) string {
	if !t.Sent {
		return ""
	}
	if dir := path.Dir(t.Path); dir != "." {
		return dir
	}
	return ""
}

// CompareFolders orders slash-separated folders segment by segment, each
// name naturally (compareNatural), so Part 2 comes before Part 10 and
// Vol 1 CD2 before Vol 1 CD10. A folder comes before the folders inside
// it.
func CompareFolders(a, b string) int {
	sa, sb := folderSegments(a), folderSegments(b)
	for i := 0; i < len(sa) && i < len(sb); i++ {
		if c := compareNatural(sa[i], sb[i]); c != 0 {
			return c
		}
	}
	return cmp.Compare(len(sa), len(sb))
}

func folderSegments(dir string) []string {
	if dir == "" {
		return nil
	}
	return strings.Split(dir, "/")
}

// compareNatural compares two names run by run: a run of digits by its
// number, a run of anything else as text, a number before text. Names
// whose runs all tie (01 and 1) fall back to plain order.
func compareNatural(a, b string) int {
	ra, rb := a, b
	for ra != "" && rb != "" {
		ta, da := leadingRun(ra)
		tb, db := leadingRun(rb)
		var c int
		switch {
		case da != db:
			if da {
				return -1
			}
			return 1
		case da:
			na, nb := strings.TrimLeft(ta, "0"), strings.TrimLeft(tb, "0")
			c = cmp.Or(cmp.Compare(len(na), len(nb)), strings.Compare(na, nb))
		default:
			c = strings.Compare(ta, tb)
		}
		if c != 0 {
			return c
		}
		ra, rb = ra[len(ta):], rb[len(tb):]
	}
	switch {
	case ra != "":
		return 1
	case rb != "":
		return -1
	}
	return strings.Compare(a, b)
}

// leadingRun is s's first run of ASCII digits, or of anything else, and
// whether it is digits.
func leadingRun(s string) (string, bool) {
	digits := isDigit(s[0])
	i := 1
	for i < len(s) && isDigit(s[i]) == digits {
		i++
	}
	return s[:i], digits
}

func isDigit(c byte) bool { return '0' <= c && c <= '9' }

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
	return "dir\x00" + trackFolder(t, discDirPattern)
}

// trackDisc and trackNumber read ordering tags; 0 means unknown and
// sorts first.
func trackDisc(t Track) int { return ParseOrdinal(t.Tags["DISCNUMBER"]) }

func trackNumber(t Track) int { return ParseOrdinal(t.Tags["TRACKNUMBER"]) }

// ParseOrdinal reads a disc or track number tag: the digits it starts
// with, so a total after them ("3/12", "3 of 12") is left out. 0 means
// none, or past 9999.
func ParseOrdinal(s string) int {
	n := 0
	for _, r := range strings.TrimSpace(s) {
		if r < '0' || r > '9' {
			break
		}
		n = n*10 + int(r-'0')
		if n > 9999 {
			return 0
		}
	}
	return n
}

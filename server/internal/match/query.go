package match

import "strings"

// SuggestedQuery exposes the tag derivation, so a surface showing what
// the matcher read out of a source title does not reimplement it. The
// derivation only: a typed query has no business changing a suggestion.
func SuggestedQuery(t Track) (artist, title string, ok bool) {
	artist, title = derivedQuery(t)
	if title == "" {
		return "", "", false
	}
	return artist, title, true
}

// recordingQuery builds a MusicBrainz recording search (artist, title) for a
// track: what somebody typed for it where they typed something, and what its
// tags imply everywhere else. It returns ok=false when no usable title
// survives.
func recordingQuery(t Track) (artist, title string, ok bool) {
	artist, title = derivedQuery(t)
	if q := t.Query; q != nil {
		if v := strings.TrimSpace(q.Artist); v != "" {
			artist = v
		}
		if v := strings.TrimSpace(q.Title); v != "" {
			title = v
		}
	}
	if title == "" {
		return "", "", false
	}
	return artist, title, true
}

// derivedQuery reads a search out of a track's tags. It targets the shape
// acquired and mislabeled files take: the descriptive title carries
// "Artist - Track", and the artist tag is often a channel or uploader rather
// than the performer.
func derivedQuery(t Track) (artist, title string) {
	title = strings.TrimSpace(t.Tags["TITLE"])
	artist = strings.TrimSpace(t.Tags["ARTIST"])
	if artist == "" {
		artist = strings.TrimSpace(t.Tags["ALBUMARTIST"])
	}
	// An "Artist - Track" descriptive title overrides the artist tag: acquired
	// content routinely tags the channel as the artist and packs the real
	// performer into the title.
	if a, tr, split := splitArtistTitle(title); split {
		artist, title = a, tr
	}
	title = cleanDescriptiveTitle(title)
	artist = stripTopicSuffix(artist)
	artist = stripTrailingParenthetical(artist)
	return artist, title
}

// stripTopicSuffix removes YouTube's auto-generated " - Topic" channel suffix
// from an artist. Topic channels are the Art Track auto-channels YouTube mints
// with labels and distributors, named "<Artist> - Topic"; the suffix is machine
// appended and never part of the artist name, so a recording search must key on
// the bare artist. The match is case-insensitive and tolerates trailing space.
func stripTopicSuffix(artist string) string {
	const suffix = " - topic"
	a := strings.TrimRight(artist, " ")
	if strings.HasSuffix(strings.ToLower(a), suffix) {
		return strings.TrimSpace(a[:len(a)-len(suffix)])
	}
	return artist
}

// artistTrackSeparators are the tokens that split a descriptive "Artist - Track"
// title, in precedence order. Each is surrounded by spaces so hyphenated words
// ("Twenty-One") never split.
var artistTrackSeparators = []string{" - ", " – ", " — "}

// splitArtistTitle splits a descriptive title on the first artist/track
// separator. Both sides must be non-empty after trimming for the split to count.
func splitArtistTitle(title string) (artist, track string, ok bool) {
	for _, sep := range artistTrackSeparators {
		if i := strings.Index(title, sep); i > 0 {
			a := strings.TrimSpace(title[:i])
			tr := strings.TrimSpace(title[i+len(sep):])
			if a != "" && tr != "" {
				return a, tr, true
			}
		}
	}
	return "", "", false
}

// cleanDescriptiveTitle strips trailing production-note groups a title picks up
// on video platforms ("(Official Video)", "[Lyrics]", "(Prod. by ...)") while
// keeping groups that name a distinct recording ("(Live)", "(Remix)", "(feat.
// ...)"), since those must still match the right recording. Groups are peeled
// from the end until one is content-bearing or unknown.
func cleanDescriptiveTitle(s string) string {
	s = strings.TrimSpace(s)
	for {
		start, inner, ok := trailingGroup(s)
		if !ok || start == 0 || !isNoiseGroup(inner) {
			break
		}
		s = strings.TrimSpace(s[:start])
	}
	return s
}

// stripTrailingParenthetical removes one trailing bracketed group from an
// artist, folding aliases, features, and producer tags ("Amir Obe (Phreshy
// Duzit)" -> "Amir Obe") so the search keys on the canonical artist. Artists
// whose canonical name is entirely parenthetical are left untouched.
func stripTrailingParenthetical(artist string) string {
	s := strings.TrimSpace(artist)
	if start, _, ok := trailingGroup(s); ok && start > 0 {
		return strings.TrimSpace(s[:start])
	}
	return s
}

// trailingGroup locates a balanced "(...)" or "[...]" group at the very end of
// s, returning the opener's index and the inner text. ok is false when s does
// not end in such a group.
func trailingGroup(s string) (start int, inner string, ok bool) {
	s = strings.TrimRight(s, " ")
	if s == "" {
		return 0, "", false
	}
	var open, close byte
	switch s[len(s)-1] {
	case ')':
		open, close = '(', ')'
	case ']':
		open, close = '[', ']'
	default:
		return 0, "", false
	}
	depth := 0
	for i := len(s) - 1; i >= 0; i-- {
		switch s[i] {
		case close:
			depth++
		case open:
			depth--
			if depth == 0 {
				return i, s[i+1 : len(s)-1], true
			}
		}
	}
	return 0, "", false
}

// contentWords name a distinct recording; a group containing one is never
// stripped, so a remix or live take still matches the right recording.
var contentWords = []string{
	"remix", "live", "acoustic", "remaster", "version", "edit", "instrumental",
	"cover", "demo", "reprise", "feat", "ft.", "featuring", "mono", "stereo",
	"extended", "unplugged", "dub", "vip", "bootleg", "rework", "mashup",
	"interlude", "skit", "freestyle", "session", "alternate", "slowed",
	"reverb", "sped up", "nightcore", "bass boosted",
}

// noiseWords mark a production/upload note with no bearing on the recording's
// identity; a group containing one (and no content word) is stripped.
var noiseWords = []string{
	"official", "lyric", "visualizer", "visualiser", "audio", "video", "hd",
	"hq", "4k", "8k", "explicit", "clean", "m/v", "mv", "prod", "produced",
	"directed", "out now", "premiere", "teaser", "trailer", "music video",
	"color coded", "colour coded", "legendado", "promo",
}

// isNoiseGroup reports whether a bracketed group is a strippable production note:
// it names no distinct recording yet matches a known upload-note keyword.
func isNoiseGroup(inner string) bool {
	l := strings.ToLower(strings.TrimSpace(inner))
	if l == "" {
		return false
	}
	for _, w := range contentWords {
		if strings.Contains(l, w) {
			return false
		}
	}
	for _, w := range noiseWords {
		if strings.Contains(l, w) {
			return true
		}
	}
	return false
}

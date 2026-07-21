package match

import (
	"strings"
	"unicode"
)

// normalize lowercases, folds common Latin diacritics to ASCII, replaces
// punctuation with spaces and collapses runs of whitespace, so string
// distance compares words rather than typography.
func normalize(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range strings.ToLower(s) {
		if folded, ok := diacritics[r]; ok {
			b.WriteRune(folded)
			continue
		}
		switch {
		case r == '&':
			b.WriteString(" and ")
		case unicode.IsLetter(r) || unicode.IsDigit(r):
			b.WriteRune(r)
		default:
			b.WriteByte(' ')
		}
	}
	return strings.Join(strings.Fields(b.String()), " ")
}

// diacritics folds the Latin accented range to base letters. Scripts
// outside it (CJK, Cyrillic, Greek) pass through untouched and compare
// against themselves, which is the correct behavior: transliteration
// would fabricate similarity that is not there.
var diacritics = map[rune]rune{
	'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a',
	'ç': 'c', 'ć': 'c', 'č': 'c', 'ĉ': 'c', 'ċ': 'c',
	'ď': 'd', 'đ': 'd', 'ð': 'd',
	'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ĕ': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
	'ĝ': 'g', 'ğ': 'g', 'ġ': 'g', 'ģ': 'g',
	'ĥ': 'h', 'ħ': 'h',
	'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i', 'ĩ': 'i', 'ī': 'i', 'ĭ': 'i', 'į': 'i', 'ı': 'i',
	'ĵ': 'j',
	'ķ': 'k',
	'ĺ': 'l', 'ļ': 'l', 'ľ': 'l', 'ŀ': 'l', 'ł': 'l',
	'ñ': 'n', 'ń': 'n', 'ņ': 'n', 'ň': 'n',
	'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o', 'ō': 'o', 'ŏ': 'o', 'ő': 'o',
	'ŕ': 'r', 'ŗ': 'r', 'ř': 'r',
	'ś': 's', 'ŝ': 's', 'ş': 's', 'š': 's', 'ß': 's',
	'ţ': 't', 'ť': 't', 'ŧ': 't',
	'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u', 'ũ': 'u', 'ū': 'u', 'ŭ': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u',
	'ŵ': 'w',
	'ý': 'y', 'ÿ': 'y', 'ŷ': 'y',
	'ź': 'z', 'ż': 'z', 'ž': 'z',
	'æ': 'a', 'œ': 'o', 'þ': 't',
}

// stripFeat removes a trailing featured artist clause from an already
// normalized string ("song feat someone" and "song" compare equal).
// Markers are whole normalized words; "with" is deliberately absent
// because it is too common a genuine title word to cut on.
func stripFeat(s string) string {
	words := strings.Fields(s)
	for i := 1; i < len(words); i++ {
		switch words[i] {
		case "feat", "featuring", "ft":
			return strings.Join(words[:i], " ")
		}
	}
	return s
}

// editionWords are the trailing words stripEdition may remove from a
// normalized album title. Parentheses are already spaces after
// normalize, so "Album (Deluxe Edition)" arrives as trailing words and
// "album deluxe edition" compares closely with "album" without erasing
// genuine title words.
var editionWords = []string{
	"deluxe", "edition", "remaster", "remastered", "expanded", "anniversary",
	"bonus", "version", "reissue", "special", "disc", "mono", "stereo",
}

func stripEdition(s string) string {
	words := strings.Fields(s)
	end := len(words)
	for end > 0 {
		w := words[end-1]
		if isEditionWord(w) || isYear(w) {
			end--
			continue
		}
		break
	}
	if end == 0 || end == len(words) {
		return s
	}
	return strings.Join(words[:end], " ")
}

func isEditionWord(w string) bool {
	for _, e := range editionWords {
		if w == e {
			return true
		}
	}
	return false
}

func isYear(w string) bool {
	if len(w) != 4 {
		return false
	}
	for _, r := range w {
		if r < '0' || r > '9' {
			return false
		}
	}
	return w[0] == '1' || w[0] == '2'
}

// levenshtein returns the edit distance between two strings by rune.
func levenshtein(a, b string) int {
	ra, rb := []rune(a), []rune(b)
	if len(ra) == 0 {
		return len(rb)
	}
	if len(rb) == 0 {
		return len(ra)
	}
	prev := make([]int, len(rb)+1)
	cur := make([]int, len(rb)+1)
	for j := range prev {
		prev[j] = j
	}
	for i := 1; i <= len(ra); i++ {
		cur[0] = i
		for j := 1; j <= len(rb); j++ {
			cost := 1
			if ra[i-1] == rb[j-1] {
				cost = 0
			}
			cur[j] = min(prev[j]+1, min(cur[j-1]+1, prev[j-1]+cost))
		}
		prev, cur = cur, prev
	}
	return prev[len(rb)]
}

// stringDist returns a normalized edit distance in [0,1] between two raw
// strings, comparing their normalized forms. Two empty strings are
// identical; one empty side is maximally distant.
func stringDist(a, b string) float64 {
	na, nb := normalize(a), normalize(b)
	if na == nb {
		return 0
	}
	if na == "" || nb == "" {
		return 1
	}
	d := levenshtein(na, nb)
	longest := len([]rune(na))
	if l := len([]rune(nb)); l > longest {
		longest = l
	}
	return float64(d) / float64(longest)
}

// titleDist compares track or artist strings, forgiving featured artist
// suffixes on either side.
func titleDist(a, b string) float64 {
	d := stringDist(a, b)
	if d == 0 {
		return 0
	}
	if s := stringDist(stripFeat(normalize(a)), stripFeat(normalize(b))); s < d {
		d = s
	}
	return d
}

// albumDist compares album titles, forgiving edition and remaster
// suffixes on either side at a small penalty so the plain title still
// wins a tie against the annotated one.
func albumDist(a, b string) float64 {
	d := stringDist(a, b)
	if d == 0 {
		return 0
	}
	const editionPenalty = 0.05
	if s := stringDist(stripEdition(normalize(a)), stripEdition(normalize(b))); s+editionPenalty < d {
		d = s + editionPenalty
	}
	return d
}

// Package sourcenoise reads the noise video platforms add to titles and
// uploader names: YouTube's " - Topic" channel suffix, "(Official Video)"
// style upload notes, "Artist - Track" descriptive titles, version tails, and
// the description YouTube generates for Art Track uploads. Words are matched
// whole, never as substrings, so "(Prodigal)" is not a producer note.
package sourcenoise

import (
	"slices"
	"strings"
	"unicode"
)

// StripTopicSuffix removes YouTube's auto-generated " - Topic" channel suffix
// from an artist. Topic channels are the Art Track auto-channels YouTube mints
// with labels and distributors, named "<Artist> - Topic"; the suffix is machine
// appended and never part of the artist name. The match is case-insensitive
// and tolerates trailing space.
func StripTopicSuffix(artist string) string {
	const suffix = " - topic"
	a := strings.TrimRight(artist, " ")
	if strings.HasSuffix(strings.ToLower(a), suffix) {
		return strings.TrimSpace(a[:len(a)-len(suffix)])
	}
	return artist
}

// artistTrackSeparators split a descriptive "Artist - Track" title, in
// precedence order: hyphen, en dash, em dash. Each is surrounded by spaces so
// hyphenated words ("Twenty-One") never split.
var artistTrackSeparators = []string{" - ", " \u2013 ", " \u2014 "}

// SplitArtistTitle splits a descriptive title on the first artist/track
// separator. Both sides must be non-empty after trimming for the split to count.
func SplitArtistTitle(title string) (artist, track string, ok bool) {
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

// StripVersionTail drops trailing " - <version note>" segments from a title
// ("Bohemian Rhapsody - Remastered 2011" -> "Bohemian Rhapsody"), last first,
// until the last segment names a track or one segment is left.
func StripVersionTail(title string) string {
	head, _ := VersionTails(title)
	return head
}

// VersionTails is StripVersionTail with the tails it dropped, last first.
func VersionTails(title string) (head string, tails []string) {
	s := strings.TrimSpace(title)
	for {
		h, tail, ok := cutLastSeparator(s)
		if !ok || !IsVersionTail(tail) {
			return s, tails
		}
		s, tails = h, append(tails, tail)
	}
}

// SameRecordingTail reports whether a version tail leaves the recording as it
// was: a remaster form, "Bonus Track", or what a song is from, read the way a
// written title is cleaned, so a cut beside it ("2015 Remaster (Clean)")
// names another cut and is not. A live take, an edit, a mix or a demo is
// another recording.
func SameRecordingTail(s string) bool {
	s, cuts := SplitCutGroups(s)
	if cuts != "" {
		return false
	}
	w := words(s)
	if len(w) == 0 {
		return false
	}
	return isRemasterTail(w) || isBonusTrack(w) || isFromTail(s, w)
}

// cutLastSeparator splits s on its last artist/track separator, both sides
// non-empty after trimming.
func cutLastSeparator(s string) (head, tail string, ok bool) {
	at, width := -1, 0
	for _, sep := range artistTrackSeparators {
		if i := strings.LastIndex(s, sep); i > at {
			at, width = i, len(sep)
		}
	}
	if at <= 0 {
		return "", "", false
	}
	head, tail = strings.TrimSpace(s[:at]), strings.TrimSpace(s[at+width:])
	return head, tail, head != "" && tail != ""
}

// CleanDescriptiveTitle strips trailing production-note groups a title picks up
// on video platforms ("(Official Video)", "[Lyrics]", "(Prod. by ...)") while
// keeping groups that name a distinct recording ("(Live)", "(Remix)", "(feat.
// ...)"). Groups are peeled from the end until one is content-bearing or
// unknown; a title that is nothing but a group is kept.
func CleanDescriptiveTitle(s string) string {
	return peelGroups(s, IsNoiseGroup, nil)
}

// CleanUploadNotes is CleanDescriptiveTitle for a title that is written back
// rather than searched for: a group that marks a different cut of the song
// ("(Clean)", "(8D Audio)", "(Teaser)") is kept whole, and the upload notes
// before it still go ("Song (Official Audio) (Explicit)" -> "Song (Explicit)"),
// since dropping it would file that cut as the plain recording.
func CleanUploadNotes(s string) string {
	cut := func(inner string) bool { return IsNoiseGroup(inner) && containsAny(words(inner), cutMarkers) }
	return peelGroups(s, func(inner string) bool { return IsNoiseGroup(inner) && !cut(inner) }, cut)
}

// CoreTitle is the title a search asks for, the song alone: version tails
// go, and so do the trailing groups that are upload notes, cut marks,
// remaster notes or name a recording ("(Live at X)", "(X Remix)", "(Demo)").
// MusicBrainz titles a live take or an alternate by the song, so a phrase
// holding more finds nothing, while the song's own phrase lists the remix
// titled "Song (X remix)" as well. A group that is none of those ("(Part
// 2)", "(feat. X)") ends the peeling.
func CoreTitle(s string) string {
	s = strings.TrimSpace(s)
	for {
		next := peelGroups(StripVersionTail(s), func(inner string) bool {
			return IsNoiseGroup(inner) || IsRemasterNote(inner) || namesRecording(inner)
		}, nil)
		if next == s {
			return s
		}
		s = next
	}
}

// namesRecording reports whether a bracketed group's inner text names a
// recording of the song: a content word other than a guest credit, a mix, or
// what reads as a version tail ("Bonus Track", "Live 1977").
func namesRecording(inner string) bool {
	w := words(inner)
	if len(w) == 0 || containsAny(w, guestWords) {
		return false
	}
	return containsAny(w, contentWords) || slices.Contains(w, "mix") || IsVersionTail(inner)
}

// NamesCut reports whether a group's inner text or a tail names a cut of the
// song other than the recording itself: a cut mark ("Clean", "8D Audio") or
// what names another recording ("Live", "X Remix", "Demo", "Acoustic",
// "Radio Edit"). A remaster note, "Bonus Track", what a song is from, an
// album, single or explicit version and "Original Mix" name none: they label
// the plain recording.
func NamesCut(s string) bool {
	w := words(s)
	if isPlainVersion(w) {
		return false
	}
	if containsAny(w, cutMarkers) {
		return true
	}
	return !SameRecordingTail(s) && namesRecording(s)
}

// isPlainVersion: "Album Version", "Single Version", "Original Version",
// "Explicit", "Explicit Version", "Original Mix".
func isPlainVersion(w []string) bool {
	switch {
	case slices.Equal(w, []string{"explicit"}), slices.Equal(w, []string{"original", "mix"}):
		return true
	case len(w) < 2 || w[len(w)-1] != "version":
		return false
	}
	for _, t := range w[:len(w)-1] {
		if !isYear(t) && !anyWord(t, []string{"album", "single", "original", "lp", "explicit"}) {
			return false
		}
	}
	return true
}

// CleanCutTitle is CleanUploadNotes that also drops a remaster note: what is
// left names the recording and the cut, for judging which recording a title
// names ("Song (2020 Remaster) (Clean)" -> "Song (Clean)").
func CleanCutTitle(s string) string {
	rest, cuts := SplitCutGroups(s)
	if cuts == "" {
		return rest
	}
	return rest + " " + cuts
}

// SplitCutGroups is CleanCutTitle in two parts: the title without its upload
// and remaster notes and its cuts, and the cut groups CleanCutTitle keeps, in
// order ("" for none).
func SplitCutGroups(s string) (rest, cuts string) {
	cut := func(inner string) bool { return IsNoiseGroup(inner) && containsAny(words(inner), cutMarkers) }
	strip := func(inner string) bool { return (IsNoiseGroup(inner) && !cut(inner)) || IsRemasterNote(inner) }
	rest, kept := peel(s, strip, cut)
	return rest, strings.Join(kept, " ")
}

// IsRemasterNote reports whether a bracketed group's inner text is a remaster
// note and nothing else: "2020 Remaster", "Remastered 2011", "Remastered
// Version".
func IsRemasterNote(inner string) bool {
	w := words(inner)
	return len(w) > 0 && isRemasterTail(w)
}

// peelGroups strips trailing bracketed groups while strip says so, stepping
// past the ones keep says to hold and putting them back after; a title that
// is nothing but groups keeps the rest.
func peelGroups(s string, strip, keep func(inner string) bool) string {
	s, kept := peel(s, strip, keep)
	for _, g := range kept {
		s += " " + g
	}
	return s
}

// peel is peelGroups apart: what is left, and the held groups in order.
func peel(s string, strip, keep func(inner string) bool) (string, []string) {
	s = strings.TrimSpace(s)
	var kept []string
	for {
		start, inner, ok := TrailingGroup(s)
		if !ok || start == 0 {
			break
		}
		if keep != nil && keep(inner) {
			kept = append(kept, strings.TrimSpace(s[start:]))
		} else if !strip(inner) {
			break
		}
		s = strings.TrimSpace(s[:start])
	}
	slices.Reverse(kept)
	return s, kept
}

// StripTrailingParenthetical removes one trailing bracketed group from an
// artist, folding aliases, features, and producer tags ("Amir Obe (Phreshy
// Duzit)" -> "Amir Obe"). Artists whose name is entirely parenthetical are
// left untouched.
func StripTrailingParenthetical(artist string) string {
	s := strings.TrimSpace(artist)
	if start, _, ok := TrailingGroup(s); ok && start > 0 {
		return strings.TrimSpace(s[:start])
	}
	return s
}

// TrailingGroup locates a balanced "(...)" or "[...]" group at the very end of
// s, returning the opener's index and the inner text. ok is false when s does
// not end in such a group.
func TrailingGroup(s string) (start int, inner string, ok bool) {
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

// contentWords name a distinct recording; a group holding one is never
// stripped, so a remix or live take still matches the right recording.
var contentWords = phrases(
	"remix", "live", "acoustic", "remaster", "version", "edit", "instrumental",
	"cover", "demo", "reprise", "feat", "ft.", "featuring", "mono", "stereo",
	"extended", "unplugged", "dub", "vip", "bootleg", "rework", "mashup",
	"interlude", "skit", "freestyle", "session", "alternate", "slowed",
	"reverb", "sped up", "nightcore", "bass boosted",
)

// guestWords are the content words that credit a guest rather than name a
// recording.
var guestWords = phrases("feat", "ft.", "featuring")

// noiseWords mark a production or upload note with no bearing on the
// recording's identity; a group holding one (and no content word) is stripped.
var noiseWords = phrases(
	"official", "lyric", "visualizer", "visualiser", "audio", "video", "hd",
	"hq", "4k", "8k", "explicit", "clean", "m/v", "mv", "prod", "produced",
	"directed", "out now", "premiere", "teaser", "trailer",
	"color coded", "colour coded", "legendado", "promo",
)

// cutMarkers are noise words to a search that still name a different cut of
// the song, so a written title keeps a group holding one.
var cutMarkers = phrases("clean", "explicit", "8d", "teaser", "trailer")

// versionModifiers may precede the last word of a "Radio Edit" style tail.
var versionModifiers = []string{
	"radio", "single", "album", "extended", "original", "acoustic",
	"instrumental", "mono", "stereo", "club", "demo", "remastered", "deluxe",
	"explicit", "clean",
}

// versionAlone are version notes on their own: "Mono", "Demo".
var versionAlone = []string{"mono", "stereo", "acoustic", "instrumental", "demo"}

// livePlaces introduce where a live take was recorded: "Live at Wembley".
var livePlaces = []string{"at", "in", "from", "on"}

// soundtrackWords say what a "From ..." tail is from. A bare "game" is not
// one: "From the Game" is a track name.
var soundtrackWords = phrases(
	"soundtrack", "motion picture", "film", "movie", "series", "musical",
	"ost", "score", "video game",
)

// soundtrackFillers may sit between "From" and its soundtrack word: "From
// The Original Motion Picture Soundtrack".
var soundtrackFillers = []string{"the", "a", "an", "original"}

// inflections are the endings a listed word may carry and still count:
// "Lyrics", "Remastered", "Remixes", "Videos".
var inflections = []string{"s", "es", "ed", "d"}

// IsNoiseGroup reports whether a bracketed group's inner text is a strippable
// production note: it names no distinct recording yet holds an upload-note word
// or phrase.
func IsNoiseGroup(inner string) bool {
	w := words(inner)
	if len(w) == 0 || containsAny(w, contentWords) {
		return false
	}
	return containsAny(w, noiseWords)
}

// IsVersionTail reports whether the right side of an "A - B" title is, as a
// whole, a version note rather than a track name: a remaster form
// ("Remastered 2011", "2011 Remaster", "Remastered Version"), "Live" alone, at a
// place or with a year, a short "Radio Edit" / "Single Version" / "Extended
// Mix" phrase, "Mono", "Demo" and the like alone, "Bonus Track", or what a song
// is from ("From 'Film'", "From The Motion Picture"). Trailing upload notes
// are ignored. Anything else, "Live Forever" included, is a track name.
func IsVersionTail(s string) bool {
	s = CleanDescriptiveTitle(s)
	w := words(s)
	if len(w) == 0 {
		return false
	}
	switch {
	case isRemasterTail(w), isLiveTail(w), isVersionPhrase(w):
		return true
	case len(w) == 1 && anyWord(w[0], versionAlone):
		return true
	case isBonusTrack(w), isFromTail(s, w):
		return true
	}
	return false
}

func isBonusTrack(w []string) bool {
	return len(w) == 2 && wordMatches(w[0], "bonus") && wordMatches(w[1], "track")
}

// isFromTail: what a song is from, quoted ("From 'Film'") or a soundtrack.
func isFromTail(s string, w []string) bool {
	if w[0] != "from" || len(w) < 2 || !strings.HasPrefix(strings.ToLower(s), "from") {
		return false
	}
	rest := strings.TrimSpace(s[len("from"):])
	if r := []rune(rest); len(r) > 0 && strings.ContainsRune("'\"\u2018\u2019\u201c\u201d\u00ab", r[0]) {
		return true
	}
	return startsWithSoundtrack(w[1:])
}

// startsWithSoundtrack reports whether w opens with a soundtrack word, past
// any fillers: "The Motion Picture", not "Russia With Love The Film".
func startsWithSoundtrack(w []string) bool {
	for len(w) > 0 && slices.Contains(soundtrackFillers, w[0]) {
		w = w[1:]
	}
	for _, p := range soundtrackWords {
		if len(p) <= len(w) && phraseAt(w, p) {
			return true
		}
	}
	return false
}

// isRemasterTail: remaster forms with only years and "version" beside them.
func isRemasterTail(w []string) bool {
	found := false
	for _, t := range w {
		switch {
		case wordMatches(t, "remaster"):
			found = true
		case isYear(t), t == "version", t == "digital":
		default:
			return false
		}
	}
	return found
}

// isLiveTail: "Live", "Live 1977", or "Live at/in/from/on <place>".
func isLiveTail(w []string) bool {
	if w[0] != "live" {
		return false
	}
	switch {
	case len(w) == 1:
		return true
	case len(w) == 2 && isYear(w[1]):
		return true
	default:
		return len(w) >= 3 && anyWord(w[1], livePlaces)
	}
}

// isVersionPhrase: up to four words ending in version, edit or mix, every
// other word a version modifier or a year.
func isVersionPhrase(w []string) bool {
	if len(w) < 2 || len(w) > 4 {
		return false
	}
	last := w[len(w)-1]
	if !wordMatches(last, "version") && !wordMatches(last, "edit") && !wordMatches(last, "mix") {
		return false
	}
	for _, t := range w[:len(w)-1] {
		if !isYear(t) && !anyWord(t, versionModifiers) {
			return false
		}
	}
	return true
}

func anyWord(tok string, list []string) bool {
	for _, w := range list {
		if wordMatches(tok, w) {
			return true
		}
	}
	return false
}

func isYear(t string) bool {
	if len(t) != 4 || (!strings.HasPrefix(t, "19") && !strings.HasPrefix(t, "20")) {
		return false
	}
	for _, r := range t {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}

// words lowercases s and splits it into runs of letters and digits, so
// punctuation never joins or splits a word: "ft." is "ft", "m/v" is "m v".
func words(s string) []string {
	return strings.FieldsFunc(strings.ToLower(s), func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r)
	})
}

// phrases tokenizes each entry the way words does, so a listed phrase matches
// the same token run in a title.
func phrases(entries ...string) [][]string {
	out := make([][]string, 0, len(entries))
	for _, e := range entries {
		out = append(out, words(e))
	}
	return out
}

// containsAny reports whether toks holds any phrase as a contiguous run.
func containsAny(toks []string, list [][]string) bool {
	for _, p := range list {
		for i := 0; i+len(p) <= len(toks); i++ {
			if phraseAt(toks[i:], p) {
				return true
			}
		}
	}
	return false
}

// phraseAt reports whether toks opens with phrase p; len(toks) >= len(p).
func phraseAt(toks, p []string) bool {
	for j, pw := range p {
		if !wordMatches(toks[j], pw) {
			return false
		}
	}
	return true
}

// SameTitle reports whether two titles are the same words, ignoring case and
// punctuation: "Hello, World!" and "hello world" are.
func SameTitle(a, b string) bool {
	wa, wb := words(a), words(b)
	return len(wa) > 0 && slices.Equal(wa, wb)
}

func wordMatches(tok, w string) bool {
	if tok == w {
		return true
	}
	for _, suf := range inflections {
		if len(tok) == len(w)+len(suf) && strings.HasPrefix(tok, w) && strings.HasSuffix(tok, suf) {
			return true
		}
	}
	return false
}

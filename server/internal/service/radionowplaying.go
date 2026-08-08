package service

import (
	"context"
	"strings"
)

// Resolving a station's announced title to a track this library holds,
// so a full-screen player can draw the song's own cover instead of the
// station logo.
//
// The strict split lives in parseRadioTitle and stays there. That
// function decides what gets *scrobbled*, and listening history is not
// something to loosen for a nicer picture: a looser parse there would
// silently rewrite everyone's history, and a wrong scrobble cannot be
// taken back. So the extra normalization is here, on top of the shared
// parse, where the worst a miss can do is leave the station logo up -
// which is what the client draws anyway when nothing matches, and which
// is the common case rather than a failure state.

// maxNowPlayingMemo bounds the resolution memo. One live entry per
// (listener, station) pair is the working set, so this clears real use
// by a wide margin; the bound exists because the key includes a title a
// station chooses, and nothing that grows on a stranger's input gets to
// grow without a ceiling.
const maxNowPlayingMemo = 256

// nowPlayingMemo is one resolved title.
//
// Keyed by listener as well as station because the resolution runs
// through Search under that caller's visibility: two accounts can see
// different libraries, so one's answer is not the other's to reuse.
// A miss is memoized as readily as a hit - "this title matches nothing
// here" is the common answer and the one most worth not recomputing.
type nowPlayingMemo struct {
	title string
	pid   string
}

func nowPlayingMemoKey(userID, apiStationPID string) string {
	return userID + "\x00" + apiStationPID
}

func (l *Library) cachedNowPlayingItem(userID, apiStationPID, title string) (string, bool) {
	l.nowPlayingMemoMu.Lock()
	defer l.nowPlayingMemoMu.Unlock()
	entry, ok := l.nowPlayingMemos[nowPlayingMemoKey(userID, apiStationPID)]
	if !ok || entry.title != title {
		return "", false
	}
	return entry.pid, true
}

func (l *Library) memoNowPlayingItem(userID, apiStationPID, title, pid string) {
	l.nowPlayingMemoMu.Lock()
	defer l.nowPlayingMemoMu.Unlock()
	if l.nowPlayingMemos == nil {
		l.nowPlayingMemos = map[string]nowPlayingMemo{}
	}
	key := nowPlayingMemoKey(userID, apiStationPID)
	// One entry per pair, so the map only grows when a new pair appears
	// and a station changing its title replaces rather than accumulates.
	// Past the bound the whole map goes: an LRU over something this small
	// costs more to maintain than the recomputation it would save, and a
	// cleared memo is a slow poll rather than a wrong answer.
	if _, exists := l.nowPlayingMemos[key]; !exists &&
		len(l.nowPlayingMemos) >= maxNowPlayingMemo {
		l.nowPlayingMemos = map[string]nowPlayingMemo{}
	}
	l.nowPlayingMemos[key] = nowPlayingMemo{title: title, pid: pid}
}

// radioTitleNoise is what stations put around a track line: their own
// call sign, a stream label, a quality tag. Matched as bracketed or
// trailing fragments rather than anywhere in the string, so a song
// actually called "Live" survives.
var radioTitleNoise = []string{
	"official stream",
	"official audio",
	"official video",
	"hq audio",
	"live stream",
	"now playing",
	"radio edit",
	"clean edit",
	"explicit",
	"remastered",
	"hd",
	"hq",
}

// RadioNowPlayingItem resolves a station's announced title to a library
// track pid, empty when there is no confident match.
//
// The title is passed in rather than read here, and that is what keeps
// the answer consistent: the relay goroutine rewrites a station's title
// whenever the stream announces one, so a second read could describe a
// different song than the `nowPlaying` the caller is about to return
// beside it.
//
// Best effort by construction and by contract: the spec says the field
// is absent more often than not and that a client falls back to the
// station's artwork. Nothing downstream treats it as authoritative.
func (l *Library) RadioNowPlayingItem(ctx context.Context, uc *UserCtx, apiStationPID, stationName, raw string) string {
	if raw == "" {
		return ""
	}
	// Answered from the memo when this caller has already resolved this
	// exact title. Clients poll play-info every 15 seconds for the whole
	// time a station is on and a station announces every few minutes, so
	// without this the overwhelming majority of polls re-run an FTS
	// search that can only produce the answer already in hand.
	if pid, ok := l.cachedNowPlayingItem(uc.ID, apiStationPID, raw); ok {
		return pid
	}
	pid := l.resolveNowPlayingItem(ctx, uc, stationName, raw)
	l.memoNowPlayingItem(uc.ID, apiStationPID, raw, pid)
	return pid
}

func (l *Library) resolveNowPlayingItem(ctx context.Context, uc *UserCtx, stationName, raw string) string {
	artist, title, ok := parseRadioTitle(raw, stationName)
	if !ok {
		return ""
	}
	artist, title = normalizeRadioField(artist), normalizeRadioField(title)
	// Both halves have to survive normalization. A title alone matches
	// every cover version there is, and the artist is what makes the
	// answer this recording - so an artist that normalized away (a name
	// that was all punctuation, or entirely bracketed) is not something
	// to fall back from, it is a reason to draw no art at all. Letting it
	// through as a title-only match is the case the artist check below
	// exists to refuse.
	if title == "" || artist == "" {
		return ""
	}
	// Both halves, because a title alone matches every cover version and
	// the artist is what makes the answer this recording. A small limit:
	// the top hits are the only ones a confident match could be in.
	hits, err := l.Search(ctx, uc, artist+" "+title, 5)
	if err != nil {
		return ""
	}
	for _, hit := range hits.Tracks {
		// The title has to actually be the title. FTS ranks by relevance
		// and will happily return a near miss at the top, and a near
		// miss here is the wrong album cover over somebody's music.
		if !radioFieldsMatch(hit.Title, title) {
			continue
		}
		// The subtitle carries the artist, so the artist we parsed has to
		// appear in it. Guaranteed non-empty by the check above, so this
		// runs for every candidate rather than being skipped into a
		// title-only match.
		//
		// Whole words, not a substring. A bare strings.Contains puts the
		// wrong cover over somebody's music for every short artist name
		// there is: "Air" matches Chair, "Eve" matches Everything
		// Everything, "CAN" matches American Football. Short names are
		// exactly the ones a station is likeliest to announce bare, so
		// this is the common case rather than a corner of it.
		if !containsTokenRun(
			tokensOf(normalizeRadioField(hit.Subtitle)), tokensOf(artist)) {
			continue
		}
		return hit.PID
	}
	return ""
}

// radioFieldsMatch compares two normalized fields, allowing one to carry
// a suffix the other does not - "Ornithology" against "Ornithology (Take
// 1)" is the same recording as far as cover art goes. Bracketed asides
// are already gone by here, so what this covers is the unbracketed form
// ("Ornithology - Take 1").
//
// The extension is by whole words. A raw string prefix would take "Orni"
// for "Ornithology", which is never right; a word-boundary prefix takes
// "Love" for "Love Song", which is a real ambiguity and is left tolerated
// on purpose - the artist has to match too, so the worst it costs is a
// sibling track's cover.
func radioFieldsMatch(a, b string) bool {
	ta, tb := tokensOf(normalizeRadioField(a)), tokensOf(normalizeRadioField(b))
	if len(ta) == 0 || len(tb) == 0 {
		return false
	}
	return hasTokenPrefix(ta, tb) || hasTokenPrefix(tb, ta)
}

// tokensOf splits a normalized field into its words.
func tokensOf(s string) []string { return strings.Fields(s) }

// hasTokenPrefix reports whether have begins with every token of want.
func hasTokenPrefix(have, want []string) bool {
	if len(want) > len(have) {
		return false
	}
	for i, token := range want {
		if have[i] != token {
			return false
		}
	}
	return true
}

// containsTokenRun reports whether want's tokens appear as a contiguous
// run anywhere in have's, which is what makes "parker" match "charlie
// parker quintet" without letting "air" match "chair".
func containsTokenRun(have, want []string) bool {
	if len(want) == 0 || len(want) > len(have) {
		return false
	}
	for start := 0; start+len(want) <= len(have); start++ {
		if hasTokenPrefix(have[start:], want) {
			return true
		}
	}
	return false
}

// normalizeRadioField lowercases, strips bracketed asides and the noise
// stations append, and collapses whitespace and punctuation, so
// "Charlie Parker  [Official Stream]" and "charlie parker" meet.
func normalizeRadioField(s string) string { return normalizeRadioText(s, false) }

// radioSearchField is the same treatment for a field about to be sent to
// a metadata service rather than compared with this catalog: the
// apostrophe survives it.
//
// MusicBrainz indexes "that's" as a single token, so both of the
// spellings the plain normalization can produce - "that s", and "thats"
// if the mark were dropped instead - match nothing at all, and every
// announced title carrying an apostrophe drew no cover. Verified against
// the live service, which is also where the asymmetry showed up: "sweet
// child o mine" resolves either way, "thats what tequila does" only with
// the mark. Both the cache key and the query are built from this, so an
// entry and the search that filled it still cannot disagree.
func radioSearchField(s string) string { return normalizeRadioText(s, true) }

func normalizeRadioText(s string, keepApostrophe bool) string {
	s = strings.ToLower(strings.TrimSpace(s))
	// Folded before anything looks at it, so the two spellings of one
	// mark cannot take different paths through the rest: the typographic
	// apostrophe is above ASCII and used to survive as itself while the
	// straight one collapsed to a space, which left "Don't" and "Don't"
	// unable to match each other.
	s = strings.NewReplacer("’", "'", "ʼ", "'").Replace(s)
	s = stripBracketed(s)
	for _, noise := range radioTitleNoise {
		// Only as a trailing fragment, so a song called "Explicit" is
		// not normalized down to nothing.
		s = strings.TrimSpace(strings.TrimSuffix(strings.TrimSpace(s), noise))
	}
	var b strings.Builder
	space := false
	for _, r := range s {
		switch {
		case keepApostrophe && r == '\'':
			// Carried like a letter: it belongs to the word rather than
			// separating two.
			if space && b.Len() > 0 {
				b.WriteByte(' ')
			}
			space = false
			b.WriteRune(r)
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			if space && b.Len() > 0 {
				b.WriteByte(' ')
			}
			space = false
			b.WriteRune(r)
		case r > 127:
			// Anything outside ASCII is kept as it is: stripping it
			// would erase whole scripts, and the two sides are compared
			// after the same treatment either way.
			if space && b.Len() > 0 {
				b.WriteByte(' ')
			}
			space = false
			b.WriteRune(r)
		default:
			space = true
		}
	}
	return b.String()
}

// stripBracketed removes (...) and [...] spans, which is where stations
// put tags that are not part of the name.
func stripBracketed(s string) string {
	var b strings.Builder
	depth := 0
	for _, r := range s {
		switch r {
		case '(', '[':
			depth++
		case ')', ']':
			if depth > 0 {
				depth--
				continue
			}
			b.WriteRune(r)
		default:
			if depth == 0 {
				b.WriteRune(r)
			}
		}
	}
	return strings.TrimSpace(b.String())
}

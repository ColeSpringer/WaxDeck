package service

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	"golang.org/x/text/language"
)

// Prefs is the per-user preference document. Every field is optional;
// empty means unset and clients apply their own defaults. The document
// is stored as JSON in waxdeck.db, validated here so a typo never
// silently drops a preference.
type Prefs struct {
	Timezone string `json:"timezone,omitempty"`
	Locale   string `json:"locale,omitempty"`
	Theme    string `json:"theme,omitempty"`
	// SharedStatsOptOut removes this user's listening from the
	// server-wide aggregate stats. Personal stats are unaffected.
	SharedStatsOptOut bool `json:"sharedStatsOptOut,omitempty"`
	// RadioFavorites are the station PIDs this user has pinned, in dial
	// order. The station library is shared by the household, so this is
	// the only per-user station state there is.
	RadioFavorites []string `json:"radioFavorites,omitempty"`
	// Pinned are the entity PIDs this user has pinned to home, in shelf
	// order. The same shape and the same rules as RadioFavorites: a pin
	// is about the listener, not the machine they made it on.
	Pinned []string `json:"pinned,omitempty"`
	// CrossfadeSeconds and ReplayGain shape a queue the server renders
	// as one stream (a cast timeline today). They live on the account
	// rather than on the device because the reload path has no client
	// in it: a queue edit arrives over the control socket and the
	// server re-mints from what it holds.
	CrossfadeSeconds float64 `json:"crossfadeSeconds,omitempty"`
	ReplayGain       bool    `json:"replayGain,omitempty"`
	// RadioScrobbleOptOut silences radio scrobbling for this listener.
	RadioScrobbleOptOut bool `json:"radioScrobbleOptOut,omitempty"`
	// BrowseShowUnknown draws the bucket for items a dimension is absent
	// from. A presentation choice, not a server filter. Pointer here and
	// on Autoplay because absent means on and false is a choice.
	BrowseShowUnknown *bool `json:"browseShowUnknown,omitempty"`
	// BrowseSorts is the order each browse index opens in, by dimension
	// name. Sparse: an absent dimension opens in the client's default.
	BrowseSorts map[string]string `json:"browseSorts,omitempty"`
	// Autoplay lets playback start with no gesture behind it: a queue
	// handed over through Connect. A head-unit tap is a gesture.
	Autoplay *bool `json:"autoplay,omitempty"`
}

// maxCrossfadeSeconds matches the timeline endpoint's own bound, since
// this value is what that endpoint ends up being called with.
const maxCrossfadeSeconds = 12

var validThemes = map[string]bool{"system": true, "dark": true, "light": true, "oled": true}

// maxRadioFavorites bounds the stored list. A bound on the document
// rather than on the feature: clients present about a dozen on a dial and
// that cap is theirs, while this one exists so a preference document
// cannot be grown without limit.
const maxRadioFavorites = 64

// maxPinned bounds the pinned-to-home list, for maxRadioFavorites'
// reason. The shelf draws all of them, so this one is the feature's cap
// as well as the document's.
const maxPinned = 64

// pinnablePrefixes are the entity kinds a card can be drawn for and a tap
// can open. Radio stations are absent because the dial is already radio's
// pin surface; tracks and episodes are absent because a kept set of
// tracks is a playlist, and playlists pin.
var pinnablePrefixes = map[string]bool{
	PrefixAlbum:        true,
	PrefixArtist:       true,
	PrefixReleaseGroup: true,
	PrefixPlaylist:     true,
	PrefixPodcast:      true,
	PrefixBook:         true,
}

// maxBrowseSorts bounds the document, like maxRadioFavorites: seven
// named dimensions plus room for custom-tag ones.
const maxBrowseSorts = 32

// canonicalPIDList validates one of the document's ordered pid lists and
// returns it in the canonical form the contract's pattern declares.
//
// Shape only. Deliberately not resolved: a station or an album another
// household member deleted leaves its pid in somebody's list, and failing
// the whole document over it would make one departed entity cost a
// listener their theme. Clients render the pids they can still find.
//
// Upper-cased, which is two separate things at once. It is the pattern
// the contract declares, so what is read back matches what the schema
// says. And it is what makes the duplicate check work: Crockford base32
// parses either case, so `rs-01H...` and `rs-01h...` name one station and
// would otherwise be two entries - two slots for one thing, and a star
// that cannot unpin the one it drew.
//
// noun names the entry in a duplicate message ("duplicate pin al-..."),
// want names what the list accepts in a rejection ("not a station pid").
func canonicalPIDList(pids []string, prefixes map[string]bool, noun, want string) ([]string, error) {
	seen := make(map[string]bool, len(pids))
	out := make([]string, 0, len(pids))
	for _, pid := range pids {
		prefix, id, ok := parseAPIPID(pid)
		if !ok || !prefixes[prefix] {
			return nil, errInvalid("not " + want + ": " + pid)
		}
		canonical := prefix + "-" + strings.ToUpper(string(id))
		if seen[canonical] {
			return nil, errInvalid("duplicate " + noun + " " + canonical)
		}
		seen[canonical] = true
		out = append(out, canonical)
	}
	return out, nil
}

// Prefs returns the acting user's stored preferences.
func (l *Library) Prefs(ctx context.Context, uc *UserCtx) (Prefs, error) {
	doc, err := l.db.PrefsJSON(ctx, uc.ID)
	if err != nil {
		return Prefs{}, &Error{Kind: KindInternal, Err: err}
	}
	return l.decodePrefs(doc, uc.ID), nil
}

// PrefsForUser reads one user's preferences by ID, for the paths that
// have no acting caller: the stream proxy reporting a finished radio
// segment, and a cast session the server re-renders after a queue edit
// arrived over the control socket. A read that fails answers defaults
// rather than an error, because both callers are doing something else
// and neither has an outcome a preference should be able to fail.
func (l *Library) PrefsForUser(ctx context.Context, userID string) Prefs {
	doc, err := l.db.PrefsJSON(ctx, userID)
	if err != nil {
		l.log.Warn("reading prefs", "user", userID, "err", err)
		return Prefs{}
	}
	return l.decodePrefs(doc, userID)
}

func (l *Library) decodePrefs(doc, userID string) Prefs {
	if doc == "" {
		return Prefs{}
	}
	var p Prefs
	if err := json.Unmarshal([]byte(doc), &p); err != nil {
		// A corrupt document reads as empty rather than wedging the
		// account; the next save replaces it.
		l.log.Warn("corrupt prefs document", "user", userID, "err", err)
		return Prefs{}
	}
	return p
}

// PutPrefs validates and replaces the acting user's preferences,
// returning the stored result.
func (l *Library) PutPrefs(ctx context.Context, uc *UserCtx, p Prefs) (Prefs, error) {
	if p.Timezone != "" {
		if _, err := time.LoadLocation(p.Timezone); err != nil {
			return Prefs{}, errInvalid("unknown timezone " + p.Timezone)
		}
	}
	if p.Locale != "" {
		if _, err := language.Parse(p.Locale); err != nil {
			return Prefs{}, errInvalid("malformed locale " + p.Locale)
		}
	}
	if p.Theme != "" && !validThemes[p.Theme] {
		return Prefs{}, errInvalid("unknown theme " + p.Theme)
	}
	if len(p.RadioFavorites) > maxRadioFavorites {
		return Prefs{}, errInvalid(fmt.Sprintf("at most %d radio favorites", maxRadioFavorites))
	}
	if len(p.Pinned) > maxPinned {
		return Prefs{}, errInvalid(fmt.Sprintf("at most %d pins", maxPinned))
	}
	if p.CrossfadeSeconds < 0 || p.CrossfadeSeconds > maxCrossfadeSeconds {
		return Prefs{}, errInvalid(fmt.Sprintf("crossfadeSeconds must be between 0 and %d", maxCrossfadeSeconds))
	}
	if len(p.BrowseSorts) > maxBrowseSorts {
		return Prefs{}, errInvalid(fmt.Sprintf("at most %d browse sorts", maxBrowseSorts))
	}
	if len(p.BrowseSorts) > 0 {
		// Through facetGroupFor, which is what the browse endpoint itself
		// parses with: a prefix check would take "tag." followed by
		// anything, and the canonical form is what keeps two spellings of
		// one tag key from becoming two entries.
		sorts := make(map[string]string, len(p.BrowseSorts))
		for dim, sort := range p.BrowseSorts {
			_, canonical, err := facetGroupFor(dim)
			if err != nil {
				return Prefs{}, err
			}
			if _, dup := sorts[canonical]; dup {
				return Prefs{}, errInvalid("duplicate browse dimension " + canonical)
			}
			// Not through ParseFacetSort alone: it reads "" as the default
			// because the query parameter is optional, and storing that
			// would put a value outside the response enum in the document.
			if _, ok := validFacetSorts[FacetSort(sort)]; !ok {
				return Prefs{}, errInvalid("unknown facet sort " + sort)
			}
			sorts[canonical] = sort
		}
		p.BrowseSorts = sorts
	}
	favorites, err := canonicalPIDList(
		p.RadioFavorites,
		map[string]bool{PrefixRadioStation: true},
		"radio favorite", "a station pid",
	)
	if err != nil {
		return Prefs{}, err
	}
	if len(favorites) > 0 {
		p.RadioFavorites = favorites
	}
	pinned, err := canonicalPIDList(p.Pinned, pinnablePrefixes, "pin", "a pinnable entity pid")
	if err != nil {
		return Prefs{}, err
	}
	if len(pinned) > 0 {
		p.Pinned = pinned
	}
	doc, err := json.Marshal(p)
	if err != nil {
		return Prefs{}, &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.PutPrefsJSON(ctx, uc.ID, string(doc)); err != nil {
		return Prefs{}, &Error{Kind: KindInternal, Err: err}
	}
	l.emitUserEvent(ctx, uc.ID, eventPrefs, "")
	return p, nil
}

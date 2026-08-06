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

// maxBrowseSorts bounds the document, like maxRadioFavorites: seven
// named dimensions plus room for custom-tag ones.
const maxBrowseSorts = 32

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
	seen := make(map[string]bool, len(p.RadioFavorites))
	favorites := make([]string, 0, len(p.RadioFavorites))
	for _, pid := range p.RadioFavorites {
		// Shape only. Deliberately not resolved: a station another
		// household member deleted leaves its pid in somebody's dial, and
		// failing the whole document over it would make one departed
		// station cost a listener their theme. Clients render the pids
		// they can still find.
		prefix, id, ok := parseAPIPID(pid)
		if !ok || prefix != PrefixRadioStation {
			return Prefs{}, errInvalid("not a station pid: " + pid)
		}
		// Stored upper-case, which is the only form this list may hold and
		// two separate things at once. It is the pattern the contract
		// declares, so what is read back matches what the schema says. And
		// it is what makes the duplicate check work: Crockford base32
		// parses either case, so `rs-01H...` and `rs-01h...` name one station
		// and would otherwise be two entries - two dial slots for the same
		// station, and a star that cannot unpin the one it drew.
		canonical := prefix + "-" + strings.ToUpper(string(id))
		if seen[canonical] {
			return Prefs{}, errInvalid("duplicate radio favorite " + canonical)
		}
		seen[canonical] = true
		favorites = append(favorites, canonical)
	}
	if len(favorites) > 0 {
		p.RadioFavorites = favorites
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

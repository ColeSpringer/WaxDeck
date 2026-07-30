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
}

var validThemes = map[string]bool{"system": true, "dark": true, "light": true, "oled": true}

// maxRadioFavorites bounds the stored list. A bound on the document
// rather than on the feature: clients present about a dozen on a dial and
// that cap is theirs, while this one exists so a preference document
// cannot be grown without limit.
const maxRadioFavorites = 64

// Prefs returns the acting user's stored preferences.
func (l *Library) Prefs(ctx context.Context, uc *UserCtx) (Prefs, error) {
	doc, err := l.db.PrefsJSON(ctx, uc.ID)
	if err != nil {
		return Prefs{}, &Error{Kind: KindInternal, Err: err}
	}
	if doc == "" {
		return Prefs{}, nil
	}
	var p Prefs
	if err := json.Unmarshal([]byte(doc), &p); err != nil {
		// A corrupt document reads as empty rather than wedging the
		// account; the next save replaces it.
		l.log.Warn("corrupt prefs document", "user", uc.ID, "err", err)
		return Prefs{}, nil
	}
	return p, nil
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

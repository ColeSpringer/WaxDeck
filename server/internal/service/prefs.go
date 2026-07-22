package service

import (
	"context"
	"encoding/json"
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
}

var validThemes = map[string]bool{"system": true, "dark": true, "light": true, "oled": true}

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

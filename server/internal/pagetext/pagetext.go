// Package pagetext holds the words on the three pages WaxDeck renders
// itself: the share landing page, the OIDC sign-on pages, and the
// Last.fm callback. None of them loads the app, so no client-side
// translation can reach them, and their readers are the least likely to
// speak the instance owner's language - a stranger opening a shared
// link on a phone most of all.
//
// The JSON API stays English by decision, so this is the only place the
// server picks words by locale.
package pagetext

import (
	"strings"
	"time"

	"golang.org/x/text/language"
)

// tables is every language this package can render, and the one place a
// locale is wired up: a switch could miss one, and since the miss
// degrades to English it would look correct from the inside.
var tables = map[language.Tag]*Strings{
	language.English: &en,
	language.Spanish: &es,
}

// supported is the negotiation order, and index 0 is the fallback: an
// Accept-Language that matches nothing lands on English. Every entry
// must have a table (TestEverySupportedLanguageHasATable).
var supported = []language.Tag{language.English, language.Spanish}

var matcher = language.NewMatcher(supported)

// Negotiate picks a supported language from an Accept-Language header.
// An absent, malformed, or unmatched header answers the fallback, so a
// caller never has to check.
func Negotiate(acceptLanguage string) language.Tag {
	tags, _, err := language.ParseAcceptLanguage(acceptLanguage)
	if err != nil {
		// The parser is all-or-nothing: one bad entry anywhere discards
		// the whole header, first choice included. Proxies do append
		// junk, and answering English to a header opening with `es`
		// reads it worse than ignoring the junk does.
		tags = parseTolerantly(acceptLanguage)
	}
	if len(tags) == 0 {
		return supported[0]
	}
	// The index, not the returned tag: Match answers the caller's own
	// tag shape (es-MX for a Spanish speaker in Mexico), and what this
	// package holds tables for is the supported entry it matched.
	_, idx, _ := matcher.Match(tags...)
	return supported[idx]
}

// parseTolerantly keeps the entries of a malformed header that do
// parse, in written order. Quality weights are dropped rather than
// honored: a header this broken cannot be read precisely, and written
// order is a better guess than nothing.
func parseTolerantly(acceptLanguage string) []language.Tag {
	var tags []language.Tag
	for entry := range strings.SplitSeq(acceptLanguage, ",") {
		entry, _, _ = strings.Cut(entry, ";")
		tag, err := language.Parse(strings.TrimSpace(entry))
		if err == nil {
			tags = append(tags, tag)
		}
	}
	return tags
}

// For is the table for a tag, English for one this build has none for.
func For(tag language.Tag) *Strings {
	if t, ok := tables[tag]; ok {
		return t
	}
	return &en
}

// Strings is every word the rendered pages draw, a field per string
// rather than a keyed map: a translation that forgets one fails
// TestLocalesAreComplete instead of rendering a blank line, and a
// mistyped key does not compile. FormatDate is a field for the same
// reason - a new locale cannot forget that dates are worded too.
type Strings struct {
	// Lang is the html lang attribute.
	Lang string

	// FormatDate renders a date the way this locale writes one.
	FormatDate func(t time.Time) string

	ShareDownload      string
	ShareSharedWith    string
	ShareExpiresPrefix string
	ShareNotFoundTitle string
	ShareNotFoundBody  string

	OidcTitle              string
	OidcCodeHeading        string
	OidcCodeBody           string
	OidcErrorHeading       string
	OidcBackLink           string
	OidcNotConfigured      string
	OidcProviderReported   string // fmt: %s %s (error, description)
	OidcIncompleteCallback string
	OidcCouldNotComplete   string
	OidcUnknownMode        string

	LastfmFailedTitle    string
	LastfmFailedBody     string
	LastfmConnectedTitle string
	LastfmConnectedBody  string // fmt: %s (username)
}

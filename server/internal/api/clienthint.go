package api

import (
	"strings"
	"unicode/utf8"
)

// The device list names what is signed in. A raw `User-Agent` is the
// wrong thing to name it with: "Mozilla/5.0 (Windows NT 10.0; Win64;
// x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.7922.34
// Safari/537.36" is one row of a list somebody is deciding what to
// revoke from, and every browser on earth begins it identically.
//
// So a browser agent is summarized to the two facts that distinguish one
// session from another - which browser, on which system - and everything
// else is left as the product token it already is, because a real client
// ("Symfonium/12.3", "WaxDeck/0.1.0") names itself perfectly well.

// clientLabelMax bounds what is stored. Well past any summary; it exists
// for the fallback path, where an unrecognized agent is kept as-is.
const clientLabelMax = 64

// browserToken is one browser's marker in a user agent, with the name to
// report for it.
//
// The order is the whole of this table's correctness and is the reverse
// of intuition: every Chromium browser claims to be Chrome, Chrome
// claims to be Safari, and Safari claims to be Mozilla. So the most
// specific marker has to be tested first, and Safari - which is the only
// one of these that claims nothing else - has to be last.
var browserTokens = []struct{ token, name string }{
	{"Edg/", "Edge"},
	{"EdgiOS/", "Edge"},
	{"OPR/", "Opera"},
	{"SamsungBrowser/", "Samsung Internet"},
	{"Vivaldi/", "Vivaldi"},
	{"Brave/", "Brave"},
	{"YaBrowser/", "Yandex"},
	{"Firefox/", "Firefox"},
	{"FxiOS/", "Firefox"},
	{"CriOS/", "Chrome"},
	{"Chromium/", "Chromium"},
	{"Chrome/", "Chrome"},
	{"Safari/", "Safari"},
}

// systemTokens maps a user agent's platform marker to a system name.
// Ordered for the same reason: an iPad reports "Mac OS X" beside
// "iPad", and Android reports "Linux" beside "Android".
var systemTokens = []struct{ token, name string }{
	{"iPhone", "iOS"},
	{"iPad", "iPadOS"},
	{"Android", "Android"},
	{"CrOS", "ChromeOS"},
	{"Windows", "Windows"},
	{"Mac OS X", "macOS"},
	{"Macintosh", "macOS"},
	{"FreeBSD", "FreeBSD"},
	{"Linux", "Linux"},
	{"X11", "Linux"},
}

// summarizeClient turns a `User-Agent` into the short label the device
// list shows. An agent it does not recognize is returned trimmed and
// bounded rather than replaced by "Unknown": the string a client chose
// for itself is more use to whoever is reading the list than a word this
// server made up.
func summarizeClient(ua string) string {
	ua = strings.TrimSpace(ua)
	if ua == "" {
		return ""
	}
	if browser, ok := browserOf(ua); ok {
		if system, ok := systemOf(ua); ok {
			return browser + " on " + system
		}
		return browser
	}
	return truncateRunes(ua, clientLabelMax)
}

func browserOf(ua string) (string, bool) {
	for _, b := range browserTokens {
		if strings.Contains(ua, b.token) {
			return b.name, true
		}
	}
	return "", false
}

func systemOf(ua string) (string, bool) {
	for _, s := range systemTokens {
		if strings.Contains(ua, s.token) {
			return s.name, true
		}
	}
	return "", false
}

// truncateRunes cuts to at most n bytes and drops every byte that is not
// part of a valid UTF-8 sequence, so an exotic agent never persists as
// invalid UTF-8.
//
// The validity pass runs whether or not anything was cut. A short agent
// is the case that makes that matter: a four-byte header from a Latin-1
// device is already under the bound, so a fast path past this would
// store the invalid bytes as-is - into a SQLite TEXT column, and back
// out of the devices endpoint forever.
//
// Dropped wherever they are rather than trimmed off the end, which is
// what keeps the readable part of a mostly-valid agent: bytes go missing
// at the front too, and a cut at n can split the rune it lands in.
func truncateRunes(s string, n int) string {
	if len(s) > n {
		s = s[:n]
	}
	if !utf8.ValidString(s) {
		s = strings.ToValidUTF8(s, "")
	}
	return strings.TrimSpace(s)
}

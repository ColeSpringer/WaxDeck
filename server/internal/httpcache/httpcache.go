// Package httpcache holds the conditional-request helpers the HTTP
// surfaces share. It exists because the first-party API and the Subsonic
// adapter mint the same validators for the same bytes, and a copy of
// this logic in each would drift.
package httpcache

import "strings"

// ETagMatches reports whether an If-None-Match header selects etag.
//
// Two things exact equality on the raw header gets wrong. The header is
// a comma-separated list, which a cache holding several variants of one
// URL sends (and a `Vary` on the credential is exactly what makes a
// shared cache hold several). And the comparison is the weak one (RFC
// 9110 section 13.1.2), so a validator echoed back as `W/"x"` matches
// the `"x"` that was issued. Getting either wrong costs a full body
// where a 304 would do, which is the entire thing a conditional request
// exists to avoid.
//
// Splitting on commas is what net/http does internally and is safe for
// the validators this server mints (a quoted hash, sometimes with a
// suffix); an entity-tag may legally contain a comma, and none of ours
// does.
//
// `*` is deliberately not handled. It means "if any representation
// exists", a write-precondition idiom no cache sends on a GET, and a
// request carrying it simply gets the full body, which is always a
// correct answer to a conditional request.
func ETagMatches(header, etag string) bool {
	if header == "" || etag == "" {
		return false
	}
	for candidate := range strings.SplitSeq(header, ",") {
		if strings.TrimPrefix(strings.TrimSpace(candidate), "W/") == etag {
			return true
		}
	}
	return false
}

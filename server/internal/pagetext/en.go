package pagetext

import "time"

// en is the fallback, and its wording is what the pages said before
// they were negotiated at all: an English reader sees no change.
var en = Strings{
	Lang:       "en",
	FormatDate: func(t time.Time) string { return t.Format("Jan 2, 2006") },

	ShareDownload:      "Download",
	ShareSharedWith:    "Shared with WaxDeck",
	ShareExpiresPrefix: "link expires",
	ShareNotFoundTitle: "Not found",
	ShareNotFoundBody:  "This link does not exist, has expired, or was revoked.",

	OidcTitle:              "WaxDeck sign-on",
	OidcCodeHeading:        "Almost there",
	OidcCodeBody:           "Enter this one-time code in the app to finish signing in. It expires in a few minutes.",
	OidcErrorHeading:       "Sign-on failed",
	OidcBackLink:           "Back to WaxDeck",
	OidcNotConfigured:      "single sign-on is not configured on this server",
	OidcProviderReported:   "the identity provider reported: %s %s",
	OidcIncompleteCallback: "the identity provider sent an incomplete callback",
	OidcCouldNotComplete:   "sign-on could not be completed",
	OidcUnknownMode:        "unknown flow mode",

	LastfmFailedTitle:    "Last.fm connection failed",
	LastfmFailedBody:     "the authorization could not be completed",
	LastfmConnectedTitle: "Last.fm connected",
	LastfmConnectedBody:  "Connected as %s. You can close this window; WaxDeck delivers your scrobbles from here on.",
}

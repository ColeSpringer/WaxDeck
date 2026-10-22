package service

import (
	"net/http"
	"net/url"
	"strings"
)

// SameOrigin reports whether two addresses share scheme, host and port, a
// default port counting as the one it stands for. It is the rule a show's
// stored credentials are sent under. An address with no host is no origin
// and matches nothing, and a respelling of a host (a trailing dot, another
// form of an IPv6 literal) counts as another host.
func SameOrigin(a, b *url.URL) bool {
	return a.Hostname() != "" &&
		strings.EqualFold(a.Scheme, b.Scheme) &&
		strings.EqualFold(a.Hostname(), b.Hostname()) &&
		originPort(a) == originPort(b)
}

func originPort(u *url.URL) string {
	if p := u.Port(); p != "" {
		return p
	}
	switch strings.ToLower(u.Scheme) {
	case "https":
		return "443"
	case "http":
		return "80"
	}
	return ""
}

// feedLogin is a show's stored credentials and the address of its feed,
// whose origin is the one place they are sent. The zero value is an open
// show's: nothing to send.
type feedLogin struct {
	feedURL    string
	user, pass string
}

// authorize gives req the pair when it is at the feed's origin and takes
// any Authorization off it when it is not.
func (f feedLogin) authorize(req *http.Request) {
	feed, err := url.Parse(f.feedURL)
	if f.user != "" && err == nil && SameOrigin(req.URL, feed) {
		req.SetBasicAuth(f.user, f.pass)
		return
	}
	req.Header.Del("Authorization")
}

// sendWithLogin sends req through client with login judged on every
// request of the chain, the first and each redirect hop that client's own
// rules let through: one at the feed's origin carries the pair, whichever
// host sent it there, and no other does. Go copies the first request's
// headers onto each hop and, once a hop goes to another domain, leaves
// Authorization off for the rest of the chain, so left to itself it would
// decide by where the chain started and where it has been. The copy of
// client shares its transport, and so its dial guard.
func sendWithLogin(client *http.Client, req *http.Request, login feedLogin) (*http.Response, error) {
	c := *client
	follow := client.CheckRedirect
	c.CheckRedirect = func(next *http.Request, via []*http.Request) error {
		if follow != nil {
			if err := follow(next, via); err != nil {
				return err
			}
		}
		login.authorize(next)
		return nil
	}
	login.authorize(req)
	return c.Do(req)
}

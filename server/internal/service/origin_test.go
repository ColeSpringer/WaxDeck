package service

import (
	"net/url"
	"testing"
)

// The origin the show's credentials may be sent to: scheme, host and port,
// a default port counting as the one it stands for, and anything in doubt
// counting as another origin.
func TestSameOrigin(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		a, b string
		want bool
	}{
		{"the same origin", "https://feeds.example/a.json", "https://feeds.example/b.xml", true},
		{"host case does not matter", "https://FEEDS.example/a.json", "https://feeds.example/b.xml", true},
		{"scheme case does not matter", "HTTPS://feeds.example/a.json", "https://feeds.example/b.xml", true},
		{"https default port spelled out", "https://feeds.example:443/a.json", "https://feeds.example/b.xml", true},
		{"http default port spelled out", "http://feeds.example:80/a.json", "http://feeds.example/b.xml", true},
		{"the other scheme's default is not the default", "https://feeds.example:80/a.json", "https://feeds.example/b.xml", false},
		{"the other scheme's default is not the default, http", "http://feeds.example:443/a.json", "http://feeds.example/b.xml", false},
		{"another port", "https://feeds.example:8443/a.json", "https://feeds.example/b.xml", false},
		{"a scheme change on the default ports", "http://feeds.example/a.json", "https://feeds.example/b.xml", false},
		{"a scheme change on equal ports", "http://feeds.example:8443/a.json", "https://feeds.example:8443/b.xml", false},
		{"a subdomain is another party", "https://cdn.feeds.example/a.json", "https://feeds.example/b.xml", false},
		{"another host", "https://cdn.other/a.json", "https://feeds.example/b.xml", false},
		{"userinfo is not part of the origin", "https://member:s3cret@feeds.example/a.json", "https://feeds.example/b.xml", true},
		{"path and query are not part of it", "https://feeds.example/a?x=1", "https://feeds.example/b/c#d", true},
		{"an IPv6 literal", "http://[::1]:8080/a.json", "http://[::1]:8080/b.xml", true},
		{"an IPv6 literal on its default port", "http://[::1]/a.json", "http://[::1]:80/b.xml", true},
		{"an IPv6 literal on another port", "http://[::1]:8080/a.json", "http://[::1]:9090/b.xml", false},
		{"an IPv6 respelling fails safe", "http://[0:0:0:0:0:0:0:1]:8080/a.json", "http://[::1]:8080/b.xml", false},
		{"a trailing dot fails safe", "https://feeds.example./a.json", "https://feeds.example/b.xml", false},
		{"a hostless address matches nothing", "/a.json", "https://feeds.example/b.xml", false},
		{"two hostless addresses match nothing", "/a.json", "/b.json", false},
	}
	parse := func(raw string) *url.URL {
		u, err := url.Parse(raw)
		if err != nil {
			t.Fatalf("parsing %q: %v", raw, err)
		}
		return u
	}
	for _, c := range cases {
		if got := SameOrigin(parse(c.a), parse(c.b)); got != c.want {
			t.Errorf("%s: SameOrigin(%q, %q) = %v, want %v", c.name, c.a, c.b, got, c.want)
		}
	}
}

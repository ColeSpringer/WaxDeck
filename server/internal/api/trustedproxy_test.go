package api

import (
	"net/http"
	"testing"
)

func mustTrust(t *testing.T, list string) trustedProxies {
	t.Helper()
	parsed, err := ParseTrustedProxies(list)
	if err != nil {
		t.Fatalf("parsing %q: %v", list, err)
	}
	return parsed
}

func requestFrom(remote string, forwarded ...string) *http.Request {
	r := &http.Request{RemoteAddr: remote, Header: http.Header{}}
	for _, line := range forwarded {
		r.Header.Add("X-Forwarded-For", line)
	}
	return r
}

// TestClientIPWalk is the whole resolution, and the row that matters
// most is the spoofed one: a request that did not arrive from a
// configured hop gets no say in what its address is, which is what keeps
// the limiter from being disabled by a header anyone can send.
func TestClientIPWalk(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name      string
		trust     string
		remote    string
		forwarded []string
		want      string
	}{
		{
			name:   "no trusted list is today's behaviour",
			remote: "203.0.113.9:41234",
			want:   "203.0.113.9",
		},
		{
			name:      "a header from an untrusted socket is ignored",
			trust:     "10.0.0.0/8",
			remote:    "203.0.113.9:41234",
			forwarded: []string{"198.51.100.7"},
			want:      "203.0.113.9",
		},
		{
			name:      "one trusted hop yields the caller",
			trust:     "10.0.0.0/8",
			remote:    "10.1.2.3:41234",
			forwarded: []string{"198.51.100.7"},
			want:      "198.51.100.7",
		},
		{
			name:      "a chain stops at the first untrusted hop",
			trust:     "10.0.0.0/8",
			remote:    "10.1.2.3:41234",
			forwarded: []string{"198.51.100.7, 10.9.9.9"},
			want:      "198.51.100.7",
		},
		{
			name:      "hops split across header lines read as one chain",
			trust:     "10.0.0.0/8",
			remote:    "10.1.2.3:41234",
			forwarded: []string{"198.51.100.7", "10.9.9.9"},
			want:      "198.51.100.7",
		},
		{
			name:      "a bracketed IPv6 hop unwraps",
			trust:     "10.0.0.0/8",
			remote:    "10.1.2.3:41234",
			forwarded: []string{"[2001:db8::1]"},
			want:      "2001:db8::1",
		},
		{
			name:      "a hop carrying a port unwraps",
			trust:     "10.0.0.0/8",
			remote:    "10.1.2.3:41234",
			forwarded: []string{"198.51.100.7:5555"},
			want:      "198.51.100.7",
		},
		{
			name:      "garbage on a hop ends the walk rather than being skipped",
			trust:     "10.0.0.0/8",
			remote:    "10.1.2.3:41234",
			forwarded: []string{"198.51.100.7, _obfuscated"},
			want:      "10.1.2.3",
		},
		{
			name:      "an obfuscated last hop keeps the socket address",
			trust:     "10.0.0.0/8",
			remote:    "10.1.2.3:41234",
			forwarded: []string{"unknown"},
			want:      "10.1.2.3",
		},
		{
			name:   "a bare trusted address is its own single-host block",
			trust:  "10.1.2.3",
			remote: "10.1.2.3:41234",
			forwarded: []string{
				"198.51.100.7",
			},
			want: "198.51.100.7",
		},
		{
			name:      "a neighbour of a bare trusted address is not trusted",
			trust:     "10.1.2.3",
			remote:    "10.1.2.4:41234",
			forwarded: []string{"198.51.100.7"},
			want:      "10.1.2.4",
		},
		{
			name:      "every hop trusted answers the leftmost",
			trust:     "10.0.0.0/8",
			remote:    "10.1.2.3:41234",
			forwarded: []string{"10.4.4.4, 10.9.9.9"},
			want:      "10.4.4.4",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := mustTrust(t, tc.trust).clientIP(requestFrom(tc.remote, tc.forwarded...))
			if got != tc.want {
				t.Errorf("clientIP = %q, want %q", got, tc.want)
			}
		})
	}
}

// TestParseTrustedProxiesRefusesGarbage is why the flag is parsed at
// boot rather than defaulted: a typo that silently trusted nothing would
// look exactly like a working configuration.
func TestParseTrustedProxiesRefusesGarbage(t *testing.T) {
	t.Parallel()
	for _, list := range []string{"not-an-address", "10.0.0.0/99", "10.0.0.1, oops"} {
		if _, err := ParseTrustedProxies(list); err == nil {
			t.Errorf("ParseTrustedProxies(%q) accepted it", list)
		}
	}
	// An empty list, and a list of nothing but separators, are both the
	// no-proxy configuration rather than an error.
	for _, list := range []string{"", "  ", ",,"} {
		parsed, err := ParseTrustedProxies(list)
		if err != nil {
			t.Errorf("ParseTrustedProxies(%q) = %v, want the empty configuration", list, err)
		}
		if !parsed.empty() {
			t.Errorf("ParseTrustedProxies(%q) trusts something", list)
		}
	}
}

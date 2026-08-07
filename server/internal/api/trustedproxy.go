package api

import (
	"net"
	"net/http"
	"strings"
)

// Trusted-proxy resolution: which address the auth limiter counts.
//
// The limiter keys on the caller's IP, and behind a reverse proxy every
// caller shares the proxy's - so five failed logins from one person lock
// out the household on a doubling ladder, and there is no way to tell
// the household apart without believing a header. Believing one
// unconditionally is worse than the problem: X-Forwarded-For is
// caller-supplied, so anyone could mint a fresh budget per request and
// the limiter would stop existing.
//
// The resolution is therefore a walk that begins only from a socket
// address the operator named as a hop. That is the property the whole
// thing rests on: an untrusted socket means the header is ignored
// entirely, so a direct visitor cannot spoof anything, and an empty
// trusted list is exactly today's behaviour.
//
// A flag, never /admin/settings. A runtime-mutable trusted-proxy list is
// a way to disable the limiter from inside the product, and the value
// belongs with the deployment rather than with the library.

// trustedProxies is a parsed CIDR list; the zero value trusts nothing
// and answers the socket address, which is what an instance with no
// proxy in front of it wants.
type trustedProxies struct {
	nets []*net.IPNet
}

// ParseTrustedProxies parses a comma-separated list of CIDRs or bare
// addresses. A bare address is taken as its own single-host block, which
// is what an operator naming one proxy means. Empty entries are skipped;
// anything unparseable is an error, because a typo that silently trusted
// nothing would look exactly like a working configuration until the day
// somebody was locked out.
func ParseTrustedProxies(list string) (trustedProxies, error) {
	var out trustedProxies
	for _, raw := range strings.Split(list, ",") {
		entry := strings.TrimSpace(raw)
		if entry == "" {
			continue
		}
		if _, block, err := net.ParseCIDR(entry); err == nil {
			out.nets = append(out.nets, block)
			continue
		}
		ip := net.ParseIP(entry)
		if ip == nil {
			return trustedProxies{}, &net.ParseError{Type: "trusted proxy CIDR or address", Text: entry}
		}
		bits := 32
		if ip.To4() == nil {
			bits = 128
		}
		out.nets = append(out.nets, &net.IPNet{
			IP:   ip,
			Mask: net.CIDRMask(bits, bits),
		})
	}
	return out, nil
}

func (t trustedProxies) empty() bool { return len(t.nets) == 0 }

func (t trustedProxies) trusts(ip net.IP) bool {
	if ip == nil {
		return false
	}
	for _, block := range t.nets {
		if block.Contains(ip) {
			return true
		}
	}
	return false
}

// clientIP resolves the address the limiter counts.
//
// The walk is right to left over X-Forwarded-For, which is append-order:
// the rightmost entry is the one the nearest proxy added and so the only
// one any of them vouched for. It stops at the first hop that is not
// trusted, and that hop is the answer.
//
// Three failure modes, all of them terminating the walk rather than
// skipping past:
//
//   - an entry that carries a port, or is a bracketed IPv6 literal, is
//     unwrapped before parsing, because both spellings are real in the
//     wild;
//   - an entry that is an obfuscated token ("_hidden"), an "unknown"
//     placeholder, or plain garbage does not parse as an IP, and the walk
//     ends at the last address it did trust rather than reaching past it
//     for something that might;
//   - a list longer than the number of hops the operator configured is
//     not special-cased, because it cannot be: the trust check already
//     bounds how far left the walk can reach.
func (t trustedProxies) clientIP(r *http.Request) string {
	socket := remoteIP(r)
	if t.empty() {
		return socket
	}
	ip := net.ParseIP(socket)
	if !t.trusts(ip) {
		// The property everything else depends on: a request that did not
		// arrive from a configured hop gets no say in what its address is.
		return socket
	}
	hops := forwardedHops(r)
	answer := socket
	for i := len(hops) - 1; i >= 0; i-- {
		hop := net.ParseIP(unwrapHop(hops[i]))
		if hop == nil {
			// Unparseable: stop here. Reaching further left would take an
			// address that this hop, not the proxy, chose to put there.
			return answer
		}
		answer = hop.String()
		if !t.trusts(hop) {
			return answer
		}
	}
	return answer
}

// forwardedHops splits every X-Forwarded-For header the request carries
// into entries, in order. Multiple header lines are as valid as one
// comma-joined line, and a proxy chain produces both.
func forwardedHops(r *http.Request) []string {
	var out []string
	for _, line := range r.Header.Values("X-Forwarded-For") {
		for _, entry := range strings.Split(line, ",") {
			if entry = strings.TrimSpace(entry); entry != "" {
				out = append(out, entry)
			}
		}
	}
	return out
}

// unwrapHop strips the two decorations a forwarded entry may carry: a
// port, and the brackets an IPv6 literal wears when it has one. A bare
// IPv6 address has colons of its own, so the port split is attempted
// only where it can be told apart.
func unwrapHop(entry string) string {
	if host, _, err := net.SplitHostPort(entry); err == nil {
		return strings.Trim(host, "[]")
	}
	return strings.Trim(entry, "[]")
}

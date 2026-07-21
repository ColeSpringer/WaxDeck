package dlna

import (
	"context"
	"net"
	"strings"
	"time"
)

const (
	ssdpMulticastAddr = "239.255.255.250:1900"
	ssdpSearchTarget  = "urn:schemas-upnp-org:device:MediaRenderer:1"
)

// ssdpWindow is how long one search listens for unicast responses. MX
// is 2 in the request, so compliant devices answer within two seconds;
// the extra second absorbs slow stacks. A package variable so tests
// shrink it.
var ssdpWindow = 3 * time.Second

// ssdpFound is one M-SEARCH response worth keeping: where the
// description lives and the device's durable identity.
type ssdpFound struct {
	Location string
	UDN      string
}

// ssdpSearch multicasts one M-SEARCH for MediaRenderer devices and
// collects responses until the window closes. Socket trouble degrades
// to an empty result with a warning: multicast is absent inside default
// Docker networking, and statically configured devices must keep
// working there.
func ssdpSearch(ctx context.Context, log Logger) []ssdpFound {
	conn, err := net.ListenPacket("udp4", ":0")
	if err != nil {
		log.Warn("dlna: ssdp socket unavailable", "err", err)
		return nil
	}
	defer conn.Close()
	dst, err := net.ResolveUDPAddr("udp4", ssdpMulticastAddr)
	if err != nil {
		log.Warn("dlna: resolving ssdp multicast address", "err", err)
		return nil
	}

	req := "M-SEARCH * HTTP/1.1\r\n" +
		"HOST: " + ssdpMulticastAddr + "\r\n" +
		`MAN: "ssdp:discover"` + "\r\n" +
		"MX: 2\r\n" +
		"ST: " + ssdpSearchTarget + "\r\n\r\n"
	// UDP drops silently; a second copy costs nothing and doubles the
	// odds a sleepy renderer hears the search.
	for range 2 {
		if _, err := conn.WriteTo([]byte(req), dst); err != nil {
			log.Warn("dlna: ssdp search send failed", "err", err)
			return nil
		}
	}

	deadline := time.Now().Add(ssdpWindow)
	if d, ok := ctx.Deadline(); ok && d.Before(deadline) {
		deadline = d
	}
	_ = conn.SetReadDeadline(deadline)

	buf := make([]byte, 8192)
	seen := make(map[string]bool)
	var out []ssdpFound
	for ctx.Err() == nil {
		n, _, err := conn.ReadFrom(buf)
		if err != nil {
			break
		}
		location, udn, ok := parseSSDPResponse(buf[:n])
		if !ok || seen[udn+location] {
			continue
		}
		seen[udn+location] = true
		out = append(out, ssdpFound{Location: location, UDN: udn})
	}
	return out
}

// parseSSDPResponse reads one HTTP-over-UDP search response: status
// line, then headers, matched case-insensitively with folded
// continuation lines unwrapped. The UDN is the uuid prefix of USN,
// which doubles the search target after a double colon.
func parseSSDPResponse(datagram []byte) (location, udn string, ok bool) {
	lines := strings.Split(strings.ReplaceAll(string(datagram), "\r\n", "\n"), "\n")
	if len(lines) == 0 {
		return "", "", false
	}
	status := strings.Fields(lines[0])
	if len(status) < 2 || !strings.HasPrefix(status[0], "HTTP/") || status[1] != "200" {
		return "", "", false
	}
	headers := make(map[string]string)
	last := ""
	for _, line := range lines[1:] {
		if line == "" {
			break
		}
		if line[0] == ' ' || line[0] == '\t' {
			if last != "" {
				headers[last] += " " + strings.TrimSpace(line)
			}
			continue
		}
		name, value, found := strings.Cut(line, ":")
		if !found {
			continue
		}
		last = strings.ToLower(strings.TrimSpace(name))
		headers[last] = strings.TrimSpace(value)
	}
	location = headers["location"]
	if location == "" {
		return "", "", false
	}
	if st, present := headers["st"]; present && !strings.Contains(st, "MediaRenderer") {
		return "", "", false
	}
	usn := headers["usn"]
	if uuid, _, found := strings.Cut(usn, "::"); found {
		udn = uuid
	} else {
		udn = usn
	}
	if !strings.HasPrefix(strings.ToLower(udn), "uuid:") {
		udn = ""
	}
	return location, udn, true
}

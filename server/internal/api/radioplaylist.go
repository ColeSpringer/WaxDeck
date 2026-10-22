package api

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// A station's address can answer a playlist that names its stream rather
// than the stream. The relay follows a PLS or M3U playlist to the first
// stream it names, one level deep, and refuses an HLS manifest, which is
// a list of segments rather than a stream it relays.

const (
	// stationPlaylistMaxBytes and stationPlaylistWait bound reading what a
	// station answers before it is known to be a stream, which the radio
	// client, deliberately without a deadline, would not.
	stationPlaylistMaxBytes = 64 << 10
	stationPlaylistWait     = 10 * time.Second
	// stationSniffBytes is how much of an answer that does not say what it
	// is gets read to tell a playlist from a stream.
	stationSniffBytes = 512
)

// stationRefusal is why a station's answer is not relayed, in the words
// the relay's refusal carries.
type stationRefusal string

func (r stationRefusal) Error() string { return string(r) }

const (
	refusedHLS      stationRefusal = "the station's address is an HLS manifest, a list of segments rather than a stream this server relays"
	refusedSlow     stationRefusal = "the station did not answer with a stream in time"
	refusedLarge    stationRefusal = "the station's playlist is larger than this server reads"
	refusedNoStream stationRefusal = "the station's playlist names no stream this server can play"
	refusedNested   stationRefusal = "the station's playlist names another playlist"
)

// stationPlaylistTypes are the labels PLS and M3U playlists, and HLS
// manifests, are served under; stationSniffedTypes are those an answer
// says nothing by, whose first bytes decide.
var (
	stationPlaylistTypes = map[string]bool{
		"audio/x-mpegurl": true, "audio/mpegurl": true, "application/x-mpegurl": true,
		"application/mpegurl": true, "application/vnd.apple.mpegurl": true, "audio/vnd.apple.mpegurl": true,
		"audio/x-m3u": true, "audio/m3u": true, "audio/x-scpls": true, "audio/scpls": true,
		"application/pls+xml": true, "application/pls": true,
	}
	stationSniffedTypes = map[string]bool{
		"": true, "application/octet-stream": true, "binary/octet-stream": true, "text/plain": true,
	}
)

// stationRequest asks for a station's stream at target.
func stationRequest(ctx context.Context, target, agent string) (*http.Request, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", agent)
	req.Header.Set("Icy-MetaData", "1")
	return req, nil
}

// stationStream is the answer the relay serves for a station that
// answered resp: resp itself, or, for a PLS or M3U playlist, the answer of
// the first stream it names, asked for through client so the dial guard
// judges that address too. Reading a playlist, or the first bytes of an
// answer that says nothing of what it is, is held to wait, past which
// stop ends the station's requests.
func stationStream(ctx context.Context, client *http.Client, agent string, resp *http.Response, stop func(), wait time.Duration) (*http.Response, error) {
	list, err := readStationPlaylist(resp, stop, wait)
	if err != nil {
		return nil, err
	}
	if list == nil {
		return resp, nil
	}
	target, err := list.stream()
	if err != nil {
		return nil, err
	}
	req, err := stationRequest(ctx, target, agent)
	if err != nil {
		return nil, err
	}
	next, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	if next.StatusCode < 200 || next.StatusCode > 299 {
		next.Body.Close()
		return nil, stationRefusal(fmt.Sprintf("the station's stream answered status %d", next.StatusCode))
	}
	nested, err := readStationPlaylist(next, stop, wait)
	if err != nil || nested != nil {
		next.Body.Close()
		switch {
		case err != nil:
		case nested.hls():
			err = refusedHLS
		default:
			err = refusedNested
		}
		return nil, err
	}
	return next, nil
}

// stationPlaylist is a playlist a station answered, and the address it
// was read from.
type stationPlaylist struct {
	text string
	base *url.URL
}

// readStationPlaylist reads resp as a playlist when it is one, by its type
// or, for an answer that says nothing of what it is, by its first bytes.
// A stream comes back nil, its body whole.
func readStationPlaylist(resp *http.Response, stop func(), wait time.Duration) (*stationPlaylist, error) {
	base, _, _ := strings.Cut(strings.ToLower(resp.Header.Get("Content-Type")), ";")
	base = strings.TrimSpace(base)
	listed := stationPlaylistTypes[base]
	if !listed && !stationSniffedTypes[base] {
		return nil, nil
	}
	timer := time.AfterFunc(wait, stop)
	list, err := readPlaylistBody(resp, listed)
	if !timer.Stop() {
		return nil, refusedSlow
	}
	return list, err
}

func readPlaylistBody(resp *http.Response, listed bool) (*stationPlaylist, error) {
	if !listed {
		peek := bufio.NewReaderSize(resp.Body, stationSniffBytes)
		head, err := peek.Peek(stationSniffBytes)
		resp.Body = struct {
			io.Reader
			io.Closer
		}{peek, resp.Body}
		if err != nil && !errors.Is(err, io.EOF) {
			return nil, err
		}
		if !looksLikePlaylist(head) {
			return nil, nil
		}
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, stationPlaylistMaxBytes+1))
	if err != nil {
		return nil, err
	}
	if len(body) > stationPlaylistMaxBytes {
		return nil, refusedLarge
	}
	return &stationPlaylist{text: string(body), base: resp.Request.URL}, nil
}

// looksLikePlaylist reports whether an answer's first bytes are a PLS or
// M3U playlist's: its header, or an address on its first line.
func looksLikePlaylist(head []byte) bool {
	first := strings.TrimSpace(strings.TrimPrefix(string(head), "\ufeff"))
	upper := strings.ToUpper(first[:min(len(first), 10)])
	return strings.HasPrefix(upper, "[PLAYLIST]") || strings.HasPrefix(upper, "#EXTM3U") ||
		strings.HasPrefix(upper, "HTTP://") || strings.HasPrefix(upper, "HTTPS://")
}

// lines are the playlist's lines, trimmed, its byte-order mark and
// carriage returns dropped.
func (p *stationPlaylist) lines() []string {
	lines := strings.Split(strings.ReplaceAll(strings.TrimPrefix(p.text, "\ufeff"), "\r", ""), "\n")
	for i, line := range lines {
		lines[i] = strings.TrimSpace(line)
	}
	return lines
}

// hls reports whether the playlist is an HLS manifest, which carries
// `#EXT-X-` tags.
func (p *stationPlaylist) hls() bool {
	for _, line := range p.lines() {
		if strings.HasPrefix(strings.ToUpper(line), "#EXT-X-") {
			return true
		}
	}
	return false
}

// stream is the first address the playlist names that the relay can ask
// for: an http or https one, a relative one taken against the address the
// playlist was read from. An HLS manifest has none.
func (p *stationPlaylist) stream() (string, error) {
	if p.hls() {
		return "", refusedHLS
	}
	lines := p.lines()
	pls := false
	for _, line := range lines {
		if strings.EqualFold(line, "[playlist]") {
			pls = true
			break
		}
	}
	for _, line := range lines {
		entry := line
		if pls {
			key, value, ok := strings.Cut(line, "=")
			if !ok || !plsFileKey(key) {
				continue
			}
			entry = strings.TrimSpace(value)
		} else if strings.HasPrefix(line, "#") {
			continue
		}
		// A real entry is an address, which never holds a space, a quote
		// or an angle bracket raw; a line that does is not one.
		if entry == "" || strings.ContainsAny(entry, " \t\"<>") {
			continue
		}
		u, err := p.base.Parse(entry)
		if err == nil && (u.Scheme == "http" || u.Scheme == "https") && u.Host != "" {
			return u.String(), nil
		}
	}
	return "", refusedNoStream
}

// plsFileKey reports whether a PLS key names an entry's address: File
// and its number.
func plsFileKey(key string) bool {
	n, ok := strings.CutPrefix(strings.ToLower(strings.TrimSpace(key)), "file")
	if !ok || n == "" {
		return false
	}
	return strings.Trim(n, "0123456789") == ""
}

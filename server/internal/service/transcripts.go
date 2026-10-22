package service

import (
	"cmp"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/netip"
	"net/url"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"
	"github.com/colespringer/waxbin/waxerr"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Episode transcripts for display and tap-line-to-seek. The catalog
// stores transcripts reduced for search indexing; the time-coded cues
// clients render are fetched from the feed's transcript pointer on
// first request and cached here.

// TranscriptCue is one time-coded cue.
type TranscriptCue struct {
	StartMS int64
	EndMS   int64
	Text    string
	Speaker string
}

// Transcript is one parsed episode transcript.
type Transcript struct {
	Format string
	Cues   []TranscriptCue
}

const (
	// transcriptMaxBytes caps a fetched document; transcripts are text.
	transcriptMaxBytes = 8 << 20
	// transcriptMaxCues caps one transcript's cues; a three-hour show with
	// a cue per word runs to about 30,000.
	transcriptMaxCues = 50_000
	// transcriptRowMaxBytes caps the cached row a transcript's cues encode
	// to, and so what one cached read decodes.
	transcriptRowMaxBytes = 4 << 20
	// transcriptCacheMaxBytes bounds the whole cache: past it the rows read
	// longest ago go.
	transcriptCacheMaxBytes = 64 << 20
	// transcriptReadGrain is how stale a row's last read may be before a
	// read records itself, so a busy transcript is not a write per read.
	transcriptReadGrain = time.Hour
	// transcriptFailTTL rate-bounds refetches of a failing pointer; the
	// caller still answers upstream-failure while a fresh negative row
	// exists, so clients retry later without hammering the host.
	transcriptFailTTL = 5 * time.Minute
)

// Transcript answers one episode's transcript, fetching and caching on
// first request. 404 semantics (no transcript announced) stay with the
// caller: an episode without a pointer never reaches the fetch.
func (l *Library) Transcript(ctx context.Context, uc *UserCtx, apiEpisodePID string) (Transcript, error) {
	det, err := l.getEpisode(ctx, apiEpisodePID)
	if err != nil {
		return Transcript{}, err
	}
	if !l.podcastsVisible(ctx, uc) {
		return Transcript{}, errNotFound("no episode with pid " + apiEpisodePID)
	}
	ep := det.Episode
	rawURL := strings.TrimSpace(ep.TranscriptURL)
	if rawURL == "" {
		return Transcript{}, errNotFound("the episode announces no transcript")
	}
	// A credentialed show's documents are read on the terms its audio is:
	// for a subscriber and no one else, what was kept included, and with the
	// credentials sent to the feed's own origin only.
	pod, err := l.readShow(ctx, ep.PodcastPID)
	if err != nil {
		return Transcript{}, classify(err)
	}
	user, pass, err := l.feedCredentials(ctx, uc.ID, pod)
	if KindOf(err) == KindForbidden {
		return Transcript{}, &Error{Kind: KindForbidden,
			Msg: "this show's feed is private to its subscribers; subscribe to read its transcript"}
	} else if err != nil {
		return Transcript{}, err
	}
	login := feedLogin{feedURL: pod.FeedURL, user: user, pass: pass}

	if row, err := l.db.TranscriptCacheFor(ctx, string(ep.PID)); err == nil {
		if !row.Negative {
			cues, decodeErr := decodeTranscriptCues(row.Cues)
			if decodeErr == nil {
				if time.Since(time.Unix(0, row.ReadAtNS)) >= transcriptReadGrain {
					if err := l.db.TouchTranscriptCache(ctx, row.EpisodePID, time.Now().UnixNano()); err != nil {
						l.log.Warn("recording a transcript read", "episode", apiEpisodePID, "err", err)
					}
				}
				return Transcript{Format: row.Format, Cues: cues}, nil
			}
			l.log.Warn("decoding cached transcript", "episode", apiEpisodePID, "err", decodeErr)
		} else if time.Since(time.Unix(0, row.FetchedAtNS)) < transcriptFailTTL {
			return Transcript{}, transcriptUnreachable(row.FailReason, nil)
		}
	} else if !errors.Is(err, wdb.ErrNotFound) {
		return Transcript{}, &Error{Kind: KindInternal, Err: err}
	}

	tx, err := l.fetchTranscript(ctx, rawURL, ep.TranscriptType, login)
	var encoded string
	if err == nil {
		encoded, err = encodeTranscriptCues(tx.Cues)
	}
	if err != nil {
		fault := hostFailure(ctx, "service.fetchTranscript", err)
		if !feedAtFault(ctx, fault) {
			return Transcript{}, classify(fault)
		}
		reason := feedReason(fault)
		l.logFeedFailure("fetching a transcript failed", ep.TranscriptURL, reason, fault)
		l.cacheTranscript(ctx, apiEpisodePID, wdb.TranscriptRow{
			EpisodePID: string(ep.PID), Negative: true, FailReason: reason, FetchedAtNS: time.Now().UnixNano(),
		})
		return Transcript{}, transcriptUnreachable(reason, fault)
	}
	l.cacheTranscript(ctx, apiEpisodePID, wdb.TranscriptRow{
		EpisodePID: string(ep.PID), Format: tx.Format, Cues: encoded,
		FetchedAtNS: time.Now().UnixNano(),
	})
	return tx, nil
}

// cacheTranscript stores one row, holding the cache to its bound.
func (l *Library) cacheTranscript(ctx context.Context, apiEpisodePID string, row wdb.TranscriptRow) {
	bound := cmp.Or(l.transcriptCacheBytes, transcriptCacheMaxBytes)
	if _, err := l.db.StoreTranscriptCache(ctx, row, bound); err != nil {
		l.log.Warn("caching transcript", "episode", apiEpisodePID, "err", err)
	}
}

// CaptureEpisodeTranscript indexes a streamed episode's transcript for
// search. A downloaded episode already indexes its transcript on fetch, and
// an already-indexed one is a no-op; otherwise the transcript is read as the
// display read reads it (the show's login at its feed's origin, for a
// private show's subscribers only, its cap, its kept answer) and its text
// handed to the catalog's index. The two keep separate stores: this
// promotes reduced search text, never the cue JSON the display cache holds.
func (l *Library) CaptureEpisodeTranscript(ctx context.Context, uc *UserCtx, apiEpisodePID string) error {
	det, err := l.getEpisode(ctx, apiEpisodePID)
	if err != nil {
		return err
	}
	if !l.podcastsVisible(ctx, uc) {
		return errNotFound("no episode with pid " + apiEpisodePID)
	}
	ep := det.Episode
	// Already indexed (downloaded, or a prior capture): nothing to fetch.
	// Two callers racing on the same episode both see not-found here and both
	// read; that is a rare redundant read of a small text document, not a
	// hazard: the store upserts the transcript idempotently (the display cue
	// path is unlocked the same way), so no lock guards this window.
	if _, err := l.lib.Podcasts().Transcript(ctx, ep.PID); err == nil {
		return nil
	} else if KindOf(err) != KindNotFound {
		return classify(err)
	}
	tx, err := l.Transcript(ctx, uc, apiEpisodePID)
	if err != nil {
		return err
	}
	lines := make([]string, 0, len(tx.Cues))
	for _, c := range tx.Cues {
		if c.Speaker != "" {
			lines = append(lines, c.Speaker+": "+c.Text)
		} else {
			lines = append(lines, c.Text)
		}
	}
	body := strings.Join(lines, "\n")
	if strings.TrimSpace(body) == "" {
		// The feed side's, so the client tries again rather than recording
		// a false absence.
		return transcriptUnreachable(reasonNotAFeed, nil)
	}
	return classify(l.lib.Podcasts().PutTranscript(ctx, model.PutTranscriptInput{
		EpisodePID: ep.PID, Format: tx.Format, Body: body, SourceURL: ep.TranscriptURL,
	}))
}

// fetchTranscript pulls and parses one transcript document through the
// guarded client, the show's login on each request at its feed's origin.
func (l *Library) fetchTranscript(ctx context.Context, rawURL, declaredType string, login feedLogin) (Transcript, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return Transcript{}, fmt.Errorf("bad transcript url: %w", err)
	}
	req.Header.Set("User-Agent", l.UserAgent())
	fetchCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	resp, err := sendWithLogin(l.transcriptClient(), req.WithContext(fetchCtx), login)
	if err != nil {
		return Transcript{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return Transcript{}, &hostStatusError{status: resp.StatusCode}
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, transcriptMaxBytes+1))
	if err != nil {
		return Transcript{}, err
	}
	if len(body) > transcriptMaxBytes {
		return Transcript{}, errTranscriptTooLarge
	}
	return parseTranscript(body, declaredType, resp.Header.Get("Content-Type"), rawURL)
}

// The transcript fetch's own failures, typed so feedReason can tell them
// apart without reading their words.
var (
	errTranscriptTooLarge = errors.New("transcript document exceeds the size cap")
	errPrivateAddress     = errors.New("host resolves to a private address")
)

// hostStatusError is a transcript host answering other than 200.
type hostStatusError struct{ status int }

func (e *hostStatusError) Error() string {
	return fmt.Sprintf("transcript host answered status %d", e.status)
}

// transcriptUnreachable is a transcript fetch's failure in the words its
// reason carries. It is always the feed side's: the request named an
// episode, and the feed named the address.
func transcriptUnreachable(reason string, err error) error {
	return &Error{Kind: KindUpstream, Msg: transcriptSentences[reason], Err: &feedFault{reason: reason, err: err}}
}

// hostFailure marks a failure to read a feed-side host as the feed's, the
// way the catalog marks its providers', or canceled once the caller is.
func hostFailure(ctx context.Context, op string, err error) error {
	if ctx.Err() != nil {
		return waxerr.FromContext(op, err, waxerr.CodeCanceled)
	}
	return &source.ProviderError{SourceType: model.SourceRSS, Op: "fetch", Err: waxerr.Wrap(waxerr.CodeIO, op, err)}
}

// transcriptClient builds the guarded HTTP client once: redirects
// capped, private addresses refused unless the server allows LAN feed
// hosts.
func (l *Library) transcriptClient() *http.Client {
	l.transcriptHTTPOnce.Do(func() {
		l.transcriptHTTP = &http.Client{
			Transport: guardedTransport(l.allowPrivateFeedHosts),
			Timeout:   25 * time.Second,
			CheckRedirect: func(req *http.Request, via []*http.Request) error {
				if len(via) >= 5 {
					return errors.New("too many redirects")
				}
				return nil
			},
		}
	})
	return l.transcriptHTTP
}

// guardedTransport is the transport of every client that fetches an
// address a feed, a station or a user named. Unless allowPrivate, each
// connection attempt to a private destination is refused after DNS
// resolution, which defeats rebinding; and the destination is dialed
// directly, never through an environment's proxy, whose address is all
// the guard would see.
func guardedTransport(allowPrivate bool) *http.Transport {
	dialer := &net.Dialer{Timeout: 10 * time.Second}
	if !allowPrivate {
		dialer.Control = func(_, address string, _ syscall.RawConn) error {
			return refusePrivateAddr(address)
		}
	}
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.Proxy = nil
	transport.DialContext = dialer.DialContext
	return transport
}

// refusePrivateAddr refuses a resolved dial address privateIP holds off
// limits.
func refusePrivateAddr(address string) error {
	host, _, err := net.SplitHostPort(address)
	if err != nil {
		return err
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return fmt.Errorf("unresolved address %q", host)
	}
	if privateIP(ip) {
		return errPrivateAddress
	}
	return nil
}

var (
	// nat64Prefix is NAT64's well-known prefix (RFC 6052): an address under
	// it reaches the IPv4 address in its last four bytes.
	nat64Prefix = netip.MustParsePrefix("64:ff9b::/96")
	// specialPrefixes are what the catalog's guard refuses beyond what
	// netip classifies: carrier-grade NAT (RFC 6598, where Tailscale peers
	// and Alibaba's metadata service live) and the IETF protocol block.
	specialPrefixes = []netip.Prefix{netip.MustParsePrefix("100.64.0.0/10"), netip.MustParsePrefix("192.0.0.0/24")}
)

// privateIP reports whether ip is off limits to a guarded fetch: the
// ranges the catalog's own feed client refuses (loopback, private and
// unique-local, link-local, unspecified, interface-local multicast,
// carrier-grade NAT, the IETF protocol block), named directly,
// IPv4-mapped or behind NAT64.
func privateIP(ip net.IP) bool {
	addr, ok := netip.AddrFromSlice(ip)
	if !ok {
		return false
	}
	addr = addr.Unmap()
	if nat64Prefix.Contains(addr) {
		b := addr.As16()
		addr = netip.AddrFrom4([4]byte(b[12:]))
	}
	if addr.IsLoopback() || addr.IsPrivate() || addr.IsLinkLocalUnicast() || addr.IsLinkLocalMulticast() ||
		addr.IsUnspecified() || addr.IsInterfaceLocalMulticast() {
		return true
	}
	for _, p := range specialPrefixes {
		if p.Contains(addr) {
			return true
		}
	}
	return false
}

// refusedNAT64Host reports whether rawURL's host is a NAT64 literal of an
// address privateIP refuses, which the catalog's own guard dials.
func refusedNAT64Host(rawURL string) bool {
	u, err := url.Parse(rawURL)
	if err != nil {
		return false
	}
	addr, err := netip.ParseAddr(u.Hostname())
	return err == nil && nat64Prefix.Contains(addr) && privateIP(addr.AsSlice())
}

// blockedFeedAddress is a subscribe's refusal of a feed on a private
// address, in the words the catalog's own refusal has.
func blockedFeedAddress() error {
	return &Error{Kind: KindInvalid, Msg: feedSentences[reasonBlockedAddress],
		Err: &feedFault{reason: reasonBlockedAddress, err: errPrivateAddress}}
}

// parseTranscript classifies and parses the document. Classification
// prefers the feed's declared type, then the response media type, then
// the URL extension, then sniffing.
func parseTranscript(body []byte, declaredType, contentType, rawURL string) (Transcript, error) {
	kind := classifyTranscript(declaredType, contentType, rawURL, body)
	switch kind {
	case "json":
		cues, err := parseJSONTranscript(body)
		if err != nil {
			return Transcript{}, err
		}
		return Transcript{Format: "json", Cues: cues}, nil
	case "srt", "vtt":
		cues, err := parseCueBlocks(string(body), kind == "vtt")
		if err != nil {
			return Transcript{}, err
		}
		return Transcript{Format: kind, Cues: cues}, nil
	default:
		text := strings.TrimSpace(string(body))
		if text == "" {
			return Transcript{Format: "text"}, nil
		}
		return Transcript{Format: "text", Cues: []TranscriptCue{{Text: text}}}, nil
	}
}

func classifyTranscript(declaredType, contentType, rawURL string, body []byte) string {
	for _, hint := range []string{strings.ToLower(declaredType), strings.ToLower(contentType), strings.ToLower(rawURL)} {
		switch {
		case strings.Contains(hint, "json"):
			return "json"
		case strings.Contains(hint, "srt") || strings.Contains(hint, "subrip"):
			return "srt"
		case strings.Contains(hint, "vtt"):
			return "vtt"
		}
	}
	head := strings.TrimSpace(string(body[:min(len(body), 64)]))
	switch {
	case strings.HasPrefix(head, "WEBVTT"):
		return "vtt"
	case strings.HasPrefix(head, "{") || strings.HasPrefix(head, "["):
		return "json"
	case strings.Contains(head, "-->"):
		return "srt"
	}
	return "text"
}

// parseJSONTranscript reads the podcast-namespace JSON transcript
// shape: a segments array with startTime and endTime seconds.
func parseJSONTranscript(body []byte) ([]TranscriptCue, error) {
	var doc struct {
		Segments []struct {
			StartTime float64 `json:"startTime"`
			EndTime   float64 `json:"endTime"`
			Speaker   string  `json:"speaker"`
			Body      string  `json:"body"`
		} `json:"segments"`
	}
	if err := json.Unmarshal(body, &doc); err != nil {
		return nil, fmt.Errorf("parsing json transcript: %w", err)
	}
	var cues []TranscriptCue
	for _, s := range doc.Segments {
		text := strings.TrimSpace(s.Body)
		if text == "" {
			continue
		}
		if len(cues) == transcriptMaxCues {
			return nil, errTranscriptTooLarge
		}
		cues = append(cues, TranscriptCue{
			StartMS: int64(s.StartTime * 1000),
			EndMS:   int64(s.EndTime * 1000),
			Text:    text,
			Speaker: strings.TrimSpace(s.Speaker),
		})
	}
	return cues, nil
}

// parseCueBlocks reads SRT and VTT: blank-line-separated blocks whose
// timing line carries "start --> end". VTT headers, NOTE blocks, and
// SRT sequence numbers are skipped; simple "speaker: text" prefixes
// populate the speaker field. Past transcriptMaxCues it stops and refuses
// the document.
func parseCueBlocks(body string, vtt bool) ([]TranscriptCue, error) {
	body = strings.ReplaceAll(body, "\r\n", "\n")
	var cues []TranscriptCue
	for block := range strings.SplitSeq(body, "\n\n") {
		lines := strings.Split(strings.TrimSpace(block), "\n")
		var start, end int64 = -1, -1
		var textLines []string
		for _, line := range lines {
			line = strings.TrimSpace(line)
			if line == "" || (vtt && (strings.HasPrefix(line, "WEBVTT") || strings.HasPrefix(line, "NOTE"))) {
				continue
			}
			if from, to, ok := parseCueTiming(line); ok {
				start, end = from, to
				continue
			}
			if start < 0 {
				// Before the timing line only cue ids and headers appear.
				continue
			}
			textLines = append(textLines, line)
		}
		if start < 0 || len(textLines) == 0 {
			continue
		}
		text := strings.Join(textLines, " ")
		speaker := ""
		if vtt {
			// VTT voice tags: <v Name>text</v>
			if strings.HasPrefix(text, "<v ") {
				if i := strings.IndexByte(text, '>'); i > 3 {
					speaker = strings.TrimSpace(text[3:i])
					text = strings.TrimSuffix(strings.TrimSpace(text[i+1:]), "</v>")
				}
			}
		}
		if speaker == "" {
			if name, rest, ok := strings.Cut(text, ": "); ok && len(name) <= 40 && !strings.ContainsAny(name, ".!?") {
				speaker, text = name, rest
			}
		}
		// Cue text is plain text on the API: SRT and VTT inline styling
		// (b, i, u, class spans, inline timestamps) would otherwise
		// render as raw markup in every client.
		text = stripCueMarkup(text)
		speaker = stripCueMarkup(speaker)
		if text == "" {
			continue
		}
		if len(cues) == transcriptMaxCues {
			return nil, errTranscriptTooLarge
		}
		cues = append(cues, TranscriptCue{StartMS: start, EndMS: end, Text: text, Speaker: speaker})
	}
	return cues, nil
}

// stripCueMarkup drops angle-bracket tags and decodes the basic
// character references subtitle text carries.
func stripCueMarkup(s string) string {
	if !strings.ContainsAny(s, "<&") {
		return s
	}
	var b strings.Builder
	b.Grow(len(s))
	inTag := false
	for _, r := range s {
		switch {
		case inTag:
			if r == '>' {
				inTag = false
			}
		case r == '<':
			inTag = true
		default:
			b.WriteRune(r)
		}
	}
	out := strings.NewReplacer(
		"&amp;", "&", "&lt;", "<", "&gt;", ">",
		"&quot;", `"`, "&#39;", "'", "&nbsp;", " ",
	).Replace(b.String())
	return strings.TrimSpace(out)
}

// parseCueTiming reads "HH:MM:SS,mmm --> HH:MM:SS,mmm" (SRT) and
// "[HH:]MM:SS.mmm --> [HH:]MM:SS.mmm" (VTT).
func parseCueTiming(line string) (startMS, endMS int64, ok bool) {
	from, to, found := strings.Cut(line, "-->")
	if !found {
		return 0, 0, false
	}
	// VTT cue settings may trail the end time.
	toFields := strings.Fields(strings.TrimSpace(to))
	if len(toFields) == 0 {
		return 0, 0, false
	}
	start, ok1 := parseCueTime(strings.TrimSpace(from))
	end, ok2 := parseCueTime(toFields[0])
	if !ok1 || !ok2 {
		return 0, 0, false
	}
	return start, end, true
}

func parseCueTime(s string) (int64, bool) {
	s = strings.ReplaceAll(s, ",", ".")
	parts := strings.Split(s, ":")
	if len(parts) < 2 || len(parts) > 3 {
		return 0, false
	}
	var h, m int64
	var sec float64
	var err error
	idx := 0
	if len(parts) == 3 {
		h, err = strconv.ParseInt(parts[0], 10, 64)
		if err != nil {
			return 0, false
		}
		idx = 1
	}
	m, err = strconv.ParseInt(parts[idx], 10, 64)
	if err != nil {
		return 0, false
	}
	sec, err = strconv.ParseFloat(parts[idx+1], 64)
	if err != nil {
		return 0, false
	}
	return h*3600000 + m*60000 + int64(sec*1000), true
}

// encodeTranscriptCues is the cached row's text for cues, refused as too
// large past transcriptRowMaxBytes.
func encodeTranscriptCues(cues []TranscriptCue) (string, error) {
	b, err := json.Marshal(cues)
	if err != nil {
		return "", err
	}
	if len(b) > transcriptRowMaxBytes {
		return "", errTranscriptTooLarge
	}
	return string(b), nil
}

// decodeTranscriptCues reads a cached row, never one past
// transcriptRowMaxBytes.
func decodeTranscriptCues(encoded string) ([]TranscriptCue, error) {
	if encoded == "" {
		return nil, nil
	}
	if len(encoded) > transcriptRowMaxBytes {
		return nil, errTranscriptTooLarge
	}
	var cues []TranscriptCue
	err := json.Unmarshal([]byte(encoded), &cues)
	return cues, err
}

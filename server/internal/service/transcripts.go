package service

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strconv"
	"strings"
	"syscall"
	"time"

	"github.com/colespringer/waxbin/model"

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
	if strings.TrimSpace(ep.TranscriptURL) == "" {
		return Transcript{}, errNotFound("the episode announces no transcript")
	}

	if row, err := l.db.TranscriptCacheFor(ctx, string(ep.PID)); err == nil {
		if !row.Negative {
			cues, decodeErr := decodeTranscriptCues(row.Cues)
			if decodeErr == nil {
				return Transcript{Format: row.Format, Cues: cues}, nil
			}
			l.log.Warn("decoding cached transcript", "episode", apiEpisodePID, "err", decodeErr)
		} else if time.Since(time.Unix(0, row.FetchedAtNS)) < transcriptFailTTL {
			return Transcript{}, &Error{Kind: KindUpstream,
				Msg: "the transcript could not be fetched; retry later"}
		}
	} else if !errors.Is(err, wdb.ErrNotFound) {
		return Transcript{}, &Error{Kind: KindInternal, Err: err}
	}

	tx, err := l.fetchTranscript(ctx, ep.PodcastPID, ep.TranscriptURL, ep.TranscriptType)
	if err != nil {
		if putErr := l.db.PutTranscriptCache(ctx, wdb.TranscriptRow{
			EpisodePID: string(ep.PID), Negative: true, FetchedAtNS: time.Now().UnixNano(),
		}); putErr != nil {
			l.log.Warn("caching transcript failure", "episode", apiEpisodePID, "err", putErr)
		}
		pod, podErr := l.lib.Podcasts().Get(ctx, ep.PodcastPID)
		private := podErr != nil || l.showIsPrivate(ctx, pod)
		return Transcript{}, l.classifyFeedErr(ctx, err, ep.TranscriptURL, private)
	}

	encoded, err := encodeTranscriptCues(tx.Cues)
	if err != nil {
		return Transcript{}, &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.PutTranscriptCache(ctx, wdb.TranscriptRow{
		EpisodePID: string(ep.PID), Format: tx.Format, Cues: encoded,
		FetchedAtNS: time.Now().UnixNano(),
	}); err != nil {
		l.log.Warn("caching transcript", "episode", apiEpisodePID, "err", err)
	}
	return tx, nil
}

// CaptureEpisodeTranscript indexes a streamed episode's transcript for
// search. A downloaded episode already indexes its transcript on fetch, and
// an already-indexed one is a no-op; otherwise the announced transcript is
// pulled through the engine (no audio download) and its text indexed. This
// is the search-side companion to the display cue transcript above: the two
// keep separate stores, and this promotes reduced search text, never the
// cue JSON the display cache holds.
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
	// fetch; that is a rare redundant fetch of a small text document, not a
	// hazard: the store upserts the transcript idempotently (the display cue
	// path is unlocked the same way), so no lock guards this window.
	if _, err := l.lib.Podcasts().Transcript(ctx, ep.PID); err == nil {
		return nil
	} else if KindOf(err) != KindNotFound {
		return classify(err)
	}
	if strings.TrimSpace(ep.TranscriptURL) == "" {
		return errNotFound("the episode announces no transcript")
	}
	if err := l.lib.Podcasts().FetchTranscript(ctx, ep.PID); err != nil {
		// The pointer exists but could not be fetched, parsed, or reduced to
		// searchable text; surface it as a retriable upstream failure so the
		// client tries again rather than recording a false absence.
		l.log.Debug("capturing episode transcript", "episode", apiEpisodePID, "err", err)
		return &Error{Kind: KindUpstream, Msg: "the transcript could not be captured; retry later"}
	}
	return nil
}

// fetchTranscript pulls and parses one transcript document, applying
// the show's stored credentials (the pointer lives in the same trust
// domain as the feed) and the private-address guard.
func (l *Library) fetchTranscript(ctx context.Context, showPID model.PID, rawURL, declaredType string) (Transcript, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, rawURL, nil)
	if err != nil {
		return Transcript{}, fmt.Errorf("bad transcript url: %w", err)
	}
	pod, err := l.lib.Podcasts().Get(ctx, showPID)
	if err == nil && pod.AuthUser != "" {
		if pass, err := l.lib.GetSecret(ctx, "podcast.auth."+string(pod.PID)); err == nil {
			req.SetBasicAuth(pod.AuthUser, pass)
		}
	}
	fetchCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
	defer cancel()
	resp, err := l.transcriptClient().Do(req.WithContext(fetchCtx))
	if err != nil {
		return Transcript{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return Transcript{}, fmt.Errorf("transcript host answered status %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, transcriptMaxBytes+1))
	if err != nil {
		return Transcript{}, err
	}
	if len(body) > transcriptMaxBytes {
		return Transcript{}, errors.New("transcript document exceeds the size cap")
	}
	return parseTranscript(body, declaredType, resp.Header.Get("Content-Type"), rawURL)
}

// transcriptClient builds the guarded HTTP client once: redirects
// capped, private addresses refused per connection attempt after DNS
// resolution (which defeats rebinding), unless the server allows LAN
// feed hosts.
func (l *Library) transcriptClient() *http.Client {
	l.transcriptHTTPOnce.Do(func() {
		dialer := &net.Dialer{Timeout: 10 * time.Second}
		if !l.allowPrivateFeedHosts {
			dialer.Control = func(network, address string, _ syscall.RawConn) error {
				return refusePrivateAddr(address)
			}
		}
		transport := http.DefaultTransport.(*http.Transport).Clone()
		transport.DialContext = dialer.DialContext
		l.transcriptHTTP = &http.Client{
			Transport: transport,
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

// refusePrivateAddr rejects loopback, private, link-local, and
// unspecified destinations after resolution (defeats DNS rebinding).
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
		return fmt.Errorf("host resolves to a private address")
	}
	return nil
}

// privateIP reports whether ip is off limits for guarded outbound
// fetches: loopback, private, link-local, or unspecified.
func privateIP(ip net.IP) bool {
	return ip.IsLoopback() || ip.IsPrivate() || ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() || ip.IsUnspecified()
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
	case "srt":
		return Transcript{Format: "srt", Cues: parseCueBlocks(string(body), false)}, nil
	case "vtt":
		return Transcript{Format: "vtt", Cues: parseCueBlocks(string(body), true)}, nil
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
// populate the speaker field.
func parseCueBlocks(body string, vtt bool) []TranscriptCue {
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
		cues = append(cues, TranscriptCue{StartMS: start, EndMS: end, Text: text, Speaker: speaker})
	}
	return cues
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

func encodeTranscriptCues(cues []TranscriptCue) (string, error) {
	b, err := json.Marshal(cues)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func decodeTranscriptCues(encoded string) ([]TranscriptCue, error) {
	if encoded == "" {
		return nil, nil
	}
	var cues []TranscriptCue
	err := json.Unmarshal([]byte(encoded), &cues)
	return cues, err
}

package flow

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"slices"
	"strconv"
	"strings"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/mp3join"
)

// Part is one backing file of a multi-file book, as a joined stream reads
// it.
type Part struct {
	FilePID string
	Src     Source
	// Rate and Channels are the file's own, zero where the catalog has
	// none.
	Rate     int
	Channels int
}

// PartsResolver lays out a multi-file book for a joined stream. The
// bridge's SourceResolver implements it where books stream as one.
type PartsResolver interface {
	// StreamParts answers the book's parts in reading order, nil for an
	// item that is not a book in parts.
	StreamParts(ctx context.Context, apiItemPID string) ([]Part, error)
}

// JoinedPlayInfo mints a multi-file book as one stream, for a client that
// plays the book as one item: the part opts.FilePID names (the first when
// empty) cut at opts.StartMS, to the millisecond, then every part after it
// whole, as MP3, the one output whose parts join end to end. The caller
// aligns the start on the book's timeline: each distinct cut is an encode
// of the rest of its part, and whole book seconds are what repeats near
// one spot share. The rate is the book's own, held to 32..320 kbps and
// lowered by opts.MaxBitrateKbps and the account's ceiling. The token
// binds the start part and the rate as it binds any stream's shape; the
// cut rides outside it, as every cut does.
func (b *Bridge) JoinedPlayInfo(ctx context.Context, user, apiItemPID string, opts PlayOptions) (PlayInfo, error) {
	parts, start, err := b.joinedParts(ctx, apiItemPID, opts.FilePID)
	if err != nil {
		return PlayInfo{}, err
	}
	first := parts[start]
	br := bookBitrate(parts)
	if opts.MaxBitrateKbps > 0 {
		br = min(br, opts.MaxBitrateKbps)
	}
	br = min(max(br, MinStreamBitrateKbps), MaxStreamBitrateKbps)
	if b.gate != nil {
		if ceiling := b.gate.MaxBitrateKbps(ctx, user); ceiling > 0 {
			br = min(br, ceiling)
		}
	}
	params := url.Values{}
	params.Set("f", first.FilePID)
	params.Set("join", "1")
	params.Set("fmt", "mp3")
	params.Set("br", strconv.Itoa(br))
	shapeKey := streamShape(params)
	token, exp := b.tokens.MintFor(auth.MediaClaims{
		User: user, Cred: opts.Cred, Purpose: auth.PurposeStream, PID: apiItemPID, Shape: shapeKey,
	}, opts.TTL)
	streamURL := "/media/stream?pid=" + url.QueryEscape(apiItemPID) + "&mt=" + url.QueryEscape(token) + "&" + shapeKey
	offset := opts.StartMS
	if d := first.Src.DurationMS; d > 0 {
		offset = min(offset, d-1)
	}
	if offset > 0 {
		streamURL += "&t=" + strconv.FormatFloat(float64(offset)/1000, 'f', -1, 64)
	} else {
		offset = 0
	}
	var durationMS int64
	for _, p := range parts[start:] {
		durationMS += p.Src.DurationMS
	}
	return PlayInfo{
		URL:                streamURL,
		MimeType:           formatMime["mp3"],
		DurationMS:         durationMS,
		ExpiresAt:          exp,
		AppliedBitrateKbps: br,
		StartOffsetMS:      offset,
	}, nil
}

// serveJoined answers a joined stream's fetch: the book's parts from the
// one the URL names to the last, asked of the engine one after another
// under one session slot and copied out as one stream of bare MP3 frames
// (mp3join.Response, which the engine-less join answers through too).
// HEAD gets the stream's own headers once the engine accepts the first
// part.
func (b *Bridge) serveJoined(w http.ResponseWriter, r *http.Request, user, pid string, q url.Values) {
	ctx := r.Context()
	parts, start, err := b.joinedParts(ctx, pid, q.Get("f"))
	if err != nil {
		writeJSONError(w, http.StatusNotFound, "not-found", "no streamable item with pid "+pid)
		return
	}
	// The whole book's envelope wherever the stream opens, so the engine
	// caches one rendering per part.
	rate, channels := joinedEnvelope(parts)
	parts = parts[start:]
	refs := make([]string, len(parts))
	for i, p := range parts {
		if refs[i], err = b.srcRef(p.Src.Path); err != nil {
			b.log.Error("joined stream resolution", "pid", pid, "part", p.FilePID, "err", err)
			writeJSONError(w, http.StatusInternalServerError, "internal", "item is not under a streamable root")
			return
		}
	}
	cut, cutMS, err := streamCut(q.Get("t"), Shape{Format: "mp3"}, parts[0].Src.DurationMS)
	if err != nil {
		writeJSONError(w, http.StatusBadRequest, "invalid-request", err.Error())
		return
	}
	// The engine's own rule for a live encode: a range from the start is
	// the whole stream, and any other is refused before a slot is taken.
	if mp3join.RangeRefused(r) {
		w.Header().Set("Accept-Ranges", "none")
		writeJSONError(w, http.StatusRequestedRangeNotSatisfiable, "invalid-request",
			"a live stream is not byte-addressable; seek with t= seconds")
		return
	}
	release, admitted := b.admit(ctx, w, user)
	if !admitted {
		return
	}
	defer release()

	params := url.Values{}
	params.Set("format", "mp3")
	params.Set("rate", strconv.Itoa(rate))
	params.Set("ch", strconv.Itoa(channels))
	if br := b.heldBitrate(ctx, user, q.Get("br")); br > 0 {
		params.Set("bitrate", strconv.Itoa(br))
	}
	out := mp3join.NewResponse(w, r, mp3join.Shape{Rate: rate, Channels: channels}, func(part string, err error) {
		b.log.Warn("joined stream broken off at a part", "pid", pid, "part", part, "err", err)
	})
	for i, p := range parts {
		params.Set("src", refs[i])
		params.Set("id", fmt.Sprintf("%d-%d", p.Src.Size, p.Src.MTimeNS))
		params.Del("t")
		if i == 0 && cut != "" {
			params.Set("t", cut)
		}
		resp, err := b.openPart(ctx, r.Method, params)
		if i > 0 {
			resp, err = b.reopenWhileBusy(ctx, r.Method, params, resp, err)
		}
		if i == 0 {
			// Before the first byte, the proxy's own answer, as for any
			// stream: never an empty 200, a request a shutdown cancelled
			// included, which is logged as nothing gone wrong.
			if err != nil {
				if ctx.Err() == nil {
					b.log.Error("joined stream", "pid", pid, "part", p.FilePID, "err", err)
				}
				writeJSONError(w, http.StatusBadGateway, "internal", "stream backend unavailable")
				return
			}
			if resp.StatusCode != http.StatusOK {
				b.relayRefusal(w, resp)
				return
			}
			if !out.Open() {
				resp.Body.Close()
				return
			}
		} else if err == nil && resp.StatusCode != http.StatusOK {
			resp.Body.Close()
			err = fmt.Errorf("the engine answered %d", resp.StatusCode)
		}
		if err != nil {
			out.BreakOff(p.FilePID, err)
		}
		func() {
			defer resp.Body.Close()
			out.CopyPart(p.FilePID, resp.Body, p.Src.DurationMS, cutMS)
		}()
		cutMS = 0 // the cut is the opening part's alone
	}
}

// seamRetries bounds the engine's refusals for load a seam waits out, and
// seamWaitCap each wait, in seconds of its Retry-After: a seam waits 15 s
// at most, and the engine sends its first 30 s of each part at twice
// realtime, so the listener holds more than that in hand.
const (
	seamRetries = 3
	seamWaitCap = 5
)

// reopenWhileBusy waits out the engine refusing a part because its own
// pool is full. At a seam WaxDeck already holds the listener's slot, but
// each part needs one of the engine's, which frees within seconds of any
// encode ending; breaking the book off there would stop it at the first
// seam that lands while anything else encodes. Any other answer is
// handed back as it came.
func (b *Bridge) reopenWhileBusy(ctx context.Context, method string, params url.Values, resp *http.Response, err error) (*http.Response, error) {
	for range seamRetries {
		if err != nil || !sidecarBusy(resp) {
			break
		}
		secs, convErr := strconv.Atoi(strings.TrimSpace(resp.Header.Get("Retry-After")))
		if convErr != nil || secs < 1 {
			secs = 2
		}
		resp.Body.Close()
		timer := time.NewTimer(time.Duration(min(secs, seamWaitCap)) * seamWaitUnit)
		select {
		case <-ctx.Done():
			timer.Stop()
			return nil, ctx.Err()
		case <-timer.C:
		}
		resp, err = b.openPart(ctx, method, params)
	}
	return resp, err
}

// seamWaitUnit is what a second of the engine's Retry-After waits; tests
// shorten it.
var seamWaitUnit = time.Second

// openPart asks the engine for one part's stream.
func (b *Bridge) openPart(ctx context.Context, method string, params url.Values) (*http.Response, error) {
	u := b.base.ResolveReference(&url.URL{Path: "/stream", RawQuery: params.Encode()})
	req, err := http.NewRequestWithContext(ctx, method, u.String(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-API-Key", b.apiKey)
	return http.DefaultClient.Do(req)
}

// relayRefusal answers the engine's refusal of a joined stream's first
// part as the proxy answers any stream's, in the API's envelope.
func (b *Bridge) relayRefusal(w http.ResponseWriter, resp *http.Response) {
	b.modifyResponse(resp)
	defer resp.Body.Close()
	for k, vals := range resp.Header {
		if hopByHopHeaders[k] {
			continue
		}
		for _, v := range vals {
			w.Header().Add(k, v)
		}
	}
	w.WriteHeader(resp.StatusCode)
	io.Copy(w, resp.Body)
}

// joinedParts lays out the book and finds the part a joined stream opens
// on: filePID's, or the first when it is empty.
func (b *Bridge) joinedParts(ctx context.Context, apiItemPID, filePID string) ([]Part, int, error) {
	pr, ok := b.resolver.(PartsResolver)
	if !ok {
		return nil, 0, errors.New("flow: the resolver lays out no books")
	}
	parts, err := pr.StreamParts(ctx, apiItemPID)
	if err != nil {
		return nil, 0, err
	}
	for i, p := range parts {
		if filePID == "" || p.FilePID == filePID {
			return parts, i, nil
		}
	}
	return nil, 0, fmt.Errorf("flow: %s has no part %q", apiItemPID, filePID)
}

// bookBitrate is the rate that loses nothing of the book's best part: the
// highest part's own, or the top rate where a part is lossless or
// unmeasured.
func bookBitrate(parts []Part) int {
	br := 0
	for _, p := range parts {
		if lossless(p.Src.Codec) || p.Src.BitrateKbps <= 0 {
			return MaxStreamBitrateKbps
		}
		br = max(br, p.Src.BitrateKbps)
	}
	return br
}

// layerIIIRates are the sample rates an MP3 frame can state, ascending.
var layerIIIRates = []int{8000, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000}

// joinedEnvelope is the one shape every part of a joined stream is
// encoded to, since a player sets its decoder up once per stream: the
// highest part rate, rounded up to one a frame can state (48 kHz at most),
// and the most channels, two at most. What the catalog does not know is
// CD stereo.
func joinedEnvelope(parts []Part) (rate, channels int) {
	for _, p := range parts {
		rate = max(rate, p.Rate)
		channels = max(channels, p.Channels)
	}
	if rate == 0 {
		rate = 44100
	}
	i, _ := slices.BinarySearch(layerIIIRates, rate)
	rate = layerIIIRates[min(i, len(layerIIIRates)-1)]
	if channels == 0 {
		channels = 2
	}
	return rate, min(channels, 2)
}

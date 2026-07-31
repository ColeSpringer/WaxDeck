package flow

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxflow/client"

	"github.com/colespringer/waxdeck/server/internal/db"
)

// Timeline support: a queue rendered as one gapless HLS presentation.
// The sidecar mints a content-addressed digest; WaxDeck signs a master
// playlist URL upstream and proxies the HLS surface through its own
// origin under a media token sized to the queue's duration. Child
// fetches are authorized by the upstream signature inside the URLs the
// playlists themselves carry, so the proxy never attaches its API key
// to an HLS request and a token holder can fetch nothing beyond what
// the signed playlists name.

// timelineInlineWait bounds how long a mint absorbs upstream member
// measurement before answering with a job instead.
const timelineInlineWait = 15 * time.Second

// TimelineMember is one queue entry with its resolved source.
type TimelineMember struct {
	PID string
	Src Source
}

// TimelineOptions are the listener's preferences for how a queue is
// rendered. They are a struct rather than two arguments because the
// call sites that get this wrong get it wrong by passing a zero: a cast
// reload that forgot the crossfade sounded like a different queue from
// the load before it, which is exactly what carrying the whole set
// together prevents.
type TimelineOptions struct {
	// CrossfadeSeconds is the equal-power fade at every seam, 0 to 12.
	CrossfadeSeconds float64
	// ReplayGain asks for the stream to be levelled. What that costs is
	// decided at the mint: with nothing measured, the render is asked
	// for gain=off and the listener hears the queue as it was mastered.
	ReplayGain bool
}

// TimelineBoundary places one member on the minted timeline.
type TimelineBoundary struct {
	PID             string
	OffsetSamples   int64
	DurationSamples int64
}

// TimelineResult is a minted timeline ready for clients or cast
// loads. When JobPID is set instead, measurement outlasted the inline
// wait: poll the job, then mint again.
type TimelineResult struct {
	URL              string
	MimeType         string
	DurationMS       int64
	ExpiresAt        time.Time
	EnvelopeRate     int
	CrossfadeSeconds float64
	Boundaries       []TimelineBoundary

	JobPID string
}

// stashedTimeline lets the HLS proxy reconstruct the signed upstream
// master URL for a digest. Persisted through TimelineStore when one is
// configured, so a restart does not turn every live timeline URL into a
// not-found; without a store it is memory only and a restart costs one
// re-mint per live timeline.
type stashedTimeline struct {
	signedMaster string
	expires      time.Time
}

// TimelineStore persists the stash across restarts. *db.DB implements
// it; nil leaves the stash in memory, which is what a bridge built
// without a database (the tests, and any caller that has none) gets.
//
// Restoring a row does not guarantee the sidecar can still serve it:
// the signed master is sidecar-signed, and under compose both processes
// restart together. That is why nothing here promises a restored row
// works, and why the read path treats an upstream miss on one as a
// re-mint, which is the same clean outcome an absent stash produces.
type TimelineStore interface {
	LoadTimelineStash(ctx context.Context, nowNS int64) ([]db.TimelineStash, error)
	PutTimelineStash(ctx context.Context, t db.TimelineStash, nowNS int64) error
	ForgetTimelineStash(ctx context.Context, digest string) error
}

// timelineState is the bridge's in-memory timeline bookkeeping. The
// stash mirrors the store; jobs are deliberately memory only, since an
// in-flight measurement job does not outlive the process that polls it.
type timelineState struct {
	mu    sync.Mutex
	stash map[string]stashedTimeline // digest -> signed master
	jobs  map[string]string          // WaxDeck job pid -> upstream job id
}

func (b *Bridge) timelines() *timelineState {
	b.tlOnce.Do(func() {
		b.tl = &timelineState{
			stash: make(map[string]stashedTimeline),
			jobs:  make(map[string]string),
		}
	})
	return b.tl
}

// loadTimelineStash reads the persisted mints back into memory at
// startup. The store drops expired rows in the same pass.
func (b *Bridge) loadTimelineStash(ctx context.Context) error {
	rows, err := b.tlStore.LoadTimelineStash(ctx, time.Now().UnixNano())
	if err != nil {
		return err
	}
	ts := b.timelines()
	ts.mu.Lock()
	defer ts.mu.Unlock()
	for _, r := range rows {
		ts.stash[r.Digest] = stashedTimeline{
			signedMaster: r.SignedMaster,
			expires:      time.Unix(0, r.ExpiresAtNS),
		}
	}
	return nil
}

// deadTimelineStatus reports whether an upstream answer means the
// stashed digest can never be served again, as opposed to a transient
// failure worth relaying.
func deadTimelineStatus(status int) bool {
	switch status {
	case http.StatusNotFound, http.StatusGone,
		http.StatusUnauthorized, http.StatusForbidden:
		return true
	}
	return false
}

// forgetTimeline drops one digest from both the memory stash and the
// store, for a timeline the sidecar has stopped serving.
func (b *Bridge) forgetTimeline(ctx context.Context, digest string) {
	ts := b.timelines()
	ts.mu.Lock()
	delete(ts.stash, digest)
	ts.mu.Unlock()
	if b.tlStore == nil {
		return
	}
	// The row is known dead, so dropping it does not ride the request
	// that discovered it: a client that gives up mid-answer would
	// otherwise cancel the cleanup its own fetch just proved necessary.
	ctx = context.WithoutCancel(ctx)
	if err := b.tlStore.ForgetTimelineStash(ctx, digest); err != nil {
		// Leaving the row costs nothing beyond one repeat of this same
		// eviction on the next fetch.
		b.log.Warn("dropping a dead timeline from the stash", "digest", digest, "err", err)
	}
}

// TimelinesSupported reports whether the sidecar mints timelines.
func (b *Bridge) TimelinesSupported() bool {
	return b.caps.Delivery.HLS && b.caps.Delivery.Timelines
}

// TimelineMemberWindowsSupported reports whether the sidecar accepts
// per-member sample windows on a timeline. When it does, a CUE-carved
// virtual track rides a gapless timeline as a window into its backing
// file instead of falling back to per-item URLs; an older sidecar 400s
// a windowed member, so callers route by this and refuse virtual
// members otherwise.
func (b *Bridge) TimelineMemberWindowsSupported() bool {
	return b.caps.Delivery.TimelineMemberWindows
}

// timelineFormat picks the HLS rendering format: AAC casts everywhere
// (the default receiver's safest codec), lossless FLAC when AAC is
// absent, then whatever the build offers.
func (b *Bridge) timelineFormat() string {
	formats := b.caps.Delivery.HLSFormats
	for _, want := range []string{"aac", "flac", "opus", "alac"} {
		for _, f := range formats {
			if f == want {
				return f
			}
		}
	}
	if len(formats) > 0 {
		return formats[0]
	}
	return "aac"
}

// TimelineFor mints a timeline over the members and signs its master
// playlist. A virtual track rides the timeline as a sample window into
// its backing file when the sidecar advertises member windows; without
// that support a virtual member has no timeline-member form, so the
// mint is refused and the caller treats the pid as timeline-ineligible.
func (b *Bridge) TimelineFor(ctx context.Context, user string, members []TimelineMember, opts TimelineOptions) (*TimelineResult, error) {
	if !b.TimelinesSupported() {
		return nil, fmt.Errorf("flow: sidecar mints no timelines")
	}
	req := client.TimelineRequest{CrossfadeSeconds: opts.CrossfadeSeconds}
	var totalMS int64
	for _, m := range members {
		if m.Src.Virtual && !b.TimelineMemberWindowsSupported() {
			return nil, fmt.Errorf("flow: %s is a virtual track and cannot join a timeline", m.PID)
		}
		ref, err := b.srcRef(m.Src.Path)
		if err != nil {
			return nil, err
		}
		src := client.TimelineSrc{Src: ref}
		if m.Src.Virtual {
			// A carved track is the half-open sample window [from, to) of
			// its backing file, the same span semantics /stream honors.
			src.From = m.Src.FromSample
			src.To = m.Src.ToSample
		}
		req.Srcs = append(req.Srcs, src)
		totalMS += m.Src.DurationMS
	}

	tl, jobID, err := b.mintTimeline(ctx, req)
	if err != nil {
		return nil, err
	}
	if tl == nil {
		// Measurement outlasted the inline wait; hand back a job the
		// caller can poll through the jobs surface.
		pid := "jb-" + ulid.MustNew(ulid.Timestamp(time.Now()), rand.Reader).String()
		ts := b.timelines()
		ts.mu.Lock()
		ts.jobs[pid] = jobID
		ts.mu.Unlock()
		return &TimelineResult{JobPID: pid}, nil
	}

	format := b.timelineFormat()
	ttl := time.Duration(totalMS)*time.Millisecond + 15*time.Minute
	if ttl < 30*time.Minute {
		ttl = 30 * time.Minute
	}
	// Timelines refuse tag-driven gain modes upstream (many sources, one
	// stream), so the gain is always explicit: a number the queue's own
	// stored measurements produced, or off.
	gain := "off"
	if opts.ReplayGain {
		if db, ok := TimelineGainDB(members); ok {
			gain = trimFloat(db)
		}
	}
	params := map[string]string{
		"tl":     tl.Tl,
		"format": format,
		"gain":   gain,
	}
	if opts.CrossfadeSeconds > 0 {
		// The identical value must ride the render, or the minted
		// boundaries describe a different presentation.
		params["crossfadeSeconds"] = trimFloat(opts.CrossfadeSeconds)
	}
	signed, err := b.client.Sign(ctx, client.SignRequest{
		Path:       "/hls/master.m3u8",
		Params:     params,
		TTLSeconds: int64(ttl / time.Second),
	})
	if err != nil {
		return nil, fmt.Errorf("flow: signing timeline master: %w", err)
	}

	token, exp := b.tokens.MintFor(user, "tl-"+tl.Tl, ttl)
	now := time.Now()
	ts := b.timelines()
	ts.mu.Lock()
	ts.stash[tl.Tl] = stashedTimeline{signedMaster: signed.URL, expires: exp}
	for digest, st := range ts.stash {
		if now.After(st.expires) {
			delete(ts.stash, digest)
		}
	}
	ts.mu.Unlock()
	if b.tlStore != nil {
		// A failed write degrades to the memory-only behavior this stash
		// had before it was persisted: the URL works until the next
		// restart, which then costs one re-mint.
		row := db.TimelineStash{Digest: tl.Tl, SignedMaster: signed.URL, ExpiresAtNS: exp.UnixNano()}
		if err := b.tlStore.PutTimelineStash(ctx, row, now.UnixNano()); err != nil {
			b.log.Warn("persisting a minted timeline", "digest", tl.Tl, "err", err)
		}
	}

	out := &TimelineResult{
		URL:              "/media/hls/master.m3u8?tl=" + url.QueryEscape(tl.Tl) + "&mt=" + url.QueryEscape(token),
		MimeType:         "application/vnd.apple.mpegurl",
		DurationMS:       int64(tl.DurationSeconds * 1000),
		ExpiresAt:        exp,
		EnvelopeRate:     tl.EnvelopeRate,
		CrossfadeSeconds: opts.CrossfadeSeconds,
	}
	for i, bd := range tl.Boundaries {
		pid := ""
		if i < len(members) {
			pid = members[i].PID
		}
		out.Boundaries = append(out.Boundaries, TimelineBoundary{
			PID:             pid,
			OffsetSamples:   bd.OffsetSamples,
			DurationSamples: bd.DurationSamples,
		})
	}
	return out, nil
}

// mintTimeline creates the timeline, absorbing short measurement jobs
// inline. A nil timeline with a job id means the wait ran out.
func (b *Bridge) mintTimeline(ctx context.Context, req client.TimelineRequest) (*client.TimelineResponse, string, error) {
	tl, jobID, err := b.client.CreateTimeline(ctx, req)
	if err != nil {
		return nil, "", fmt.Errorf("flow: minting timeline: %w", err)
	}
	if tl != nil {
		return tl, "", nil
	}
	deadline := time.Now().Add(timelineInlineWait)
	for time.Now().Before(deadline) {
		select {
		case <-ctx.Done():
			return nil, "", ctx.Err()
		case <-time.After(time.Second):
		}
		job, err := b.client.Job(ctx, jobID)
		if err != nil {
			return nil, "", fmt.Errorf("flow: polling timeline job: %w", err)
		}
		switch job.State {
		case "done":
			if job.Timeline == nil {
				return nil, "", fmt.Errorf("flow: timeline job %s finished without a timeline", jobID)
			}
			// A finished timeline job carries the same digest and boundaries
			// CreateTimeline's inline answer does, under the job-document type.
			return &client.TimelineResponse{
				Tl:              job.Timeline.Tl,
				Members:         job.Timeline.Members,
				DurationSeconds: job.Timeline.DurationSeconds,
				EnvelopeRate:    job.Timeline.EnvelopeRate,
				Boundaries:      job.Timeline.Boundaries,
			}, "", nil
		case "queued", "running":
		default:
			msg := job.State
			if job.Error != nil {
				msg = job.Error.Code + ": " + job.Error.Message
			}
			return nil, "", fmt.Errorf("flow: timeline job %s failed: %s", jobID, msg)
		}
	}
	return nil, jobID, nil
}

// TimelineJob reports a pending timeline-measurement job's state:
// queued, running, done, or failed. Unknown pids answer false.
func (b *Bridge) TimelineJob(ctx context.Context, jobPID string) (state string, ok bool) {
	ts := b.timelines()
	ts.mu.Lock()
	upstream, found := ts.jobs[jobPID]
	ts.mu.Unlock()
	if !found {
		return "", false
	}
	job, err := b.client.Job(ctx, upstream)
	if err != nil {
		return "failed", true
	}
	switch job.State {
	case "queued", "running", "done":
		return job.State, true
	default:
		return "failed", true
	}
}

// ServeHLS proxies the sidecar's HLS surface under media tokens. The
// mt parameter must verify and bind a timeline pid; everything else in
// the URL is what the upstream-signed playlists themselves carry, so
// authorization for the actual bytes is the upstream signature, and
// the proxy attaches no API key here.
func (b *Bridge) ServeHLS(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	token := q.Get("mt")
	_, pid, err := b.tokens.VerifyAny(token)
	if err != nil || !strings.HasPrefix(pid, "tl-") {
		writeJSONError(w, http.StatusUnauthorized, "unauthenticated", "invalid or expired media token")
		return
	}

	var upstreamURL, stashed string
	if strings.HasSuffix(r.URL.Path, "/master.m3u8") && q.Get("tl") != "" {
		// The master fetch names the digest; the stashed signed URL
		// carries the format and crossfade the mint chose.
		digest := q.Get("tl")
		if pid != "tl-"+digest {
			writeJSONError(w, http.StatusUnauthorized, "unauthenticated", "token does not match this timeline")
			return
		}
		ts := b.timelines()
		ts.mu.Lock()
		st, ok := ts.stash[digest]
		ts.mu.Unlock()
		if !ok {
			writeJSONError(w, http.StatusNotFound, "not-found", "this timeline URL is no longer live; re-request it")
			return
		}
		upstreamURL = st.signedMaster
		stashed = digest
	} else {
		// Child fetches (variant playlists, init, segments) carry the
		// upstream-signed query verbatim plus our mt, which we strip.
		q.Del("mt")
		rel := strings.TrimPrefix(r.URL.Path, "/media/hls")
		upstreamURL = "/hls" + rel + "?" + q.Encode()
	}

	upstream, err := url.Parse(upstreamURL)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "internal", "bad upstream URL")
		return
	}

	req, err := http.NewRequestWithContext(r.Context(), http.MethodGet, b.base.ResolveReference(upstream).String(), nil)
	if err != nil {
		writeJSONError(w, http.StatusInternalServerError, "internal", "building upstream request")
		return
	}
	if rg := r.Header.Get("Range"); rg != "" {
		req.Header.Set("Range", rg)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		writeJSONError(w, http.StatusBadGateway, "internal", "stream backend unavailable")
		return
	}
	defer resp.Body.Close()

	// A stashed digest the sidecar will not serve is dead. Drop it so the
	// next fetch takes the absent-stash path, and answer the same
	// re-request an absent stash gives rather than relaying the upstream
	// status: persisting the stash is only worth doing if a restored row
	// that cannot be served fails the same clean way an unrestored one
	// does.
	//
	// Three ways it dies, and the signature ones are why this is not just
	// 404. The sidecar no longer holds the digest (404). The files moved
	// underneath a live one (410, which keeps its own code because it
	// means something different). Or the stashed signature no longer
	// verifies (401 unauthorized, 403 signature-invalid or
	// signature-expired), which is what a sidecar whose signing secret
	// was regenerated answers -- it is auto-generated into its data dir,
	// so recreating that volume alone rotates it under an otherwise
	// untouched stash.
	if stashed != "" && deadTimelineStatus(resp.StatusCode) {
		b.forgetTimeline(r.Context(), stashed)
		if resp.StatusCode != http.StatusGone {
			writeJSONError(w, http.StatusNotFound, "not-found", "this timeline URL is no longer live; re-request it")
			return
		}
	}
	if resp.StatusCode == http.StatusGone {
		writeJSONError(w, http.StatusGone, "stream-stale", "the timeline no longer matches the files on disk; re-request it")
		return
	}

	ct := resp.Header.Get("Content-Type")
	isPlaylist := strings.Contains(ct, "mpegurl") || strings.HasSuffix(r.URL.Path, ".m3u8")
	for k, vals := range resp.Header {
		if k == "Content-Length" && isPlaylist {
			continue
		}
		if hopByHopHeaders[k] {
			continue
		}
		for _, v := range vals {
			w.Header().Add(k, v)
		}
	}
	if !isPlaylist || resp.StatusCode != http.StatusOK {
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body)
		return
	}

	// Playlist bodies get every URI stamped with the same media token
	// this fetch presented, so the player's child requests stay
	// authorized at this origin.
	body, err := io.ReadAll(io.LimitReader(resp.Body, 8<<20))
	if err != nil {
		writeJSONError(w, http.StatusBadGateway, "internal", "reading upstream playlist")
		return
	}
	rewritten := rewritePlaylist(body, token)
	w.Header().Set("Content-Length", fmt.Sprint(len(rewritten)))
	w.WriteHeader(resp.StatusCode)
	w.Write(rewritten)
}

// rewritePlaylist appends the media token to every URI in an m3u8
// document: plain URI lines and URI="..." attributes on tag lines.
func rewritePlaylist(body []byte, token string) []byte {
	var out bytes.Buffer
	sc := bufio.NewScanner(bytes.NewReader(body))
	sc.Buffer(make([]byte, 0, 64*1024), 8<<20)
	for sc.Scan() {
		line := sc.Text()
		switch {
		case strings.HasPrefix(line, "#") && strings.Contains(line, `URI="`):
			start := strings.Index(line, `URI="`) + len(`URI="`)
			end := strings.Index(line[start:], `"`)
			if end < 0 {
				out.WriteString(line)
			} else {
				uri := line[start : start+end]
				out.WriteString(line[:start])
				out.WriteString(appendToken(uri, token))
				out.WriteString(line[start+end:])
			}
		case line == "" || strings.HasPrefix(line, "#"):
			out.WriteString(line)
		default:
			out.WriteString(appendToken(line, token))
		}
		out.WriteByte('\n')
	}
	return out.Bytes()
}

func appendToken(uri, token string) string {
	sep := "?"
	if strings.Contains(uri, "?") {
		sep = "&"
	}
	return uri + sep + "mt=" + url.QueryEscape(token)
}

// hopByHopHeaders never cross a proxy boundary (RFC 9110 section
// 7.6.1); the manual HLS relay strips them like ReverseProxy would.
var hopByHopHeaders = map[string]bool{
	"Connection":          true,
	"Proxy-Connection":    true,
	"Keep-Alive":          true,
	"Proxy-Authenticate":  true,
	"Proxy-Authorization": true,
	"Te":                  true,
	"Trailer":             true,
	"Transfer-Encoding":   true,
	"Upgrade":             true,
}

func trimFloat(f float64) string {
	s := fmt.Sprintf("%.3f", f)
	s = strings.TrimRight(s, "0")
	return strings.TrimRight(s, ".")
}

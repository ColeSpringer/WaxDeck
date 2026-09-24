package flow

import (
	"bufio"
	"bytes"
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxflow/client"
	"github.com/colespringer/waxflow/waxerr"

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

// ErrTimelineUnrenderable is the refusal of a queue rather than a fault
// of the server's: every member resolved and was visible, and the
// renderer still will not make one stream of them. Distinct from every
// other error a mint can return, because those are the server being
// broken - a sidecar that is down, a signature that would not sign -
// and answering those as a refusal of the queue tells the caller to
// stop asking and takes the outage out of the error rate.
var ErrTimelineUnrenderable = errors.New("this queue cannot be rendered as one timeline")

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
	// Formats are the caller's decodable formats, most preferred first.
	// Empty means the default ladder, which is what a cast receiver
	// wants; a browser names what its media source actually accepts,
	// since a rendering it cannot decode is silence with no error.
	Formats []string
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
	// PID addresses this rendering for release. Minted with the stash
	// row and stable across a re-mint of the same rendering.
	PID              string
	URL              string
	MimeType         string
	DurationMS       int64
	ExpiresAt        time.Time
	EnvelopeRate     int
	CrossfadeSeconds float64
	Format           string
	Boundaries       []TimelineBoundary

	JobPID string
}

// stashedTimeline lets the HLS proxy reconstruct the signed upstream
// master URL for a timeline key. Persisted through TimelineStore when
// one is configured, so a restart does not turn every live timeline URL
// into a not-found; without a store it is memory only and a restart
// costs one re-mint per live timeline.
type stashedTimeline struct {
	// id names this row on the client-facing surface, so a client can
	// release the rendering it stopped playing. The stash key holds a
	// slash and cannot be a path segment; this is minted per row and
	// outlives a re-mint of the same rendering.
	id           string
	signedMaster string
	expires      time.Time
	// listeners is when each listener last asked for any part of this
	// rendering. It is what lets a slot be given back: a listener who
	// paused an hour ago is not holding the server's capacity, and a
	// fragment fetch takes it again.
	//
	// A map rather than one owner, because the key is a content digest
	// and a rendering: two accounts playing the same album with the same
	// gain and crossfade share the row, which is the point - one render
	// serves both. With one owner the second mint took the row over, and
	// the first listener's fetches then counted for nobody, so the sweep
	// took her slot back mid-track while she was still fetching.
	listeners map[string]time.Time
}

func (st stashedTimeline) listening(user string, now time.Time) bool {
	at, ok := st.listeners[user]
	return ok && now.Sub(at) < timelineIdle
}

// timelineIdle is how long every one of a listener's timelines must go
// unfetched before their slot goes back. Long enough that a paused
// track, a tab switch, or a slow seek does not cost the slot; short
// enough that a browser closed mid-listen gives it up promptly. hls.js
// never re-fetches the master, so the fetch that takes the slot again
// is a fragment.
const timelineIdle = 60 * time.Second

// timelineKey identifies one rendering of one queue. The sidecar's
// digest names the sources and the seams; everything else that shapes
// what comes out of the encoder - the format, the gain, the crossfade -
// lives inside the signed master URL and nowhere in that digest. Keying
// the stash by the digest alone therefore let a second mint of the same
// queue in another format overwrite the first, and the browser that
// minted FLAC because it cannot decode AAC would then be handed AAC by
// a cast mint that happened afterwards. Both renderings are live at
// once here instead.
func timelineKey(digest, render string) string { return digest + "/" + render }

// renderKey names one rendering's encoder settings. Readable rather
// than hashed: it rides the client's URL, and a support answer about a
// timeline is easier when the URL says which one it is.
func renderKey(format, gain string, crossfadeSeconds float64) string {
	return format + "~" + gain + "~" + trimFloat(crossfadeSeconds)
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
	ForgetTimelineStash(ctx context.Context, key string) error
}

// timelineState is the bridge's in-memory timeline bookkeeping. The
// stash mirrors the store; jobs are deliberately memory only, since an
// in-flight measurement job does not outlive the process that polls it.
type timelineState struct {
	mu    sync.Mutex
	stash map[string]stashedTimeline // timeline key -> signed master
	ids   map[string]string          // row id -> timeline key
	jobs  map[string]string          // WaxDeck job pid -> upstream job id
	// minting counts each listener's mints that have taken a slot and
	// not yet stashed a rendering. In that window nothing in the stash
	// speaks for them, so a release arriving mid-mint would read as
	// "listening to nothing" and hand the slot back.
	minting map[string]int
	// slots holds one transcode slot per listener with live timelines,
	// not one per timeline. The feeder mints a replacement on a queue
	// edit while the one playing is still being fetched, and a per-mint
	// slot under a per-user cap of one would refuse that re-mint - then
	// the progressive fallback under the same cap - and stall the music
	// at the seam the edit was made in.
	slots map[string]timelineSlot // user -> the slot they hold
}

// timelineSlot is one listener's held transcode slot. `taken` is what
// keeps the sweeper off a slot a mint is still assembling a rendering
// for: until that rendering is stashed there is nothing to say the
// listener is listening.
type timelineSlot struct {
	release func()
	taken   time.Time
}

// forget drops one stash row and the id that addressed it. The caller
// holds the lock.
func (ts *timelineState) forget(key string) {
	if st, ok := ts.stash[key]; ok {
		delete(ts.ids, st.id)
	}
	delete(ts.stash, key)
}

func (b *Bridge) timelines() *timelineState {
	b.tlOnce.Do(func() {
		b.tl = &timelineState{
			stash:   make(map[string]stashedTimeline),
			ids:     make(map[string]string),
			jobs:    make(map[string]string),
			minting: make(map[string]int),
			slots:   make(map[string]timelineSlot),
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
		ts.stash[r.Key] = stashedTimeline{
			id:           r.ID,
			signedMaster: r.SignedMaster,
			expires:      time.Unix(0, r.ExpiresAtNS),
		}
		ts.ids[r.ID] = r.Key
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

// forgetTimeline drops one timeline key from both the memory stash and
// the store, for a rendering the sidecar has stopped serving. Only that
// rendering: a signature that stopped verifying is this URL's, and a
// sibling rendering of the same queue proves its own death on its own
// next fetch.
func (b *Bridge) forgetTimeline(ctx context.Context, key string) {
	ts := b.timelines()
	ts.mu.Lock()
	ts.forget(key)
	ts.mu.Unlock()
	if b.tlStore == nil {
		return
	}
	// The row is known dead, so dropping it does not ride the request
	// that discovered it: a client that gives up mid-answer would
	// otherwise cancel the cleanup its own fetch just proved necessary.
	ctx = context.WithoutCancel(ctx)
	if err := b.tlStore.ForgetTimelineStash(ctx, key); err != nil {
		// Leaving the row costs nothing beyond one repeat of this same
		// eviction on the next fetch.
		b.log.Warn("dropping a dead timeline from the stash", "timeline", key, "err", err)
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

// timelineFormat picks the HLS rendering format. The caller's own
// preferences win in the order they gave them: a browser knows what its
// media source will decode, and a rendering it cannot decode is silence
// with no error to explain it. Without preferences, or with none the
// engine can produce, the default ladder decides: AAC casts everywhere
// (the default receiver's safest codec), lossless FLAC when AAC is
// absent, then whatever the build offers.
func (b *Bridge) timelineFormat(ctx context.Context, user string, prefs []string) string {
	formats := b.caps.Delivery.HLSFormats
	// A bitrate ceiling is a ceiling however the queue is delivered.
	// The progressive path applies the account's, so a listener who
	// switched gapless on would otherwise be handed a lossless render
	// of a whole queue by the same server that caps their single
	// tracks - many times the bytes, on the connection the cap was set
	// for. Dropped from the caller's preferences too, since those are
	// what wins: a browser asking for FLAC first is saying what it can
	// decode, not what it is allowed.
	if b.gate != nil && b.gate.MaxBitrateKbps(ctx, user) > 0 {
		if lossy := withoutLossless(formats); len(lossy) > 0 {
			formats = lossy
			prefs = withoutLossless(prefs)
		}
	}
	for _, want := range prefs {
		for _, f := range formats {
			if f == want {
				return f
			}
		}
	}
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

// withoutLossless drops the formats that carry the whole sample.
func withoutLossless(formats []string) []string {
	out := make([]string, 0, len(formats))
	for _, f := range formats {
		if f == "flac" || f == "alac" {
			continue
		}
		out = append(out, f)
	}
	return out
}

// holdTimelineSlot reserves the listener's timeline slot when they hold
// none. `fresh` says whether this call is the one that took it, which is
// what a failed mint has to give back.
func (b *Bridge) holdTimelineSlot(ctx context.Context, user string) (fresh bool, err error) {
	if b.gate == nil {
		return false, nil
	}
	ts := b.timelines()
	ts.mu.Lock()
	_, held := ts.slots[user]
	ts.mu.Unlock()
	if held {
		return false, nil
	}
	// Outside the lock: the gate reads the database to decide, and a
	// stalled read must not hold every other listener's timeline
	// bookkeeping behind it.
	release, err := b.gate.Acquire(ctx, user, TranscodeTimeline)
	if err != nil {
		return false, err
	}
	ts.mu.Lock()
	if _, raced := ts.slots[user]; raced {
		ts.mu.Unlock()
		release()
		return false, nil
	}
	ts.slots[user] = timelineSlot{release: release, taken: time.Now()}
	ts.mu.Unlock()
	return true, nil
}

// dropTimelineSlot gives a listener's slot back, for a mint that took
// one and then failed.
//
// Kept when they have a live rendering, which is what makes a failed
// mint safe to concurrently run beside a good one: two mints for one
// listener share the slot the first took, and an unconditional drop
// then let the failure hand back the slot the success is riding - a
// timeline streaming outside the cap and outside what the admin console
// reports.
func (b *Bridge) dropTimelineSlot(user string) {
	// A rendering they are on at all, not only one they are fetching:
	// the mint that failed is the one holding this slot, so a slot taken
	// moments ago is exactly what has to go back here.
	b.dropTimelineSlotUnless(user, func(st stashedTimeline, _ time.Time) bool {
		_, on := st.listeners[user]
		return on
	})
}

// dropTimelineSlotUnless gives a listener's slot back unless one of
// their live renderings still holds it, which `holds` decides. A failed
// mint keeps the slot for any rendering they are on at all; a release
// keeps it only for one they are still fetching, because a rendering
// paused an hour ago is not holding the server's capacity.
//
// A mint of theirs still assembling a rendering keeps it either way,
// because that is the window where the stash says nothing about them.
// A release needs it: a client that stopped and started again inside
// one round trip sends its release while the restart's mint is running,
// and without this that release takes the slot the new rendering is
// about to stream on - live, uncounted, and outside the per-user cap.
// So does a failed mint, for the same window on the other side: one of
// two concurrent mints failing must not hand back the slot the other is
// about to stream on. Which is why TimelineFor stops counting itself
// before this runs - a mint that spared its own slot would leak it to
// the sweep. The sweep guards the same window with the slot's own age;
// a re-mint reuses the slot it finds rather than taking a fresh one, so
// age says nothing here and the mint in flight has to say it itself.
func (b *Bridge) dropTimelineSlotUnless(user string, holds func(stashedTimeline, time.Time) bool) {
	now := time.Now()
	ts := b.timelines()
	ts.mu.Lock()
	for _, st := range ts.stash {
		if now.After(st.expires) {
			continue
		}
		if holds(st, now) {
			ts.mu.Unlock()
			return
		}
	}
	if ts.minting[user] > 0 {
		ts.mu.Unlock()
		return
	}
	slot, ok := ts.slots[user]
	delete(ts.slots, user)
	ts.mu.Unlock()
	if ok {
		slot.release()
	}
}

// ReleaseTimeline drops a listener from one rendering and gives their
// slot back when none of their other renderings has been fetched inside
// the idle window. It reports whether there was a rendering of theirs
// to release: an unknown or expired id answers false, and so does one
// they are not a listener on, which the handler turns into a 404.
//
// The rendering itself stays. Another listener may be on it, and the
// caller's own URL keeps working until it expires - a fetch simply
// takes the slot again, the way resuming a paused listen does.
func (b *Bridge) ReleaseTimeline(user, id string) bool {
	now := time.Now()
	ts := b.timelines()
	ts.mu.Lock()
	key, ok := ts.ids[id]
	if !ok {
		ts.mu.Unlock()
		return false
	}
	st, live := ts.stash[key]
	if !live || now.After(st.expires) {
		ts.mu.Unlock()
		return false
	}
	if _, on := st.listeners[user]; !on {
		// Not theirs to let go of. Answering 204 to a pid the caller was
		// never on makes this an oracle for whether somebody else's
		// rendering is live, and drops the caller's own slot as a side
		// effect of asking.
		ts.mu.Unlock()
		return false
	}
	delete(st.listeners, user)
	ts.stash[key] = st
	ts.mu.Unlock()
	b.dropTimelineSlotUnless(user, func(st stashedTimeline, now time.Time) bool {
		return st.listening(user, now)
	})
	return true
}

// SweepTimelineSlots gives back the slot of every listener whose
// timelines have all gone quiet or expired, and drops the expired rows
// with them. Called on a ticker by the process's supervised group,
// which is where every other periodic sweep in this server lives.
func (b *Bridge) SweepTimelineSlots() {
	now := time.Now()
	ts := b.timelines()
	ts.mu.Lock()
	listening := make(map[string]bool, len(ts.slots))
	for key, st := range ts.stash {
		if now.After(st.expires) {
			ts.forget(key)
			continue
		}
		for user, at := range st.listeners {
			if now.Sub(at) < timelineIdle {
				listening[user] = true
			}
		}
	}
	var gone []func()
	for user, slot := range ts.slots {
		if listening[user] {
			continue
		}
		// A slot taken moments ago belongs to a mint still assembling
		// its rendering: it has nothing stashed to be listening to yet,
		// and taking it back here would leave that mint streaming
		// uncounted.
		if now.Sub(slot.taken) < timelineIdle {
			continue
		}
		gone = append(gone, slot.release)
		delete(ts.slots, user)
	}
	ts.mu.Unlock()
	// Outside the lock: a release is the service layer's counter, and
	// nothing here needs to see it happen.
	for _, release := range gone {
		release()
	}
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
	// Marked before the slot is taken and cleared after the row is
	// stashed: everything between is a window where this listener holds
	// capacity that nothing in the stash accounts for.
	ts := b.timelines()
	ts.mu.Lock()
	ts.minting[user]++
	ts.mu.Unlock()
	// Given back on every way out that is not a live timeline: a mint
	// that failed is not a listener holding capacity.
	//
	// Registered before the decrement below and so running after it, on
	// purpose: the drop spares a slot while another mint of this
	// listener's is in flight, and a mint still counting itself would
	// spare its own and leak it to the sweep.
	fresh, minted := false, false
	defer func() {
		if fresh && !minted {
			b.dropTimelineSlot(user)
		}
	}()
	defer func() {
		ts.mu.Lock()
		if ts.minting[user] <= 1 {
			delete(ts.minting, user)
		} else {
			ts.minting[user]--
		}
		ts.mu.Unlock()
	}()
	// Before the render, not after: a listener over the cap is told so
	// before the server spends anything on them, exactly as a
	// progressive stream refuses before it opens.
	var err error
	fresh, err = b.holdTimelineSlot(ctx, user)
	if err != nil {
		return nil, err
	}
	req := client.TimelineRequest{CrossfadeSeconds: opts.CrossfadeSeconds}
	var totalMS int64
	for _, m := range members {
		if m.Src.Virtual && !b.TimelineMemberWindowsSupported() {
			return nil, fmt.Errorf("%w: %s is a virtual track", ErrTimelineUnrenderable, m.PID)
		}
		ref, err := b.srcRef(m.Src.Path)
		if err != nil {
			// A source outside every configured root, which is about
			// this queue's members and not about the server.
			return nil, fmt.Errorf("%w: %s has no source the engine can reach", ErrTimelineUnrenderable, m.PID)
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

	format := b.timelineFormat(ctx, user, opts.Formats)
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

	render := renderKey(format, gain, opts.CrossfadeSeconds)
	key := timelineKey(tl.Tl, render)
	token, exp := b.tokens.MintFor(user, "tl-"+key, ttl)
	now := time.Now()
	ts.mu.Lock()
	// Merged rather than replaced: another listener may already be on
	// this rendering, and dropping their last fetch would take their
	// slot back mid-track.
	held := ts.stash[key]
	if held.listeners == nil {
		held.listeners = map[string]time.Time{}
	}
	if held.id == "" {
		held.id = ulid.Make().String()
	}
	ts.ids[held.id] = key
	held.signedMaster = signed.URL
	held.expires = exp
	// A rendering nobody has fetched yet is not idle: the player is
	// about to ask for it, and a sweep in between would take the slot
	// back a second before the first fragment.
	held.listeners[user] = now
	ts.stash[key] = held
	id := held.id
	minted = true
	for k, st := range ts.stash {
		if now.After(st.expires) {
			ts.forget(k)
		}
	}
	ts.mu.Unlock()
	if b.tlStore != nil {
		// A failed write degrades to the memory-only behavior this stash
		// had before it was persisted: the URL works until the next
		// restart, which then costs one re-mint.
		row := db.TimelineStash{Key: key, ID: id, SignedMaster: signed.URL, ExpiresAtNS: exp.UnixNano()}
		if err := b.tlStore.PutTimelineStash(ctx, row, now.UnixNano()); err != nil {
			b.log.Warn("persisting a minted timeline", "timeline", key, "err", err)
		}
	}

	out := &TimelineResult{
		PID: "tl-" + id,
		URL: "/media/hls/master.m3u8?tl=" + url.QueryEscape(tl.Tl) +
			"&rk=" + url.QueryEscape(render) + "&mt=" + url.QueryEscape(token),
		MimeType:         "application/vnd.apple.mpegurl",
		DurationMS:       int64(tl.DurationSeconds * 1000),
		ExpiresAt:        exp,
		EnvelopeRate:     tl.EnvelopeRate,
		CrossfadeSeconds: opts.CrossfadeSeconds,
		Format:           format,
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
		// The engine's own taxonomy decides which of the two answers
		// this is. A request it refused is about this queue, and the
		// caller's move is to play the items one at a time; anything
		// else - the sidecar down, a socket that broke, an overloaded
		// daemon - is this server being unwell, and saying "your queue
		// cannot be rendered" to that both tells the caller to stop
		// asking and takes an outage out of the error rate.
		if PermanentJobErr(err) {
			return nil, "", fmt.Errorf("%w (%s)", ErrTimelineUnrenderable, waxerr.CodeOf(err))
		}
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
				if PermanentJobErr(waxerr.New(waxerr.Code(job.Error.Code), job.Error.Message)) {
					return nil, "", fmt.Errorf("%w (%s)", ErrTimelineUnrenderable, job.Error.Code)
				}
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
	user, pid, err := b.tokens.VerifyAny(token)
	if err != nil || !strings.HasPrefix(pid, "tl-") {
		writeJSONError(w, http.StatusUnauthorized, "unauthenticated", "invalid or expired media token")
		return
	}
	// Every fetch of this timeline, master and fragment alike, says the
	// listener is still listening - and takes their slot again when a
	// quiet spell gave it back. hls.js never re-fetches the master, so
	// a resumed listen re-acquires on a fragment, which is why a refusal
	// here is one the player has to be able to explain rather than
	// recover from.
	if !b.touchTimeline(r.Context(), w, user, strings.TrimPrefix(pid, "tl-")) {
		return
	}

	var upstreamURL, stashed string
	if strings.HasSuffix(r.URL.Path, "/master.m3u8") && q.Get("tl") != "" {
		// The master fetch names the digest and the rendering; the
		// stashed signed URL is where the format, gain and crossfade the
		// mint chose actually live. A URL with no rendering on it is one
		// this server never minted, and misses the stash like any other.
		key := timelineKey(q.Get("tl"), q.Get("rk"))
		if pid != "tl-"+key {
			writeJSONError(w, http.StatusUnauthorized, "unauthenticated", "token does not match this timeline")
			return
		}
		ts := b.timelines()
		ts.mu.Lock()
		st, ok := ts.stash[key]
		ts.mu.Unlock()
		if !ok {
			writeJSONError(w, http.StatusNotFound, "not-found", "this timeline URL is no longer live; re-request it")
			return
		}
		upstreamURL = st.signedMaster
		stashed = key
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

	// A stashed rendering the sidecar will not serve is dead. Drop it so the
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

// touchTimeline marks a rendering as being listened to and makes sure
// its listener holds a slot, answering the request itself on refusal.
//
// Only for a rendering this server still holds. A player looping on a
// URL whose row was let go took a fresh slot on every retry and got its
// not-found anyway, so one dead client's retry loop refused other
// listeners' live mints a minute at a time - and answered "transcode
// limited", which a client is told not to recover from, where what the
// request actually needed was the not-found that says re-request.
func (b *Bridge) touchTimeline(ctx context.Context, w http.ResponseWriter, user, key string) bool {
	now := time.Now()
	ts := b.timelines()
	ts.mu.Lock()
	st, live := ts.stash[key]
	if live && now.After(st.expires) {
		live = false
	}
	if live {
		if st.listeners == nil {
			st.listeners = map[string]time.Time{}
		}
		st.listeners[user] = now
		ts.stash[key] = st
	}
	_, held := ts.slots[user]
	ts.mu.Unlock()
	if !live || held {
		return true
	}
	if _, err := b.holdTimelineSlot(ctx, user); err != nil {
		writeJSONError(w, http.StatusTooManyRequests, "transcode-limited",
			"the server's transcode session limit is reached; retry when a stream ends")
		return false
	}
	return true
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

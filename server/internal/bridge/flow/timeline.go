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
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxflow/client"
	"github.com/colespringer/waxflow/waxerr"

	"github.com/colespringer/waxdeck/server/internal/auth"
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

// TimelinePIDPrefix opens a gapless rendering's pid on the API and in its
// media token; one item's rendering is named by its item instead.
const TimelinePIDPrefix = "tl-"

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
	// Cred is the credential the timeline's token runs under
	// (auth.MediaClaims.Cred), the account's reach at mint: a timeline's
	// items are fixed when it is minted, so a change to what the account
	// may see has to end it.
	Cred string
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
// master URL for a rendering's key: a timeline's, or one item's
// (itemKey). Persisted through TimelineStore when one is configured, so
// a restart does not turn every live URL into a not-found; without a
// store it is memory only and a restart costs one re-mint per live
// rendering.
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
// timeline is easier when the URL says which one it is. A rate rides only
// where a ceiling set one.
func renderKey(format, gain string, crossfadeSeconds float64, bitrate int) string {
	key := format + "~" + gain + "~" + trimFloat(crossfadeSeconds)
	if bitrate > 0 {
		key += "~" + strconv.Itoa(bitrate)
	}
	return key
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

// timelineJob is a measurement a timeline mint outlasted: the upstream
// job, and the account whose queue it measures, the one account that
// may read it.
type timelineJob struct {
	upstream string
	user     string
}

// timelineState is the bridge's in-memory timeline bookkeeping. The
// stash mirrors the store; jobs are deliberately memory only, since an
// in-flight measurement job does not outlive the process that polls it.
type timelineState struct {
	mu    sync.Mutex
	stash map[string]stashedTimeline // timeline key -> signed master
	ids   map[string]string          // row id -> timeline key
	jobs  map[string]timelineJob     // WaxDeck job pid -> its measurement
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
	// acquiring marks a listener whose slot is being asked of the gate,
	// closed when the answer lands. Two first fetches of one listener at
	// once would otherwise both ask, and under a per-user cap of one the
	// second is refused for the slot the first is about to hold.
	acquiring map[string]chan struct{}
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
			stash:     make(map[string]stashedTimeline),
			ids:       make(map[string]string),
			jobs:      make(map[string]timelineJob),
			minting:   make(map[string]int),
			slots:     make(map[string]timelineSlot),
			acquiring: make(map[string]chan struct{}),
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

// TimelinesSupported reports whether the sidecar mints timelines, false
// while it is away.
func (b *Bridge) TimelinesSupported() bool { return timelinesSupported(b.Caps()) }

func timelinesSupported(caps *client.Caps) bool {
	return caps != nil && caps.Delivery.HLS && caps.Delivery.Timelines
}

// TimelineMemberWindowsSupported reports whether the sidecar accepts
// per-member sample windows on a timeline. When it does, a CUE-carved
// virtual track rides a gapless timeline as a window into its backing
// file instead of falling back to per-item URLs; an older sidecar 400s
// a windowed member, so callers route by this and refuse virtual
// members otherwise.
func (b *Bridge) TimelineMemberWindowsSupported() bool {
	caps := b.Caps()
	return caps != nil && caps.Delivery.TimelineMemberWindows
}

// timelineFormat picks the HLS rendering format. The caller's own
// preferences win in the order they gave them: a browser knows what its
// media source will decode, and a rendering it cannot decode is silence
// with no error to explain it. Without preferences, or with none the
// engine can produce, the default ladder decides: AAC casts everywhere
// (the default receiver's safest codec), lossless FLAC when AAC is
// absent, then whatever the build offers.
func timelineFormat(caps *client.Caps, prefs []string, ceiling int) string {
	formats := caps.Delivery.HLSFormats
	// A bitrate ceiling is a ceiling however the queue is delivered.
	// The progressive path applies the account's, so a listener who
	// switched gapless on would otherwise be handed a lossless render
	// of a whole queue by the same server that caps their single
	// tracks - many times the bytes, on the connection the cap was set
	// for. Dropped from the caller's preferences too, since those are
	// what wins: a browser asking for FLAC first is saying what it can
	// decode, not what it is allowed.
	if ceiling > 0 {
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
// what a failed mint has to give back. One item's rendering rides the
// same slot; kind only says which took it. A listener's asks of the gate
// go one at a time: one in flight is waited out, and its slot is this
// call's too.
func (b *Bridge) holdTimelineSlot(ctx context.Context, user string, kind TranscodeKind) (fresh bool, err error) {
	if b.gate == nil {
		return false, nil
	}
	ts := b.timelines()
	for {
		ts.mu.Lock()
		if _, held := ts.slots[user]; held {
			ts.mu.Unlock()
			return false, nil
		}
		asking, busy := ts.acquiring[user]
		if !busy {
			ts.acquiring[user] = make(chan struct{})
		}
		ts.mu.Unlock()
		if !busy {
			break
		}
		select {
		case <-asking:
		case <-ctx.Done():
			return false, ctx.Err()
		}
	}
	// Outside the lock: the gate reads the database to decide, and a
	// stalled read must not hold every other listener's timeline
	// bookkeeping behind it. The ask is settled however it ends, so a
	// listener's next one never waits on it for good.
	var release func()
	defer func() {
		ts.mu.Lock()
		close(ts.acquiring[user])
		delete(ts.acquiring, user)
		if fresh {
			ts.slots[user] = timelineSlot{release: release, taken: time.Now()}
		}
		ts.mu.Unlock()
	}()
	release, err = b.gate.Acquire(ctx, user, kind)
	return err == nil, err
}

// dropTimelineSlot gives a listener's slot back, for a mint that took
// one and then failed.
//
// Kept when a rendering of theirs has been minted or fetched since the
// slot was taken, which is what makes a failed mint safe to concurrently
// run beside a good one: two mints for one listener share the slot the
// first took, and an unconditional drop then let the failure hand back
// the slot the success is riding - a timeline streaming outside the cap
// and outside what the admin console reports. A rendering listed under
// them from before the slot (an item rendering stays listed from its
// mint, a queue played an hour ago) rides nothing of this one's.
func (b *Bridge) dropTimelineSlot(user string) {
	b.dropTimelineSlotUnless(user, func(st stashedTimeline, _, taken time.Time) bool {
		at, on := st.listeners[user]
		return on && !at.Before(taken)
	})
}

// dropTimelineSlotUnless gives a listener's slot back unless one of
// their live renderings still holds it, which `holds` decides from the
// rendering, the time, and when the slot was taken. A failed mint keeps
// the slot for a rendering they have been on since it was taken; a
// release keeps it only for one they are still fetching, because a
// rendering paused an hour ago is not holding the server's capacity.
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
func (b *Bridge) dropTimelineSlotUnless(user string, holds func(st stashedTimeline, now, taken time.Time) bool) {
	now := time.Now()
	ts := b.timelines()
	ts.mu.Lock()
	slot, ok := ts.slots[user]
	if !ok || ts.minting[user] > 0 {
		ts.mu.Unlock()
		return
	}
	for _, st := range ts.stash {
		if !now.After(st.expires) && holds(st, now, slot.taken) {
			ts.mu.Unlock()
			return
		}
	}
	delete(ts.slots, user)
	ts.mu.Unlock()
	slot.release()
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
	b.dropTimelineSlotUnless(user, func(st stashedTimeline, now, _ time.Time) bool {
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
	caps := b.Caps()
	if caps == nil {
		return nil, ErrEngineDown
	}
	if !timelinesSupported(caps) {
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
	fresh, err = b.holdTimelineSlot(ctx, user, TranscodeTimeline)
	if err != nil {
		return nil, err
	}
	req := client.TimelineRequest{CrossfadeSeconds: opts.CrossfadeSeconds}
	var totalMS int64
	for _, m := range members {
		if m.Src.Virtual && !caps.Delivery.TimelineMemberWindows {
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
	if b.engineGone(ctx, err) {
		return nil, ErrEngineDown
	}
	if err != nil {
		return nil, err
	}
	if tl == nil {
		// Measurement outlasted the inline wait; hand back a job the
		// caller can poll through the jobs surface.
		pid := "jb-" + ulid.MustNew(ulid.Timestamp(time.Now()), rand.Reader).String()
		ts := b.timelines()
		ts.mu.Lock()
		ts.jobs[pid] = timelineJob{upstream: jobID, user: user}
		ts.mu.Unlock()
		return &TimelineResult{JobPID: pid}, nil
	}

	ceiling := 0
	if b.gate != nil {
		ceiling = b.gate.MaxBitrateKbps(ctx, user)
	}
	format := timelineFormat(caps, opts.Formats, ceiling)
	// The ceiling holds the rendering to its rate, as it holds a track's
	// encode; the engine's own rate could be above it.
	bitrate := 0
	if ceiling > 0 && lossyBitrateFormats[format] {
		bitrate = min(max(ceiling, MinStreamBitrateKbps), MaxStreamBitrateKbps)
	}
	ttl := renderingTTL(totalMS)
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
	if bitrate > 0 {
		params["bitrate"] = strconv.Itoa(bitrate)
	}
	signed, err := b.client.Sign(ctx, client.SignRequest{
		Path:       "/hls/master.m3u8",
		Params:     params,
		TTLSeconds: int64(ttl / time.Second),
	})
	if b.engineGone(ctx, err) {
		return nil, ErrEngineDown
	}
	if err != nil {
		return nil, fmt.Errorf("flow: signing timeline master: %w", err)
	}

	render := renderKey(format, gain, opts.CrossfadeSeconds, bitrate)
	key := timelineKey(tl.Tl, render)
	token, exp := b.tokens.MintFor(auth.MediaClaims{
		User: user, Cred: opts.Cred, Purpose: auth.PurposeHLS, PID: TimelinePIDPrefix + key,
	}, ttl)
	id := b.stashRendering(ctx, user, key, signed.URL, exp)
	minted = true

	out := &TimelineResult{
		PID: TimelinePIDPrefix + id,
		URL: "/media/hls/master.m3u8?tl=" + url.QueryEscape(tl.Tl) +
			"&rk=" + url.QueryEscape(render) + "&mt=" + url.QueryEscape(token),
		MimeType:         hlsMimeType,
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

// renderingTTL is how long an HLS rendering's token and signature live:
// the content's length plus margin, so a listen never expires mid-way.
func renderingTTL(durationMS int64) time.Duration {
	return max(time.Duration(durationMS)*time.Millisecond+15*time.Minute, 30*time.Minute)
}

// stashRendering records a signed master under key, user listening as
// of now, drops the rows that expired, and persists the row when a store
// is configured. It answers the row's id.
func (b *Bridge) stashRendering(ctx context.Context, user, key, signedMaster string, exp time.Time) string {
	ts := b.timelines()
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
	held.signedMaster = signedMaster
	held.expires = exp
	// A rendering nobody has fetched yet is not idle: the player is
	// about to ask for it, and a sweep in between would take the slot
	// back a second before the first fragment.
	held.listeners[user] = now
	ts.stash[key] = held
	id := held.id
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
		row := db.TimelineStash{Key: key, ID: id, SignedMaster: signedMaster, ExpiresAtNS: exp.UnixNano()}
		if err := b.tlStore.PutTimelineStash(ctx, row, now.UnixNano()); err != nil {
			b.log.Warn("persisting a minted rendering", "rendering", key, "err", err)
		}
	}
	return id
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

// TimelineJob reports a pending timeline-measurement job's state to the
// account that minted it: queued, running, done, or failed. Unknown pids
// answer false, and so does another account's, so a pid's existence is
// not something one listener learns about another's queue.
func (b *Bridge) TimelineJob(ctx context.Context, user, jobPID string) (state string, ok bool) {
	ts := b.timelines()
	ts.mu.Lock()
	tj, found := ts.jobs[jobPID]
	ts.mu.Unlock()
	if !found || tj.user != user {
		return "", false
	}
	job, err := b.client.Job(ctx, tj.upstream)
	if err != nil {
		b.engineGone(ctx, err)
		return "failed", true
	}
	switch job.State {
	case "queued", "running", "done":
		return job.State, true
	default:
		return "failed", true
	}
}

// ServeHLS proxies the sidecar's HLS surface under media tokens: a
// queue's timeline, or one item's rendering. The mt parameter must
// verify and bind what the URL names, a timeline pid or an item and its
// rendering; everything else in the URL is what the upstream-signed
// playlists themselves carry, so authorization for the actual bytes is
// the upstream signature, and the proxy attaches no API key here.
func (b *Bridge) ServeHLS(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	token := q.Get("mt")
	master := strings.HasSuffix(r.URL.Path, "/master.m3u8")
	stashedMaster := master && (q.Get("tl") != "" || q.Get("it") != "")
	// A child (variant playlist, init, segment) carries the engine's own
	// signed query sealed beside the token it was handed out under, so
	// the listener never reads it and it opens under no other token.
	var child string
	if !stashedMaster {
		var err error
		if child, err = b.tokens.OpenQuery(token, q.Get("c")); err != nil {
			writeJSONError(w, http.StatusUnauthorized, "unauthenticated", "invalid or expired media token")
			return
		}
	}
	childQuery, _ := url.ParseQuery(child)
	desc, _ := decodeDescriptor(childQuery.Get("v"))
	// An item's rendering is named by the master URL, and by a child's own
	// descriptor; the token has to have been minted for that one. Whether
	// the fetch is one item's or a queue's is decided here, once.
	rendering := desc.rendering()
	if stashedMaster {
		rendering = q.Get("it")
	}
	item := rendering != ""
	want := auth.MediaWant{Purposes: []string{auth.PurposeHLS}, AnyPID: true}
	if item {
		want.Shape = itemShape(rendering)
	}
	claims, err := b.tokens.Verify(token, want)
	// A rendering's token names its item and never a timeline, whose pid
	// the per-fetch check would pass without asking about any item.
	if err != nil || item == strings.HasPrefix(claims.PID, TimelinePIDPrefix) {
		writeJSONError(w, http.StatusUnauthorized, "unauthenticated", "invalid or expired media token")
		return
	}
	// Master and every child fetch alike, so a timeline stops with its
	// account and with the reach it was minted under, and a rendering
	// with its account, its session and the account's right to the item.
	if !b.authorize(r.Context(), w, claims) {
		return
	}
	if !b.Up() {
		RefuseEngineDown(w)
		return
	}
	user, pid := claims.User, claims.PID
	key, what := strings.TrimPrefix(pid, TimelinePIDPrefix), "timeline"
	if item {
		key, what = itemKey(rendering), "stream"
		// The account's ceiling is read again at every fetch, as a stream's
		// is, and before a slot is taken: a rendering it no longer allows
		// is stale, which a player re-mints on, under the ceiling as it
		// is now.
		enc := desc
		if stashedMaster {
			enc = b.stashedDescriptor(key)
		}
		if b.ceilingDropped(r.Context(), user, enc) {
			writeJSONError(w, http.StatusGone, "stream-stale",
				"the account's bitrate ceiling is now below this stream's; re-request it")
			return
		}
	}
	// Every fetch of this rendering, master and fragment alike, says the
	// listener is still listening - and takes their slot again when a
	// quiet spell gave it back. hls.js never re-fetches the master, so
	// a resumed listen re-acquires on a fragment, which is why a refusal
	// here is one the player has to be able to explain rather than
	// recover from.
	if !b.touchTimeline(r.Context(), w, user, key, item) {
		return
	}

	var upstreamURL string
	if stashedMaster {
		// The master fetch names the rendering; the stashed signed URL is
		// where the format, gain and crossfade the mint chose actually
		// live. A URL with no rendering on it is one this server never
		// minted, and misses the stash like any other.
		if !item && pid != TimelinePIDPrefix+timelineKey(q.Get("tl"), q.Get("rk")) {
			writeJSONError(w, http.StatusUnauthorized, "unauthenticated", "token does not match this timeline")
			return
		}
		ts := b.timelines()
		ts.mu.Lock()
		st, ok := ts.stash[key]
		ts.mu.Unlock()
		if !ok {
			writeJSONError(w, http.StatusNotFound, "not-found", "this "+what+" URL is no longer live; re-request it")
			return
		}
		upstreamURL = st.signedMaster
	} else {
		// The engine's signature binds a child to its own timeline, not
		// to this token, so the token has to name the timeline the child
		// does as well as having sealed it: a timeline's descriptor names
		// its digest. A rendering's child was held to its token by its
		// own descriptor before the token was read.
		digest, _, _ := strings.Cut(key, "/")
		if !item && desc.Tl != digest {
			writeJSONError(w, http.StatusUnauthorized, "unauthenticated", "token does not match this timeline")
			return
		}
		rel := strings.TrimPrefix(r.URL.Path, "/media/hls")
		upstreamURL = "/hls" + rel + "?" + child
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
	resp, err := b.engineHTTP.Do(req)
	if err != nil {
		b.unreachable(r.Context(), err)
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
	if stashedMaster && deadTimelineStatus(resp.StatusCode) {
		b.forgetTimeline(r.Context(), key)
		if resp.StatusCode != http.StatusGone {
			writeJSONError(w, http.StatusNotFound, "not-found", "this "+what+" URL is no longer live; re-request it")
			return
		}
	}
	if resp.StatusCode == http.StatusGone {
		writeJSONError(w, http.StatusGone, "stream-stale", "the "+what+" no longer matches the files on disk; re-request it")
		return
	}
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusPartialContent {
		refuseAsTheAPI(w, resp, item)
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
	if !isPlaylist {
		w.WriteHeader(resp.StatusCode)
		io.Copy(w, resp.Body)
		return
	}

	// Playlist bodies get every URI stamped with the same media token
	// this fetch presented, so the player's child requests stay
	// authorized at this origin. Streamed a line at a time, whatever the
	// length: a long single-file book lists tens of thousands of segments.
	w.WriteHeader(http.StatusOK)
	if err := rewritePlaylist(w, resp.Body, token, b.tokens.QuerySealer(token).Append); err != nil {
		// Part of it is out already, and a well-formed end would read as
		// all of it, which a player then waits on for segments that never
		// come: the answer is torn down instead.
		if r.Context().Err() == nil {
			b.log.Warn("hls playlist broke off", "path", r.URL.Path, "err", err)
		}
		panic(http.ErrAbortHandler)
	}
}

// refuseAsTheAPI answers a child the engine would not serve in the API's
// envelope (engineRefusal), never the engine's own body. item says the
// child is one item's rendering rather than a timeline's.
func refuseAsTheAPI(w http.ResponseWriter, resp *http.Response, item bool) {
	status, code, message := engineRefusal(resp, item)
	refusalHeaders(w.Header(), resp.Header, status)
	writeJSONError(w, status, code, message)
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
func (b *Bridge) touchTimeline(ctx context.Context, w http.ResponseWriter, user, key string, item bool) bool {
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
	kind := TranscodeTimeline
	if item {
		kind = TranscodeStream
	}
	if _, err := b.holdTimelineSlot(ctx, user, kind); err != nil {
		writeJSONError(w, http.StatusTooManyRequests, "transcode-limited",
			"the server's transcode session limit is reached; retry when a stream ends")
		return false
	}
	return true
}

// rewritePlaylist copies an m3u8 document from src to dst, pointing
// every URI in it (plain URI lines and URI="..." attributes on tag lines)
// back at this origin under the media token: the engine's own query,
// which names the source file, rides sealed beside the token (seal
// appends it), so the listener reads nothing of it. A line at a time, so
// a playlist of any length goes through whole or not at all, and each
// URI built in one buffer: a long single-file book lists tens of
// thousands of them.
func rewritePlaylist(dst io.Writer, src io.Reader, token string, seal func(dst, query []byte) []byte) error {
	out := bufio.NewWriter(dst)
	sc := bufio.NewScanner(src)
	sc.Buffer(make([]byte, 0, 64*1024), 1<<20)
	mt := "mt=" + url.QueryEscape(token)
	var uri []byte
	// child is one child's URI as the listener gets it: its path, the
	// sealed query as c, and the token.
	child := func(raw []byte) []byte {
		path, query, _ := bytes.Cut(raw, []byte("?"))
		uri = append(uri[:0], path...)
		if len(query) == 0 {
			uri = append(append(uri, '?'), mt...)
			return uri
		}
		uri = seal(append(uri, "?c="...), query)
		uri = append(append(uri, '&'), mt...)
		return uri
	}
	for sc.Scan() {
		line := sc.Bytes()
		switch {
		case len(line) > 0 && line[0] == '#':
			start := bytes.Index(line, []byte(`URI="`))
			end := -1
			if start >= 0 {
				start += len(`URI="`)
				end = bytes.IndexByte(line[start:], '"')
			}
			if end < 0 {
				out.Write(line)
				break
			}
			out.Write(line[:start])
			out.Write(child(line[start : start+end]))
			out.Write(line[start+end:])
		case len(line) == 0:
		default:
			out.Write(child(line))
		}
		if err := out.WriteByte('\n'); err != nil {
			return err
		}
	}
	if err := sc.Err(); err != nil {
		return err
	}
	return out.Flush()
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

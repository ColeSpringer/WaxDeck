// Package castv2 drives Chromecast devices over the CASTV2 protocol:
// a TLS connection to port 8009 carrying length-prefixed protobuf
// CastMessage frames whose payloads are JSON, one dialect per
// namespace. The package provides mDNS discovery, a connect.Driver per
// device, and the wire codec the in-process test receiver shares.
package castv2

import (
	"context"
	"errors"
	"fmt"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// streamTypeBuffered marks a fixed-length timeline. WaxDeck's HLS
// loads (application/vnd.apple.mpegurl) are fixed-length timelines
// too, so they take the same LOAD path with the same stream type.
const streamTypeBuffered = "BUFFERED"

// Device is one discovered or statically configured cast device.
// Speaker groups look exactly like devices and need no special casing.
type Device struct {
	Host string
	Port int
	Name string
	ID   string
}

// Key is the stable registry key: the device id when mDNS supplied
// one, else the address.
func (d Device) Key() string {
	if d.ID != "" {
		return d.ID
	}
	return d.address()
}

// address is the dialable host and port.
func (d Device) address() string {
	return net.JoinHostPort(d.Host, strconv.Itoa(d.portOrDefault()))
}

func (d Device) portOrDefault() int {
	if d.Port != 0 {
		return d.Port
	}
	return castPort
}

// Dial returns the DialFunc the registry stores for this device. The
// session manager calls it when a session starts, so idle devices hold
// no connections; every goroutine the driver needs runs under group.
func (d Device) Dial(group *supervise.Group, log Logger) connect.DialFunc {
	return func(ctx context.Context) (connect.Driver, error) {
		if log == nil {
			log = nopLogger{}
		}
		c, err := dialConn(ctx, group, log, d.Host, d.portOrDefault())
		if err != nil {
			return nil, err
		}
		drv := &driver{
			conn:   c,
			log:    log,
			events: make(chan connect.DriverEvent, 32),
		}
		group.GoOnce(c.runCtx, "castv2-status-"+d.Host, drv.pump)
		return drv, nil
	}
}

// driver drives one cast device for one load at a time. Protocol
// state lives behind mu: the event pump and the verb methods both
// touch it.
type driver struct {
	conn   *conn
	log    Logger
	events chan connect.DriverEvent

	closeOnce sync.Once

	mu          sync.Mutex
	transportID string
	sessionID   string
	// transportSeq is where the launch that cached the transport sits
	// in the connection's arrival order, so a status the device sent
	// before it cannot be read as the app having gone away.
	transportSeq   uint64
	mediaSessionID int
	// loadSeq is where the load that this media state belongs to went
	// out, or where the newest seek's reply came back, so a status the
	// device sent before either cannot be folded in as describing it.
	loadSeq        uint64
	itemIDs        []int
	loaded         bool
	played         bool
	lastIndex      int
	lastPlaying    bool
	lastPositionMS int64

	// load numbers the loads and seeks the device has taken, stamped on
	// every event so the session can drop what describes playback one of
	// them has since moved.
	load uint64
	// replacedSession is the media session the newest load replaced. A
	// status the device sent before it read the LOAD can arrive after
	// the LOAD went out, past loadSeq; it still names that session.
	replacedSession int

	// op numbers the loads and seeks begun. While the newest one's reply
	// is outstanding (holdFor), media statuses are held: only the reply
	// says which of them describe what the device now plays.
	op      uint64
	holdFor uint64
	held    []heldStatus
}

// heldStatus is a media status the pump read while a reply was due, and
// when it read it.
type heldStatus struct {
	u  statusUpdate
	at time.Time
}

// mediaInfoFor maps one item onto the wire shape.
func mediaInfoFor(item connect.MediaItem) mediaInformation {
	md := &mediaMetadata{MetadataType: 3, Title: item.Title, Artist: item.Artist}
	if item.ArtURL != "" {
		md.Images = []mediaImage{{URL: item.ArtURL}}
	}
	return mediaInformation{
		ContentID:   item.URL,
		ContentType: item.MimeType,
		StreamType:  streamTypeBuffered,
		Metadata:    md,
	}
}

// ensureApp makes sure the default media receiver is running and the
// virtual connection to its transport is open. Launching is
// idempotent: an app already running is reused.
func (d *driver) ensureApp(ctx context.Context) (string, error) {
	d.mu.Lock()
	transport := d.transportID
	d.mu.Unlock()
	if transport != "" {
		return transport, nil
	}
	st, seq, err := d.conn.getReceiverStatus(ctx)
	if err != nil {
		return "", err
	}
	app := findApp(st, DefaultMediaReceiverApp)
	if app == nil {
		if st, seq, err = d.conn.launch(ctx, DefaultMediaReceiverApp); err != nil {
			return "", err
		}
		if app = findApp(st, DefaultMediaReceiverApp); app == nil {
			return "", fmt.Errorf("castv2: launch reported no running %s app", DefaultMediaReceiverApp)
		}
	}
	if err := d.conn.connectTransport(app.TransportID); err != nil {
		return "", err
	}
	// seq is the reply that found the app running, not where the
	// connection happens to be now: a status the device broadcast
	// while the transport connect was queued behind the write lock is
	// news, and taking it for one of the answers above would lose it.
	d.mu.Lock()
	d.transportID, d.sessionID = app.TransportID, app.SessionID
	d.transportSeq = seq
	d.mu.Unlock()
	return app.TransportID, nil
}

func findApp(st *receiverStatus, appID string) *receiverApp {
	for i := range st.Applications {
		if st.Applications[i].AppID == appID {
			return &st.Applications[i]
		}
	}
	return nil
}

// Idle reports whether the device is free to be taken over. Loading
// media launches the default media receiver over whatever app is
// running, so anything doing that for a diagnosis rather than for a
// listener asks this first.
//
// Two things count as busy and both have to be asked about separately.
// A foreign application - somebody's film, somebody's music service -
// is named as the device names it. The stock media receiver is not a
// foreign app, because it is the one a WaxDeck load uses too; whether
// it is idle or playing for another sender is a question only its own
// media status answers, so that is asked. The ambient idle screen a
// device runs when nothing is casting is an application in the status
// like any other and is not busy at all.
//
// A status read that fails answers idle. The connection is then
// broken, and a load about to fail with the device's own error says
// more than a refusal invented here.
func (d *driver) Idle(ctx context.Context) (bool, string) {
	st, _, err := d.conn.getReceiverStatus(ctx)
	if err != nil {
		return true, ""
	}
	for _, app := range st.Applications {
		if app.IsIdleScreen {
			continue
		}
		if app.AppID != DefaultMediaReceiverApp {
			name := app.DisplayName
			if name == "" {
				name = app.AppID
			}
			return false, name + " is running on this device"
		}
		if playing, what := d.receiverPlaying(ctx, app); playing {
			return false, what
		}
	}
	return true, ""
}

// receiverPlaying asks a running default media receiver what it is
// doing. A receiver launched and then left alone reports no media
// session at all, which is the idle a device sitting on the cast
// screen is in; anything mid-item belongs to whoever put it there.
func (d *driver) receiverPlaying(ctx context.Context, app receiverApp) (bool, string) {
	if err := d.conn.connectTransport(app.TransportID); err != nil {
		return false, ""
	}
	st, _, err := d.conn.mediaCall(ctx, app.TransportID, func(id int) any {
		return getStatusRequest{Type: "GET_STATUS", RequestID: id}
	})
	if err != nil || st == nil {
		return false, ""
	}
	switch st.PlayerState {
	case statePlaying, stateBuffering, statePaused:
		if title := currentTitle(st); title != "" {
			return true, title + " is playing on this device"
		}
		return true, "this device is already playing something"
	}
	return false, ""
}

// currentTitle names what a receiver has loaded, where its metadata
// says: what is on the screen is what a listener recognises.
func currentTitle(st *mediaStatus) string {
	for _, it := range st.Items {
		if it.ItemID != st.CurrentItemID {
			continue
		}
		if it.Media.Metadata != nil {
			return it.Media.Metadata.Title
		}
	}
	return ""
}

// Load replaces whatever is playing: one item goes over LOAD, more
// over QUEUE_LOAD. QUEUE_LOAD has no autoplay knob, so a paused queue
// load pauses right after the receiver starts.
func (d *driver) Load(ctx context.Context, items []connect.MediaItem, index int, positionMS int64, play bool) error {
	if len(items) == 0 {
		return fmt.Errorf("castv2: load called with no items")
	}
	transport, err := d.ensureApp(ctx)
	if err != nil {
		return err
	}
	// Nothing load-scoped changes until the device has taken the load:
	// a refused one leaves the old media playing, and everything about
	// it must stand. Statuses read meanwhile wait for the reply.
	d.mu.Lock()
	d.op++
	op := d.op
	d.holdFor = op
	sent := d.conn.observed()
	replaced := d.mediaSessionID
	d.mu.Unlock()
	startSeconds := float64(positionMS) / 1000
	var st *mediaStatus
	if len(items) == 1 {
		st, _, err = d.conn.mediaCall(ctx, transport, func(id int) any {
			return loadRequest{
				Type:        "LOAD",
				RequestID:   id,
				Media:       mediaInfoFor(items[0]),
				CurrentTime: startSeconds,
				Autoplay:    play,
			}
		})
	} else {
		qItems := make([]queueLoadItem, len(items))
		for i, item := range items {
			qItems[i] = queueLoadItem{Media: mediaInfoFor(item), Autoplay: true}
		}
		st, _, err = d.conn.mediaCall(ctx, transport, func(id int) any {
			return queueLoadRequest{
				Type:        "QUEUE_LOAD",
				RequestID:   id,
				Items:       qItems,
				StartIndex:  index,
				CurrentTime: startSeconds,
				RepeatMode:  "REPEAT_OFF",
			}
		})
	}
	d.mu.Lock()
	if err != nil {
		// What was held is the media still playing.
		if d.holdFor == op {
			d.releaseLocked()
		}
		d.mu.Unlock()
		return fmt.Errorf("castv2: loading media: %w", err)
	}
	// Everything the connection read before the LOAD went out describes
	// what it replaced, whichever session it named.
	d.load++
	d.loadSeq = max(d.loadSeq, sent)
	d.replacedSession = replaced
	d.loaded = true
	d.played = st != nil && (st.PlayerState == statePlaying || st.PlayerState == stateBuffering)
	d.itemIDs = nil
	d.lastIndex = 0
	if len(items) > 1 {
		d.lastIndex = index
	}
	// What was asked for, until the device says otherwise: a receiver
	// status carries these two forward, and the previous session's
	// playhead is not this one's.
	d.lastPlaying = play
	d.lastPositionMS = positionMS
	if st != nil {
		if st.MediaSessionID != 0 {
			// A device that kept the id across the load leaves it
			// nothing to tell old from new by; arrival order has to do.
			if st.MediaSessionID == replaced {
				d.replacedSession = 0
			}
			d.mediaSessionID = st.MediaSessionID
		}
		for _, it := range st.Items {
			d.itemIDs = append(d.itemIDs, it.ItemID)
		}
	}
	if d.holdFor == op {
		d.releaseLocked()
	}
	d.mu.Unlock()
	if len(items) > 1 && !play {
		return d.Pause(ctx)
	}
	return nil
}

func (d *driver) Play(ctx context.Context) error  { return d.mediaVerb(ctx, "PLAY") }
func (d *driver) Pause(ctx context.Context) error { return d.mediaVerb(ctx, "PAUSE") }
func (d *driver) Stop(ctx context.Context) error  { return d.mediaVerb(ctx, "STOP") }

// mediaVerb issues one media command against the current session.
func (d *driver) mediaVerb(ctx context.Context, verb string) error {
	transport, session, err := d.session()
	if err != nil {
		return err
	}
	_, _, err = d.conn.mediaCall(ctx, transport, func(id int) any {
		return mediaCommandRequest{Type: verb, RequestID: id, MediaSessionID: session}
	})
	if err != nil {
		return fmt.Errorf("castv2: %s: %w", strings.ToLower(verb), err)
	}
	return nil
}

// session returns the transport and media session; media verbs need
// both, so nothing loaded is an error.
func (d *driver) session() (string, int, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.transportID == "" || d.mediaSessionID == 0 {
		return "", 0, fmt.Errorf("castv2: no media session loaded")
	}
	return d.transportID, d.mediaSessionID, nil
}

func (d *driver) SeekTo(ctx context.Context, positionMS int64) error {
	transport, session, err := d.session()
	if err != nil {
		return err
	}
	d.mu.Lock()
	d.op++
	op := d.op
	d.holdFor = op
	d.mu.Unlock()
	_, seq, err := d.conn.mediaCall(ctx, transport, func(id int) any {
		return seekRequest{
			Type:           "SEEK",
			RequestID:      id,
			MediaSessionID: session,
			CurrentTime:    float64(positionMS) / 1000,
			ResumeState:    "PLAYBACK_START",
		}
	})
	d.mu.Lock()
	defer d.mu.Unlock()
	if err == nil {
		// A seek moves playback as a load does. What the device said
		// before its answer is about the playhead it left.
		d.load++
		d.loadSeq = max(d.loadSeq, seq-1)
		d.lastPositionMS = positionMS
	}
	if d.holdFor == op {
		d.releaseLocked()
	}
	if err != nil {
		return fmt.Errorf("castv2: seek: %w", err)
	}
	return nil
}

func (d *driver) SetVolume(ctx context.Context, volume float64) error {
	return d.conn.setVolume(ctx, volume)
}

// SetRate always fails: cast receivers play at fixed rate, and the
// registry registers the endpoint with rate control off.
func (d *driver) SetRate(ctx context.Context, rate float64) error {
	return fmt.Errorf("castv2: cast receivers play at fixed rate")
}

func (d *driver) Events() <-chan connect.DriverEvent { return d.events }

// CurrentLoad is the number of the newest load or seek the device took.
func (d *driver) CurrentLoad() uint64 {
	d.mu.Lock()
	defer d.mu.Unlock()
	return d.load
}

// Close is teardown, not a playback verb: no STOP is sent, the device
// keeps playing what it was told to, and only the channel goes away.
func (d *driver) Close() error {
	d.closeOnce.Do(func() {
		d.mu.Lock()
		transport := d.transportID
		d.mu.Unlock()
		if transport != "" {
			d.conn.sendJSON(transport, NamespaceConnection, tpPayload{Type: "CLOSE"})
		}
		d.conn.Close()
	})
	return nil
}

// pump turns status broadcasts into DriverEvents and keeps positions
// fresh with a periodic GET_STATUS while media is loaded. It ends with
// the connection, emitting a fatal event unless Close was the cause.
func (d *driver) pump(ctx context.Context) error {
	ticker := time.NewTicker(statusPollInterval)
	defer ticker.Stop()
	for {
		select {
		// Both are the connection ending: fail closes dead and then
		// cancels the run context, so a pump busy when it died finds
		// both ready, and select takes either.
		case <-ctx.Done():
			d.reportDeath()
			return nil
		case <-d.conn.dead:
			d.reportDeath()
			return nil
		case u := <-d.conn.statuses:
			d.handleStatus(u)
		case <-ticker.C:
			d.mu.Lock()
			transport, loaded := d.transportID, d.loaded
			d.mu.Unlock()
			if loaded && transport != "" {
				// A write failure kills the connection and surfaces
				// through the dead channel above.
				d.conn.pollMediaStatus(transport)
			}
		}
	}
}

// reportDeath emits the fatal event that ends the session, unless
// Close was the cause.
func (d *driver) reportDeath() {
	if err := d.conn.deathErr(); !errors.Is(err, errConnClosed) {
		d.emit(connect.DriverEvent{At: time.Now(), Fatal: true, Err: err})
	}
}

// handleStatus folds one status into driver state and emits the
// observation. Every status message becomes an event: fields are
// absolute, so duplicates are harmless.
func (d *driver) handleStatus(u statusUpdate) {
	now := time.Now()
	d.mu.Lock()
	defer d.mu.Unlock()
	switch {
	case u.receiver != nil:
		// A vanished app (someone stopped it from the device side)
		// invalidates the cached transport so the next Load relaunches.
		// Only where the device said so after the launch: the status
		// calls that precede one answer with nothing running, and the
		// pump reads those answers whenever it gets to them.
		if d.transportID != "" && u.seq > d.transportSeq && findApp(u.receiver, DefaultMediaReceiverApp) == nil {
			d.transportID, d.sessionID = "", ""
			d.mediaSessionID = 0
			d.loaded = false
		}
		d.emit(connect.DriverEvent{
			At:         now,
			Load:       d.load,
			Playing:    d.lastPlaying,
			Index:      d.lastIndex,
			PositionMS: d.lastPositionMS,
			Volume:     u.receiver.Volume.Level,
		})
	case u.media != nil:
		if u.seq <= d.loadSeq {
			// The previous session, answering a question asked before
			// this load: its session id, queue, and playhead are all
			// the wrong ones to carry forward.
			return
		}
		if d.holdFor != 0 {
			d.held = append(d.held, heldStatus{u: u, at: now})
			return
		}
		d.applyMediaLocked(u.media, now)
	}
}

// releaseLocked ends the hold and folds in, in arrival order, what the
// arrival fence now passes; d.mu held.
func (d *driver) releaseLocked() {
	held := d.held
	d.held, d.holdFor = nil, 0
	for _, h := range held {
		if h.u.seq > d.loadSeq {
			d.applyMediaLocked(h.u.media, h.at)
		}
	}
}

// applyMediaLocked folds one media status into driver state and emits
// the observation; d.mu held.
func (d *driver) applyMediaLocked(ms *mediaStatus, now time.Time) {
	if ms.MediaSessionID != 0 && ms.MediaSessionID == d.replacedSession {
		return
	}
	ev := connect.DriverEvent{At: now, Load: d.load}
	if ms.MediaSessionID != 0 {
		d.mediaSessionID = ms.MediaSessionID
	}
	if len(ms.Items) > 0 {
		d.itemIDs = d.itemIDs[:0]
		for _, it := range ms.Items {
			d.itemIDs = append(d.itemIDs, it.ItemID)
		}
	}
	if ms.CurrentItemID != 0 {
		for i, id := range d.itemIDs {
			if id == ms.CurrentItemID {
				d.lastIndex = i
				break
			}
		}
	}
	playing := ms.PlayerState == statePlaying || ms.PlayerState == stateBuffering
	if playing {
		d.played = true
	}
	d.lastPlaying = playing
	d.lastPositionMS = int64(ms.CurrentTime * 1000)
	ev.Playing = playing
	ev.Index = d.lastIndex
	ev.PositionMS = d.lastPositionMS
	// Finished only after something played: receivers report IDLE
	// before the first load too, and that must not end a session.
	ev.Finished = ms.PlayerState == stateIdle && ms.IdleReason == idleFinished && d.played
	d.emit(ev)
}

// emit delivers without blocking the pump: when the consumer lags, the
// oldest event is dropped for the newer absolute state. The channel is
// never closed, per the Driver contract.
func (d *driver) emit(ev connect.DriverEvent) {
	for {
		select {
		case d.events <- ev:
			return
		default:
		}
		select {
		case <-d.events:
		default:
		}
	}
}

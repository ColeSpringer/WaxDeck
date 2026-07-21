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

	mu             sync.Mutex
	transportID    string
	sessionID      string
	mediaSessionID int
	itemIDs        []int
	loaded         bool
	played         bool
	lastIndex      int
	lastPlaying    bool
	lastPositionMS int64
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
	st, err := d.conn.getReceiverStatus(ctx)
	if err != nil {
		return "", err
	}
	app := findApp(st, DefaultMediaReceiverApp)
	if app == nil {
		if st, err = d.conn.launch(ctx, DefaultMediaReceiverApp); err != nil {
			return "", err
		}
		if app = findApp(st, DefaultMediaReceiverApp); app == nil {
			return "", fmt.Errorf("castv2: launch reported no running %s app", DefaultMediaReceiverApp)
		}
	}
	if err := d.conn.connectTransport(app.TransportID); err != nil {
		return "", err
	}
	d.mu.Lock()
	d.transportID, d.sessionID = app.TransportID, app.SessionID
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
	// Load-scoped state resets before the request goes out: the
	// reply's statuses race the reply itself through the pump, and a
	// PLAYING observed there must count for this load.
	d.mu.Lock()
	d.loaded = true
	d.played = false
	d.itemIDs = nil
	d.lastIndex = 0
	if len(items) > 1 {
		d.lastIndex = index
	}
	d.mu.Unlock()
	startSeconds := float64(positionMS) / 1000
	var st *mediaStatus
	if len(items) == 1 {
		st, err = d.conn.mediaCall(ctx, transport, func(id int) any {
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
		st, err = d.conn.mediaCall(ctx, transport, func(id int) any {
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
	if err != nil {
		return fmt.Errorf("castv2: loading media: %w", err)
	}
	if st != nil {
		d.mu.Lock()
		if st.MediaSessionID != 0 {
			d.mediaSessionID = st.MediaSessionID
		}
		if len(st.Items) > 0 {
			d.itemIDs = d.itemIDs[:0]
			for _, it := range st.Items {
				d.itemIDs = append(d.itemIDs, it.ItemID)
			}
		}
		d.mu.Unlock()
	}
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
	_, err = d.conn.mediaCall(ctx, transport, func(id int) any {
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
	_, err = d.conn.mediaCall(ctx, transport, func(id int) any {
		return seekRequest{
			Type:           "SEEK",
			RequestID:      id,
			MediaSessionID: session,
			CurrentTime:    float64(positionMS) / 1000,
			ResumeState:    "PLAYBACK_START",
		}
	})
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
		case <-ctx.Done():
			return nil
		case <-d.conn.dead:
			if err := d.conn.deathErr(); !errors.Is(err, errConnClosed) {
				d.emit(connect.DriverEvent{At: time.Now(), Fatal: true, Err: err})
			}
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

// handleStatus folds one status into driver state and emits the
// observation. Every status message becomes an event: fields are
// absolute, so duplicates are harmless.
func (d *driver) handleStatus(u statusUpdate) {
	now := time.Now()
	d.mu.Lock()
	defer d.mu.Unlock()
	ev := connect.DriverEvent{At: now}
	switch {
	case u.receiver != nil:
		// A vanished app (someone stopped it from the device side)
		// invalidates the cached transport so the next Load relaunches.
		if d.transportID != "" && findApp(u.receiver, DefaultMediaReceiverApp) == nil {
			d.transportID, d.sessionID = "", ""
			d.mediaSessionID = 0
			d.loaded = false
		}
		ev.Playing = d.lastPlaying
		ev.Index = d.lastIndex
		ev.PositionMS = d.lastPositionMS
		ev.Volume = u.receiver.Volume.Level
	case u.media != nil:
		ms := u.media
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
	default:
		return
	}
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

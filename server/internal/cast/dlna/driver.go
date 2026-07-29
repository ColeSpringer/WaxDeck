package dlna

import (
	"context"
	"fmt"
	"math"
	"slices"
	"sync"
	"time"

	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// Device identifies one discovered renderer well enough to dial it.
type Device struct {
	Location string
	UDN      string
	Name     string
}

const (
	// defaultPollInterval is the transport poll cadence. One second
	// matches what renderer remotes do; anything faster only warms the
	// renderer's HTTP stack.
	defaultPollInterval = time.Second
	// volumeEvery spaces GetVolume calls out to every fifth poll:
	// volume moves rarely and RenderingControl is a separate request.
	volumeEvery = 5
	// maxPollFailures is how many consecutive failed polls mean the
	// renderer is gone rather than busy.
	maxPollFailures = 5
	// eventBuffer bounds the events channel. Observations are
	// absolute, so a lagging consumer loses nothing it cannot
	// reconstruct from the next tick.
	eventBuffer = 16
)

// Dial returns a DialFunc for the device. The description is fetched
// per dial, not cached from discovery, so a renderer that rebooted onto
// new control URLs still connects.
func (dev Device) Dial(group *supervise.Group, log Logger) connect.DialFunc {
	if log == nil {
		log = nopLogger{}
	}
	return func(ctx context.Context) (connect.Driver, error) {
		desc, err := fetchDescription(ctx, dev.Location)
		if err != nil {
			return nil, err
		}
		if desc.AVTransport == "" {
			return nil, fmt.Errorf("dlna: device at %s exposes no avtransport service", dev.Location)
		}
		udn := dev.UDN
		if udn == "" {
			udn = desc.UDN
		}
		if udn == "" {
			udn = dev.Location
		}
		cl := newClient(desc)
		// Ask what the renderer plays, once, here. It is a fixed property
		// of the device, so asking per load would spend a SOAP round trip
		// to learn the same answer; and a renderer that cannot answer is
		// not a renderer that cannot play, so a failure narrows nothing
		// and the caller falls back to the mp3 floor.
		var accepts []string
		if desc.ConnectionManager != "" {
			mimes, err := cl.protocolInfo(ctx)
			if err != nil {
				log.Warn("dlna: renderer did not report its protocol info; using the format floor",
					"udn", udn, "err", err)
			} else {
				accepts = make([]string, 0, len(mimes))
				for mime := range mimes {
					accepts = append(accepts, mime)
				}
				slices.Sort(accepts)
			}
		}
		return &driver{
			cl:           cl,
			group:        group,
			log:          log,
			udn:          udn,
			accepts:      accepts,
			pollInterval: defaultPollInterval,
			events:       make(chan connect.DriverEvent, eventBuffer),
			lastVolume:   -1,
		}, nil
	}
}

// driver drives one renderer for one load at a time. The renderer
// offers no eventing worth trusting, so a poll worker started per load
// observes transport state and synthesizes DriverEvents, including the
// track-to-track advance the renderer will not do on its own.
type driver struct {
	cl    *client
	group *supervise.Group
	log   Logger
	udn   string
	// accepts is the renderer's Sink media types, read once at dial and
	// immutable after. Empty means it declared nothing usable.
	accepts      []string
	pollInterval time.Duration

	events chan connect.DriverEvent

	mu         sync.Mutex
	items      []connect.MediaItem
	index      int
	played     bool
	finished   bool
	lastVolume int
	closed     bool
	cancelPoll context.CancelFunc
	pollDone   chan struct{}
}

// Load replaces the renderer's queue with items starting at index. The
// item's mime type is used as given: the caller already applied the
// transcode floor policy, so by here every URL is device-playable.
// When play is false only the URI is set; Play and Seek are skipped
// because most renderers refuse Seek while stopped, so a nonzero
// positionMS without play is dropped rather than half-applied.
func (d *driver) Load(ctx context.Context, items []connect.MediaItem, index int, positionMS int64, play bool) error {
	if index < 0 || index >= len(items) {
		return fmt.Errorf("dlna: load index %d out of range for %d items", index, len(items))
	}
	d.stopPoll()
	d.mu.Lock()
	if d.closed {
		d.mu.Unlock()
		return fmt.Errorf("dlna: driver is closed")
	}
	d.items = slices.Clone(items)
	d.index = index
	d.played = false
	d.finished = false
	d.mu.Unlock()

	item := items[index]
	if err := d.cl.setURI(ctx, item.URL, didlLite(item)); err != nil {
		return err
	}
	if play {
		if err := d.cl.play(ctx); err != nil {
			return err
		}
		if positionMS > 0 {
			if err := d.cl.seek(ctx, positionMS); err != nil {
				d.log.Warn("dlna: resume seek refused", "udn", d.udn, "err", err)
			}
		}
	}
	d.setNext(ctx, items, index)
	d.startPoll()
	return nil
}

// setNext arms the renderer's gapless slot with the item after index.
// Best effort by design: SetNextAVTransportURI is optional in the wild
// and a 718 or 602 refusal only means the poll loop does the advance.
func (d *driver) setNext(ctx context.Context, items []connect.MediaItem, index int) {
	if index+1 >= len(items) {
		return
	}
	next := items[index+1]
	if err := d.cl.setNextURI(ctx, next.URL, didlLite(next)); err != nil {
		d.log.Warn("dlna: renderer refused next uri", "udn", d.udn, "err", err)
	}
}

func (d *driver) Play(ctx context.Context) error  { return d.cl.play(ctx) }
func (d *driver) Pause(ctx context.Context) error { return d.cl.pause(ctx) }
func (d *driver) Stop(ctx context.Context) error  { return d.cl.stop(ctx) }

func (d *driver) SeekTo(ctx context.Context, positionMS int64) error {
	return d.cl.seek(ctx, positionMS)
}

func (d *driver) SetVolume(ctx context.Context, volume float64) error {
	v := int(math.Round(volume * 100))
	v = max(0, min(100, v))
	return d.cl.setVolume(ctx, v)
}

func (d *driver) SetRate(context.Context, float64) error {
	return fmt.Errorf("dlna: renderers play at fixed rate")
}

func (d *driver) Events() <-chan connect.DriverEvent { return d.events }

// AcceptedFormats reports the renderer's Sink media types, so the
// resolver can serve something better than the mp3 floor when the
// renderer and the engine agree on one. Fixed at dial; never nil-checked
// by the caller, which reads an empty result as "no constraint".
func (d *driver) AcceptedFormats() []string { return d.accepts }

// Close stops the poll worker and closes the events channel. The
// renderer is left as it is: closing a driver ends the session's view
// of the device, not whatever the device is doing.
func (d *driver) Close() error {
	d.stopPoll()
	d.mu.Lock()
	if d.closed {
		d.mu.Unlock()
		return nil
	}
	d.closed = true
	d.mu.Unlock()
	close(d.events)
	return nil
}

// startPoll spawns the poll worker for the current load under its own
// context, detached from the Load request's.
func (d *driver) startPoll() {
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	d.mu.Lock()
	d.cancelPoll = cancel
	d.pollDone = done
	d.mu.Unlock()
	d.group.GoOnce(ctx, "dlna-poll-"+d.udn, func(ctx context.Context) error {
		defer close(done)
		d.poll(ctx)
		return nil
	})
}

// stopPoll cancels the running poll worker and waits it out, so the
// caller can mutate driver state or close the events channel without
// racing an emit.
func (d *driver) stopPoll() {
	d.mu.Lock()
	cancel, done := d.cancelPoll, d.pollDone
	d.cancelPoll, d.pollDone = nil, nil
	d.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	if done != nil {
		<-done
	}
}

// poll observes the renderer once per interval until canceled. Five
// consecutive failures mean the device is gone: emit Fatal and end.
func (d *driver) poll(ctx context.Context) {
	ticker := time.NewTicker(d.pollInterval)
	defer ticker.Stop()
	failures := 0
	for tick := 0; ; tick++ {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
		ev, err := d.observe(ctx, tick)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			failures++
			if failures >= maxPollFailures {
				d.log.Warn("dlna: renderer unreachable, ending driver", "udn", d.udn, "err", err)
				d.emit(connect.DriverEvent{At: time.Now(), Fatal: true, Err: err})
				return
			}
			continue
		}
		failures = 0
		d.emit(ev)
	}
}

// observe reads transport and position state and runs the advance
// machine: renderers stop at the end of a URI, so moving through the
// item list is this driver's job unless the renderer honored the next
// slot itself.
func (d *driver) observe(ctx context.Context, tick int) (connect.DriverEvent, error) {
	state, err := d.cl.transportState(ctx)
	if err != nil {
		return connect.DriverEvent{}, err
	}
	pos, err := d.cl.positionInfo(ctx)
	if err != nil {
		return connect.DriverEvent{}, err
	}

	d.mu.Lock()
	items := d.items
	index := d.index
	played := d.played
	finished := d.finished
	d.mu.Unlock()

	playing := state == statePlaying || state == stateTransitioning
	if playing {
		played = true
	}
	ended := state == stateStopped || state == stateNoMedia
	positionMS := pos.RelMS
	justFinished := false

	switch {
	case playing && index+1 < len(items) && pos.TrackURI != "" && pos.TrackURI == items[index+1].URL:
		// The renderer promoted the next slot itself (gapless): the
		// playing URI moved on without a STOPPED gap. Follow it and
		// re-arm the slot.
		index++
		d.setNext(ctx, items, index)
	case ended && played && !finished:
		if index+1 < len(items) {
			// Renderer-driven advance: load and start the next item
			// ourselves. A failure here counts as a poll failure so a
			// dead device still trips Fatal.
			index++
			item := items[index]
			if err := d.cl.setURI(ctx, item.URL, didlLite(item)); err != nil {
				return connect.DriverEvent{}, err
			}
			if err := d.cl.play(ctx); err != nil {
				return connect.DriverEvent{}, err
			}
			d.setNext(ctx, items, index)
			playing = true
			positionMS = 0
		} else {
			finished = true
			justFinished = true
		}
	}

	ev := connect.DriverEvent{
		At:         time.Now(),
		Playing:    playing,
		Index:      index,
		PositionMS: positionMS,
		Finished:   justFinished,
	}

	if tick%volumeEvery == 0 {
		vol, err := d.cl.volume(ctx)
		if err != nil {
			return connect.DriverEvent{}, err
		}
		d.mu.Lock()
		if vol != d.lastVolume {
			d.lastVolume = vol
			f := float64(vol) / 100
			ev.Volume = &f
		}
		d.mu.Unlock()
	}

	d.mu.Lock()
	d.index = index
	d.played = played
	d.finished = finished
	d.mu.Unlock()
	return ev, nil
}

// emit delivers without blocking the poll: observations are absolute,
// so when the consumer lags, the oldest buffered event is dropped for
// the newest.
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

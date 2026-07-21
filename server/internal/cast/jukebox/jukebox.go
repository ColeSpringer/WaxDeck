// Package jukebox plays queues out of the server's own audio device:
// the endpoint for the box wired to the living-room amplifier. Audio
// arrives as WAV from the streaming engine over the loopback base and
// pipes into a player subprocess (aplay by default, pw-cat where
// PipeWire owns the device), keeping the server CGO-free where a
// native audio stack would not be. Volume is applied in-process by
// scaling PCM samples, since the pipe players expose none.
package jukebox

import (
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"net/http"
	"os/exec"
	"strings"
	"sync"
	"time"

	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// Logger is the slice of logging the package needs.
type Logger interface {
	Info(msg string, args ...any)
	Warn(msg string, args ...any)
}

// Config configures the jukebox output.
type Config struct {
	// Command is the player invocation; the WAV stream feeds stdin.
	// The default plays through ALSA.
	Command []string
	// Name labels the endpoint in pickers.
	Name string
	Log  Logger
}

// DefaultCommand pipes WAV to ALSA. PipeWire hosts use
// ["pw-cat", "-p", "-"].
var DefaultCommand = []string{"aplay", "-q", "-t", "wav", "-"}

// Dial returns the DialFunc the registry hands the session manager.
func Dial(cfg Config, group *supervise.Group) connect.DialFunc {
	if len(cfg.Command) == 0 {
		cfg.Command = DefaultCommand
	}
	return func(ctx context.Context) (connect.Driver, error) {
		if _, err := exec.LookPath(cfg.Command[0]); err != nil {
			return nil, fmt.Errorf("jukebox: player command %q not found", cfg.Command[0])
		}
		d := &driver{
			cfg:    cfg,
			group:  group,
			events: make(chan connect.DriverEvent, 16),
			volume: 1,
		}
		return d, nil
	}
}

// driver plays one load at a time: a supervised loop fetches each
// item's WAV and feeds the player, advancing through the queue.
type driver struct {
	cfg    Config
	group  *supervise.Group
	events chan connect.DriverEvent

	mu      sync.Mutex
	items   []connect.MediaItem
	index   int
	playing bool
	paused  bool
	volume  float64
	posMS   int64
	gen     int
	cancel  context.CancelFunc
	closed  bool
}

func (d *driver) Load(ctx context.Context, items []connect.MediaItem, index int, positionMS int64, play bool) error {
	if len(items) == 0 {
		return fmt.Errorf("jukebox: empty load")
	}
	d.mu.Lock()
	if d.cancel != nil {
		d.cancel()
	}
	d.items = items
	d.index = index
	d.posMS = positionMS
	d.playing = play
	d.paused = !play
	d.gen++
	gen := d.gen
	runCtx, cancel := context.WithCancel(context.Background())
	d.cancel = cancel
	d.mu.Unlock()
	if play {
		d.group.GoOnce(runCtx, fmt.Sprintf("jukebox-play-%d", gen), func(c context.Context) error {
			d.playLoop(c, gen)
			return nil
		})
	}
	return nil
}

// playLoop walks the queue from the current index, one item per
// player process.
func (d *driver) playLoop(ctx context.Context, gen int) {
	for {
		d.mu.Lock()
		if d.gen != gen || d.closed || d.index >= len(d.items) {
			finished := d.gen == gen && d.index >= len(d.items)
			d.playing = false
			d.mu.Unlock()
			if finished {
				d.emit(connect.DriverEvent{At: time.Now(), Playing: false, Index: len(d.items) - 1, Finished: true})
			}
			return
		}
		item := d.items[d.index]
		startMS := d.posMS
		index := d.index
		d.mu.Unlock()

		err := d.playOne(ctx, item, startMS, index)
		if ctx.Err() != nil {
			return
		}
		if err != nil {
			d.cfg.Log.Warn("jukebox item failed", "pid", item.PID, "err", err)
			d.emit(connect.DriverEvent{At: time.Now(), Playing: false, Index: index, Fatal: true, Err: err})
			return
		}
		d.mu.Lock()
		if d.gen != gen {
			d.mu.Unlock()
			return
		}
		d.index++
		d.posMS = 0
		d.mu.Unlock()
		d.emit(connect.DriverEvent{At: time.Now(), Playing: true, Index: d.index, PositionMS: 0})
	}
}

// playOne streams one item into one player process, scaling volume
// and reporting position from consumed bytes.
func (d *driver) playOne(ctx context.Context, item connect.MediaItem, startMS int64, index int) error {
	u := item.URL
	if startMS > 0 {
		sep := "?"
		if strings.Contains(u, "?") {
			sep = "&"
		}
		u += sep + "t=" + fmt.Sprintf("%.3f", float64(startMS)/1000)
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return fmt.Errorf("jukebox: %w", err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("jukebox: fetching audio: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusPartialContent {
		return fmt.Errorf("jukebox: audio fetch answered %d", resp.StatusCode)
	}

	cmd := exec.CommandContext(ctx, d.cfg.Command[0], d.cfg.Command[1:]...)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("jukebox: %w", err)
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("jukebox: starting %s: %w", d.cfg.Command[0], err)
	}

	err = d.pump(ctx, resp.Body, stdin, startMS, index)
	stdin.Close()
	waitErr := cmd.Wait()
	if err != nil {
		return err
	}
	if waitErr != nil && ctx.Err() == nil {
		return fmt.Errorf("jukebox: player: %w", waitErr)
	}
	return nil
}

// pump copies WAV from src to the player, scaling 16-bit samples by
// the current volume, honoring pause, and emitting position events.
func (d *driver) pump(ctx context.Context, src io.Reader, dst io.Writer, startMS int64, index int) error {
	header, byteRate, bits, err := readWAVHeader(src)
	if err != nil {
		return err
	}
	if _, err := dst.Write(header); err != nil {
		return fmt.Errorf("jukebox: writing header: %w", err)
	}

	buf := make([]byte, 32*1024)
	var consumed int64
	lastEvent := time.Time{}
	for {
		if ctx.Err() != nil {
			return nil
		}
		d.mu.Lock()
		paused := d.paused
		vol := d.volume
		d.mu.Unlock()
		if paused {
			select {
			case <-ctx.Done():
				return nil
			case <-time.After(100 * time.Millisecond):
			}
			continue
		}
		n, readErr := src.Read(buf)
		if n > 0 {
			chunk := buf[:n]
			if vol < 0.999 && bits == 16 {
				scalePCM16(chunk, vol)
			}
			if _, err := dst.Write(chunk); err != nil {
				return fmt.Errorf("jukebox: writing audio: %w", err)
			}
			consumed += int64(n)
			if byteRate > 0 {
				pos := startMS + consumed*1000/int64(byteRate)
				d.mu.Lock()
				d.posMS = pos
				d.playing = true
				d.mu.Unlock()
				if time.Since(lastEvent) >= time.Second {
					lastEvent = time.Now()
					d.emit(connect.DriverEvent{At: time.Now(), Playing: true, Index: index, PositionMS: pos})
				}
			}
		}
		if readErr == io.EOF {
			return nil
		}
		if readErr != nil {
			return fmt.Errorf("jukebox: reading audio: %w", readErr)
		}
	}
}

// maxHeaderChunk bounds any single pre-data chunk. Real WAV headers
// are a few hundred bytes; a corrupt size field must not become an
// allocation.
const maxHeaderChunk = 1 << 20

// readWAVHeader consumes RIFF chunks up to the data chunk and returns
// the raw header bytes, the byte rate, and the sample bit width.
func readWAVHeader(r io.Reader) (header []byte, byteRate uint32, bits uint16, err error) {
	head := make([]byte, 12)
	if _, err := io.ReadFull(r, head); err != nil {
		return nil, 0, 0, fmt.Errorf("jukebox: reading wav preamble: %w", err)
	}
	if string(head[0:4]) != "RIFF" || string(head[8:12]) != "WAVE" {
		return nil, 0, 0, fmt.Errorf("jukebox: the stream is not wav")
	}
	out := append([]byte(nil), head...)
	for {
		ch := make([]byte, 8)
		if _, err := io.ReadFull(r, ch); err != nil {
			return nil, 0, 0, fmt.Errorf("jukebox: reading wav chunk: %w", err)
		}
		out = append(out, ch...)
		id := string(ch[0:4])
		size := binary.LittleEndian.Uint32(ch[4:8])
		if id == "data" {
			return out, byteRate, bits, nil
		}
		if size > maxHeaderChunk {
			return nil, 0, 0, fmt.Errorf("jukebox: wav %s chunk of %d bytes is not a header", id, size)
		}
		body := make([]byte, size)
		if _, err := io.ReadFull(r, body); err != nil {
			return nil, 0, 0, fmt.Errorf("jukebox: reading wav %s chunk: %w", id, err)
		}
		out = append(out, body...)
		if id == "fmt " && size >= 16 {
			byteRate = binary.LittleEndian.Uint32(body[8:12])
			bits = binary.LittleEndian.Uint16(body[14:16])
		}
	}
}

// scalePCM16 scales little-endian 16-bit samples in place.
func scalePCM16(b []byte, vol float64) {
	for i := 0; i+1 < len(b); i += 2 {
		s := int16(binary.LittleEndian.Uint16(b[i : i+2]))
		scaled := float64(s) * vol
		if scaled > 32767 {
			scaled = 32767
		}
		if scaled < -32768 {
			scaled = -32768
		}
		binary.LittleEndian.PutUint16(b[i:i+2], uint16(int16(scaled)))
	}
}

func (d *driver) emit(ev connect.DriverEvent) {
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.closed {
		return
	}
	select {
	case d.events <- ev:
	default:
	}
}

func (d *driver) Play(ctx context.Context) error {
	d.mu.Lock()
	wasPaused := d.paused
	d.paused = false
	playing := d.playing
	items := d.items
	index := d.index
	posMS := d.posMS
	gen := d.gen
	d.mu.Unlock()
	if !playing && !wasPaused && len(items) > 0 && index < len(items) {
		// Loaded without autoplay: start the loop now.
		return d.Load(ctx, items, index, posMS, true)
	}
	_ = gen
	d.emit(connect.DriverEvent{At: time.Now(), Playing: true, Index: index, PositionMS: posMS})
	return nil
}

func (d *driver) Pause(context.Context) error {
	d.mu.Lock()
	d.paused = true
	index, pos := d.index, d.posMS
	d.mu.Unlock()
	d.emit(connect.DriverEvent{At: time.Now(), Playing: false, Index: index, PositionMS: pos})
	return nil
}

func (d *driver) Stop(context.Context) error {
	d.mu.Lock()
	if d.cancel != nil {
		d.cancel()
	}
	d.playing = false
	d.paused = false
	index, pos := d.index, d.posMS
	d.mu.Unlock()
	d.emit(connect.DriverEvent{At: time.Now(), Playing: false, Index: index, PositionMS: pos})
	return nil
}

func (d *driver) SeekTo(ctx context.Context, positionMS int64) error {
	d.mu.Lock()
	items, index := d.items, d.index
	playing := !d.paused && d.playing
	d.mu.Unlock()
	if len(items) == 0 {
		return fmt.Errorf("jukebox: nothing loaded")
	}
	// A seek restarts the fetch at the target offset; the stream
	// engine's time parameter does the cutting.
	return d.Load(ctx, items, index, positionMS, playing)
}

func (d *driver) SetVolume(_ context.Context, volume float64) error {
	d.mu.Lock()
	d.volume = volume
	v := volume
	index, pos, playing := d.index, d.posMS, d.playing && !d.paused
	d.mu.Unlock()
	d.emit(connect.DriverEvent{At: time.Now(), Playing: playing, Index: index, PositionMS: pos, Volume: &v})
	return nil
}

func (d *driver) SetRate(context.Context, float64) error {
	return fmt.Errorf("jukebox: rate control is not supported")
}

func (d *driver) Events() <-chan connect.DriverEvent { return d.events }

func (d *driver) Close() error {
	d.mu.Lock()
	if d.closed {
		d.mu.Unlock()
		return nil
	}
	d.closed = true
	if d.cancel != nil {
		d.cancel()
	}
	// Emits are refused once closed (same lock), so closing here can
	// never race a send; consumers unblock like the other drivers.
	close(d.events)
	d.mu.Unlock()
	return nil
}

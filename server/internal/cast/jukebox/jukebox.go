// Package jukebox plays queues out of the server's own audio device:
// the endpoint for the box wired to the living-room amplifier. Audio
// arrives as WAV from the streaming engine over the loopback base and
// pipes into a player subprocess (aplay by default, pw-cat where
// PipeWire owns the device), keeping the server CGO-free where a
// native audio stack would not be. Volume is applied in-process by
// scaling PCM samples, since the pipe players expose none.
package jukebox

import (
	"bytes"
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
	// looping says a play loop runs for the current load. A load made
	// while paused (a seek, a transfer, a reload) starts none, so the play
	// after it has one to start rather than only a pause to lift.
	looping bool
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
	d.looping = play
	d.gen++
	gen := d.gen
	runCtx, cancel := context.WithCancel(context.Background())
	d.cancel = cancel
	d.mu.Unlock()
	if play && !d.group.GoOnce(runCtx, fmt.Sprintf("jukebox-play-%d", gen), func(c context.Context) error {
		d.playLoop(c, gen)
		return nil
	}) {
		d.mu.Lock()
		if d.gen == gen {
			d.looping = false
		}
		d.mu.Unlock()
	}
	return nil
}

// playLoop walks the queue from the current index, one item per
// player process.
func (d *driver) playLoop(ctx context.Context, gen int) {
	defer func() {
		d.mu.Lock()
		if d.gen == gen {
			d.looping = false
		}
		d.mu.Unlock()
	}()
	for {
		d.mu.Lock()
		if d.gen != gen || d.closed || d.index >= len(d.items) {
			finished := d.gen == gen && d.index >= len(d.items)
			last := len(d.items) - 1
			// Where the load actually ran out, which is the end of the
			// last item. A zero here would be read as the start of it,
			// and for one entry rendered as several - a multi-file
			// audiobook - that is a listener sent back a chapter.
			endMS := int64(0)
			if finished && last >= 0 {
				endMS = d.items[last].DurationMS
			}
			d.playing = false
			d.mu.Unlock()
			if finished {
				d.emit(connect.DriverEvent{At: time.Now(), Playing: false, Index: last, PositionMS: endMS, Finished: true})
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
		next, loaded := d.index, len(d.items)
		d.mu.Unlock()
		// Only where there is a next item: past the end the index names
		// nothing loaded, and the loop's own finished event above is
		// what says the queue ran out.
		if next < loaded {
			d.emit(connect.DriverEvent{At: time.Now(), Playing: true, Index: next, PositionMS: 0})
		}
	}
}

// playOne streams one item into one player process, scaling volume
// and reporting position from consumed bytes.
func (d *driver) playOne(ctx context.Context, item connect.MediaItem, startMS int64, index int) error {
	body, err := openAudio(ctx, item.URL, startMS)
	if err != nil {
		return err
	}
	defer body.Close()

	cmd := exec.CommandContext(ctx, d.cfg.Command[0], d.cfg.Command[1:]...)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		return fmt.Errorf("jukebox: %w", err)
	}
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("jukebox: starting %s: %w", d.cfg.Command[0], err)
	}

	err = d.pump(ctx, body, stdin, startMS, index)
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

// openAudio fetches an item's WAV from startMS. The engine cuts a stream
// it renders (t=). An original served as it is, a WAV file that needs no
// engine, is refused a cut, and it is byte-addressable anyway, so that
// start is a range request past its header.
func openAudio(ctx context.Context, u string, startMS int64) (io.ReadCloser, error) {
	if startMS > 0 {
		sep := "?"
		if strings.Contains(u, "?") {
			sep = "&"
		}
		resp, err := getAudio(ctx, u+sep+"t="+fmt.Sprintf("%.3f", float64(startMS)/1000), "")
		if err != nil {
			return nil, err
		}
		if resp.StatusCode != http.StatusBadRequest {
			return audioBody(resp)
		}
		resp.Body.Close()
	}
	resp, err := getAudio(ctx, u, "")
	if err != nil {
		return nil, err
	}
	body, err := audioBody(resp)
	if err != nil || startMS == 0 {
		return body, err
	}
	return seekInto(ctx, u, body, startMS)
}

// seekInto positions a whole WAV at startMS: the header off the head of
// the file, then its frames from that point on, fetched by range so the
// audio before the start is never read.
func seekInto(ctx context.Context, u string, head io.ReadCloser, startMS int64) (io.ReadCloser, error) {
	header, f, err := readWAVHeader(head)
	head.Close()
	if err != nil {
		return nil, err
	}
	resp, err := getAudio(ctx, u, fmt.Sprintf("bytes=%d-", int64(len(header))+frameOffset(f, startMS)))
	if err != nil {
		return nil, err
	}
	switch resp.StatusCode {
	case http.StatusPartialContent:
		return withHeader(header, resp.Body), nil
	case http.StatusRequestedRangeNotSatisfiable:
		// A start past the end leaves nothing to play, which the pump
		// reads as the item ending.
		resp.Body.Close()
		return withHeader(header, http.NoBody), nil
	}
	// A server that ignored the range sent the whole file again.
	body, err := audioBody(resp)
	if err != nil {
		return nil, err
	}
	return skipInto(body, header, f, startMS)
}

// skipInto positions a whole WAV, whose header and format are in hand, at
// startMS by reading past the header and the audio before it.
func skipInto(body io.ReadCloser, header []byte, f wavFormat, startMS int64) (io.ReadCloser, error) {
	// Past the end there is nothing left to play, as above.
	if _, err := io.CopyN(io.Discard, body, int64(len(header))+frameOffset(f, startMS)); err != nil && err != io.EOF {
		body.Close()
		return nil, fmt.Errorf("jukebox: reading to %d ms: %w", startMS, err)
	}
	return withHeader(header, body), nil
}

// frameOffset is where startMS falls in a WAV's data, on a frame boundary.
func frameOffset(f wavFormat, startMS int64) int64 {
	off := startMS * int64(f.byteRate) / 1000
	if f.blockAlign > 0 {
		off -= off % int64(f.blockAlign)
	}
	return off
}

// withHeader replays a WAV's header ahead of frames read from body.
func withHeader(header []byte, body io.ReadCloser) io.ReadCloser {
	return struct {
		io.Reader
		io.Closer
	}{io.MultiReader(bytes.NewReader(header), body), body}
}

// getAudio issues one audio fetch, of a byte range when rng is set.
func getAudio(ctx context.Context, u, rng string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, fmt.Errorf("jukebox: %w", err)
	}
	if rng != "" {
		req.Header.Set("Range", rng)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("jukebox: fetching audio: %w", err)
	}
	return resp, nil
}

// audioBody answers a fetch's audio, or why it carries none.
func audioBody(resp *http.Response) (io.ReadCloser, error) {
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusPartialContent {
		resp.Body.Close()
		return nil, fmt.Errorf("jukebox: audio fetch answered %d", resp.StatusCode)
	}
	return resp.Body, nil
}

// pump copies WAV from src to the player, scaling 16-bit samples by
// the current volume, honoring pause, and emitting position events.
func (d *driver) pump(ctx context.Context, src io.Reader, dst io.Writer, startMS int64, index int) error {
	header, f, err := readWAVHeader(src)
	if err != nil {
		return err
	}
	byteRate, bits := f.byteRate, f.bits
	if _, err := dst.Write(header); err != nil {
		return fmt.Errorf("jukebox: writing header: %w", err)
	}

	buf := make([]byte, 32*1024)
	// held is a trailing odd byte kept back, at the head of buf, for the
	// read that completes its sample: a body arrives in reads of any
	// length, and scaling a run that starts mid-sample scales every sample
	// after it across its neighbour's bytes.
	held := 0
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
		n, readErr := src.Read(buf[held:])
		chunk := buf[:held+n]
		// Whole samples go; a byte over waits for its pair, unless the
		// stream ended, when it goes as it is.
		whole := len(chunk) &^ 1
		if readErr != nil {
			whole = len(chunk)
		}
		if whole > 0 {
			if vol < 0.999 && bits == 16 {
				scalePCM16(chunk[:whole], vol)
			}
			if _, err := dst.Write(chunk[:whole]); err != nil {
				return fmt.Errorf("jukebox: writing audio: %w", err)
			}
		}
		held = copy(buf, chunk[whole:])
		if n > 0 {
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

// wavFormat is what the jukebox reads off a WAV's fmt chunk.
type wavFormat struct {
	byteRate   uint32
	blockAlign uint16
	bits       uint16
}

// readWAVHeader consumes RIFF chunks up to the data chunk and returns
// the raw header bytes and the format they declare.
func readWAVHeader(r io.Reader) (header []byte, f wavFormat, err error) {
	head := make([]byte, 12)
	if _, err := io.ReadFull(r, head); err != nil {
		return nil, wavFormat{}, fmt.Errorf("jukebox: reading wav preamble: %w", err)
	}
	if string(head[0:4]) != "RIFF" || string(head[8:12]) != "WAVE" {
		return nil, wavFormat{}, fmt.Errorf("jukebox: the stream is not wav")
	}
	out := append([]byte(nil), head...)
	for {
		ch := make([]byte, 8)
		if _, err := io.ReadFull(r, ch); err != nil {
			return nil, wavFormat{}, fmt.Errorf("jukebox: reading wav chunk: %w", err)
		}
		out = append(out, ch...)
		id := string(ch[0:4])
		size := binary.LittleEndian.Uint32(ch[4:8])
		if id == "data" {
			return out, f, nil
		}
		if size > maxHeaderChunk {
			return nil, wavFormat{}, fmt.Errorf("jukebox: wav %s chunk of %d bytes is not a header", id, size)
		}
		// An odd-sized chunk is followed by a pad byte its size does not
		// count. It stays in the header, whose length is where the frames
		// begin.
		body := make([]byte, size+size%2)
		if _, err := io.ReadFull(r, body); err != nil {
			return nil, wavFormat{}, fmt.Errorf("jukebox: reading wav %s chunk: %w", id, err)
		}
		out = append(out, body...)
		if id == "fmt " && size >= 16 {
			f.byteRate = binary.LittleEndian.Uint32(body[8:12])
			f.blockAlign = binary.LittleEndian.Uint16(body[12:14])
			f.bits = binary.LittleEndian.Uint16(body[14:16])
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
	d.paused = false
	looping := d.looping
	items := d.items
	index := d.index
	posMS := d.posMS
	d.mu.Unlock()
	if !looping && index < len(items) {
		// Loaded with no loop running (without autoplay, stopped, or paused
		// when a seek or a reload landed): start one where the load left it.
		return d.Load(ctx, items, index, posMS, true)
	}
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
	// Its loop is on its way out, so a play right after starts another.
	d.looping = false
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
	// A seek restarts the fetch at the target offset (see openAudio).
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

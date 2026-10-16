package jukebox

import (
	"bytes"
	"context"
	"encoding/binary"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"slices"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/connect"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// wavBytes builds a minimal RIFF/WAVE stream: fmt chunk, one extra
// chunk to prove chunk-walking, then the data chunk header.
func wavBytes(t *testing.T, byteRate uint32, bits uint16) []byte {
	t.Helper()
	var b bytes.Buffer
	b.WriteString("RIFF")
	binary.Write(&b, binary.LittleEndian, uint32(0))
	b.WriteString("WAVE")
	b.WriteString("fmt ")
	binary.Write(&b, binary.LittleEndian, uint32(16))
	binary.Write(&b, binary.LittleEndian, uint16(1))
	binary.Write(&b, binary.LittleEndian, uint16(2))
	binary.Write(&b, binary.LittleEndian, uint32(44100))
	binary.Write(&b, binary.LittleEndian, byteRate)
	binary.Write(&b, binary.LittleEndian, uint16(4))
	binary.Write(&b, binary.LittleEndian, bits)
	b.WriteString("LIST")
	binary.Write(&b, binary.LittleEndian, uint32(4))
	b.WriteString("INFO")
	b.WriteString("data")
	binary.Write(&b, binary.LittleEndian, uint32(0))
	return b.Bytes()
}

func TestReadWAVHeader(t *testing.T) {
	raw := wavBytes(t, 176400, 16)
	header, f, err := readWAVHeader(bytes.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	if f.byteRate != 176400 || f.bits != 16 || f.blockAlign != 4 {
		t.Fatalf("format %+v", f)
	}
	// The header bytes replay verbatim to the player, chunk walk and
	// all, ending right after the data chunk header.
	if !bytes.Equal(header, raw) {
		t.Fatalf("header %d bytes, want %d", len(header), len(raw))
	}

	if _, _, err := readWAVHeader(bytes.NewReader([]byte("not a wav at all"))); err == nil {
		t.Fatal("garbage accepted")
	}
}

// numberedWAV is a WAV of four-byte frames at one a millisecond, each
// holding its own index, so where a reader starts is readable off the
// first frame it gets.
func numberedWAV(t *testing.T, frames int) (wav, header []byte) {
	t.Helper()
	header = wavBytes(t, 4000, 16)
	wav = append([]byte(nil), header...)
	for i := range frames {
		wav = binary.LittleEndian.AppendUint32(wav, uint32(i))
	}
	return wav, header
}

// startsAt reads a positioned stream: the header it must replay, then the
// index of the first frame after it.
func startsAt(t *testing.T, body io.Reader, header []byte) uint32 {
	t.Helper()
	got := make([]byte, len(header)+4)
	if _, err := io.ReadFull(body, got); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got[:len(header)], header) {
		t.Fatalf("the stream does not open with the file's header")
	}
	return binary.LittleEndian.Uint32(got[len(header):])
}

// oddChunkWAV is numberedWAV with an odd-sized LIST chunk ahead of its
// data, padded as RIFF pads one: a byte its size does not count. Tagged
// and broadcast WAVs carry such chunks.
func oddChunkWAV(t *testing.T, frames int) (wav, header []byte) {
	t.Helper()
	var b bytes.Buffer
	b.WriteString("RIFF")
	binary.Write(&b, binary.LittleEndian, uint32(0))
	b.WriteString("WAVE")
	b.WriteString("fmt ")
	binary.Write(&b, binary.LittleEndian, uint32(16))
	binary.Write(&b, binary.LittleEndian, uint16(1))
	binary.Write(&b, binary.LittleEndian, uint16(2))
	binary.Write(&b, binary.LittleEndian, uint32(1000))
	binary.Write(&b, binary.LittleEndian, uint32(4000))
	binary.Write(&b, binary.LittleEndian, uint16(4))
	binary.Write(&b, binary.LittleEndian, uint16(16))
	b.WriteString("LIST")
	binary.Write(&b, binary.LittleEndian, uint32(5))
	b.WriteString("INFOx")
	b.WriteByte(0)
	b.WriteString("data")
	binary.Write(&b, binary.LittleEndian, uint32(4*frames))
	header = append([]byte(nil), b.Bytes()...)
	for i := range frames {
		binary.Write(&b, binary.LittleEndian, uint32(i))
	}
	return b.Bytes(), header
}

// A chunk of odd size is followed by its pad byte, which the header keeps:
// the header replays to the player whole, and its length is where the
// frames begin when a start is fetched by range.
func TestReadWAVHeaderKeepsAnOddChunksPadByte(t *testing.T) {
	wav, header := oddChunkWAV(t, 3000)
	got, f, err := readWAVHeader(bytes.NewReader(wav))
	if err != nil || !bytes.Equal(got, header) || f.byteRate != 4000 || f.blockAlign != 4 {
		t.Fatalf("header %d bytes, format %+v, err %v; want the %d bytes through the data chunk's header", len(got), f, err, len(header))
	}
	for _, start := range []int64{0, 1000} {
		h := &audioHost{wav: wav, ranges: true}
		if got := startsAt(t, h.open(t, start), header); got != uint32(start) {
			t.Errorf("opened at %d ms, the audio starts on frame %d", start, got)
		}
	}
}

// audioHost serves numbered WAV audio the way the server would and
// records what each request asked for.
type audioHost struct {
	wav []byte
	// cuts says whether t is honoured (an engine render) or refused (an
	// original played as it is); ranges whether Range is.
	cuts, ranges bool

	mu        sync.Mutex
	gotCuts   []string
	gotRanges []string
}

func (h *audioHost) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.mu.Lock()
	h.gotCuts = append(h.gotCuts, r.URL.Query().Get("t"))
	h.gotRanges = append(h.gotRanges, r.Header.Get("Range"))
	h.mu.Unlock()
	if r.URL.Query().Has("t") && !h.cuts {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		io.WriteString(w, `{"code":"invalid-request","message":"t applies only to a stream the engine cuts"}`)
		return
	}
	if h.ranges {
		http.ServeContent(w, r, "audio.wav", time.Time{}, bytes.NewReader(h.wav))
		return
	}
	w.Write(h.wav)
}

// open serves h and opens its audio at startMS.
func (h *audioHost) open(t *testing.T, startMS int64) io.ReadCloser {
	t.Helper()
	srv := httptest.NewServer(h)
	t.Cleanup(srv.Close)
	body, err := openAudio(context.Background(), srv.URL+"/media/stream?pid=tr-X", startMS)
	if err != nil {
		t.Fatalf("opening at %d ms: %v", startMS, err)
	}
	t.Cleanup(func() { body.Close() })
	return body
}

// A seek or a resume reaches its start whichever way the server serves
// the item. A stream the engine renders is cut there in one request. An
// original served as it is (a WAV file, which needs no engine) is refused
// a cut, so its frames from the start are fetched by range past its
// header, or read past where a server ignores the range.
func TestOpenAudioReachesTheStartEitherWay(t *testing.T) {
	wav, header := numberedWAV(t, 3000)

	rendered := &audioHost{wav: wav, cuts: true}
	if got := startsAt(t, rendered.open(t, 1000), header); got != 0 ||
		!slices.Equal(rendered.gotCuts, []string{"1.000"}) {
		t.Errorf("a rendered stream starts on frame %d after cuts %q, want one request cut at 1.000", got, rendered.gotCuts)
	}

	original := &audioHost{wav: wav, ranges: true}
	if got := startsAt(t, original.open(t, 1000), header); got != 1000 {
		t.Errorf("an original resumed at 1 s starts on frame %d, want 1000", got)
	}
	// One frame a millisecond, four bytes a frame: 1 s in is 4000 bytes
	// past the header.
	if want := fmt.Sprintf("bytes=%d-", len(header)+4000); !slices.Contains(original.gotRanges, want) {
		t.Errorf("an original was fetched with ranges %q, want one from %s", original.gotRanges, want)
	}

	ignoring := &audioHost{wav: wav}
	if got := startsAt(t, ignoring.open(t, 1000), header); got != 1000 {
		t.Errorf("an original whose server ignores ranges starts on frame %d, want 1000", got)
	}

	// Past the end there is nothing left to play: the header, then the end.
	past := &audioHost{wav: wav, ranges: true}
	body := past.open(t, 5000)
	got := make([]byte, len(header)+1)
	if n, err := io.ReadFull(body, got); n != len(header) || !bytes.Equal(got[:n], header) || err != io.ErrUnexpectedEOF {
		t.Errorf("a start past the end read %d bytes (%v), want the header alone", n, err)
	}
}

// quietLog drops the driver's log lines.
type quietLog struct{}

func (quietLog) Info(string, ...any) {}
func (quietLog) Warn(string, ...any) {}

// newSilentDriver is a jukebox whose player swallows what it is fed, so
// nothing reaches a sound device.
func newSilentDriver(t *testing.T) *driver {
	t.Helper()
	group := supervise.NewGroup(nil)
	d := &driver{
		cfg:    Config{Command: []string{"sh", "-c", "cat > /dev/null"}, Log: quietLog{}},
		group:  group,
		events: make(chan connect.DriverEvent, 64),
		volume: 1,
	}
	t.Cleanup(func() {
		d.Close()
		group.Wait()
	})
	return d
}

// heldHost serves a WAV's header and its first frames, then holds the
// response open until the client goes, as a long item streams; each fetch
// reports the cut it asked for.
type heldHost struct {
	header  []byte
	fetches chan string
}

func (h *heldHost) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	h.fetches <- r.URL.Query().Get("t")
	w.Write(h.header)
	w.Write(make([]byte, 4096))
	w.(http.Flusher).Flush()
	<-r.Context().Done()
}

// nextFetch waits for the host's next fetch, or says there was none.
func (h *heldHost) nextFetch(within time.Duration) (string, bool) {
	select {
	case cut := <-h.fetches:
		return cut, true
	case <-time.After(within):
		return "", false
	}
}

// A load made while paused (a seek, a transfer, a reload after a queue
// edit) starts nothing, and the play after it starts the item where the
// load left it: the play has a loop to start, not just one to unpause.
func TestPlayStartsALoadMadeWhilePaused(t *testing.T) {
	_, header := numberedWAV(t, 0)
	host := &heldHost{header: header, fetches: make(chan string, 8)}
	srv := httptest.NewServer(host)
	t.Cleanup(srv.Close)
	d := newSilentDriver(t)
	ctx := context.Background()
	items := []connect.MediaItem{{PID: "tr-X", URL: srv.URL + "/media/stream?pid=tr-X", DurationMS: 60_000}}

	if err := d.Load(ctx, items, 0, 2000, false); err != nil {
		t.Fatal(err)
	}
	if cut, fetched := host.nextFetch(200 * time.Millisecond); fetched {
		t.Fatalf("a paused load fetched from %q", cut)
	}
	if err := d.Play(ctx); err != nil {
		t.Fatal(err)
	}
	if cut, fetched := host.nextFetch(5 * time.Second); !fetched || cut != "2.000" {
		t.Fatalf("play after a paused load fetched %v from %q, want the item from 2 s", fetched, cut)
	}

	// Paused mid-item, then a seek: the play after it starts at the seek.
	if err := d.Pause(ctx); err != nil {
		t.Fatal(err)
	}
	if err := d.SeekTo(ctx, 5000); err != nil {
		t.Fatal(err)
	}
	if cut, fetched := host.nextFetch(200 * time.Millisecond); fetched {
		t.Fatalf("a seek while paused fetched from %q", cut)
	}
	if err := d.Play(ctx); err != nil {
		t.Fatal(err)
	}
	if cut, fetched := host.nextFetch(5 * time.Second); !fetched || cut != "5.000" {
		t.Fatalf("play after a seek while paused fetched %v from %q, want the item from 5 s", fetched, cut)
	}
}

// oddReads hands out what it holds in reads of the sizes it cycles
// through, as a network body does whatever its framing.
type oddReads struct {
	b     []byte
	sizes []int
	n     int
}

func (r *oddReads) Read(p []byte) (int, error) {
	if len(r.b) == 0 {
		return 0, io.EOF
	}
	size := min(r.sizes[r.n%len(r.sizes)], len(p), len(r.b))
	r.n++
	copy(p, r.b[:size])
	r.b = r.b[size:]
	return size, nil
}

// The volume scales whole samples however the bytes arrive: a read of odd
// length must not leave every later sample scaled across its neighbour's
// bytes.
func TestPumpScalesWholeSamplesWhateverTheReads(t *testing.T) {
	header := wavBytes(t, 176400, 16)
	var data []byte
	for i := range 5000 {
		data = binary.LittleEndian.AppendUint16(data, uint16(int16(1000+i%7000)))
	}
	for name, sizes := range map[string][]int{
		"one odd read, then even": {4097, 32768},
		"odd reads throughout":    {3, 5, 7, 4093},
		"a byte at a time":        {1},
	} {
		t.Run(name, func(t *testing.T) {
			d := newSilentDriver(t)
			d.volume = 0.5
			src := io.MultiReader(bytes.NewReader(header), &oddReads{b: data, sizes: sizes})
			var out bytes.Buffer
			if err := d.pump(context.Background(), src, &out, 0, 0); err != nil {
				t.Fatal(err)
			}
			got := out.Bytes()[len(header):]
			if len(got) != len(data) {
				t.Fatalf("pumped %d bytes of audio, want %d", len(got), len(data))
			}
			for i := 0; i+1 < len(data); i += 2 {
				in := int16(binary.LittleEndian.Uint16(data[i:]))
				if s := int16(binary.LittleEndian.Uint16(got[i:])); s != in/2 {
					t.Fatalf("sample %d is %d, want %d at half volume", i/2, s, in/2)
				}
			}
		})
	}
}

func TestScalePCM16(t *testing.T) {
	samples := []int16{16000, -16000, 32767, -32768}
	buf := make([]byte, len(samples)*2)
	for i, s := range samples {
		binary.LittleEndian.PutUint16(buf[i*2:], uint16(s))
	}
	scalePCM16(buf, 0.5)
	got := make([]int16, len(samples))
	for i := range got {
		got[i] = int16(binary.LittleEndian.Uint16(buf[i*2:]))
	}
	want := []int16{8000, -8000, 16383, -16384}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("sample %d: got %d want %d", i, got[i], want[i])
		}
	}

	// Unity volume on the boundary values must not clip or wrap.
	buf2 := make([]byte, 4)
	high := int16(32767)
	low := int16(-32768)
	binary.LittleEndian.PutUint16(buf2[0:], uint16(high))
	binary.LittleEndian.PutUint16(buf2[2:], uint16(low))
	scalePCM16(buf2, 1.0)
	if int16(binary.LittleEndian.Uint16(buf2[0:])) != 32767 ||
		int16(binary.LittleEndian.Uint16(buf2[2:])) != -32768 {
		t.Fatal("unity scale changed boundary samples")
	}
}

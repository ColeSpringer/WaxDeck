package mp3join

import (
	"bytes"
	"context"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"math/rand/v2"
	"os"
	"testing"
	"testing/iotest"
	"time"

	"github.com/colespringer/waxflow"
	"github.com/colespringer/waxflow/codec/mp3"
	"github.com/colespringer/waxflow/container"

	"github.com/colespringer/waxdeck/fixtures"
)

// rendered renders a tagged MP3 the way the engine writes one: an ID3v2
// tag, an Info frame stating the stream's own length, then the audio.
func rendered(t *testing.T, name string, d time.Duration, rate, channels int) []byte {
	t.Helper()
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: name, Codec: fixtures.CodecMP3, Duration: d,
		SampleRate: rate, Channels: channels,
		Tags: map[string]string{"TITLE": name},
	})
	if err != nil {
		t.Fatal(err)
	}
	b, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	return b
}

// frames splits a bare MP3 stream into its frames, failing on any byte
// that is not part of one.
func frames(t *testing.T, b []byte) [][]byte {
	t.Helper()
	var out [][]byte
	for off := 0; off < len(b); {
		h, err := mp3.ParseHeader(b[off:])
		if err != nil || h.Size() == 0 || off+h.Size() > len(b) {
			t.Fatalf("byte %d of %d is not the start of a whole frame (%v)", off, len(b), err)
		}
		out = append(out, b[off:off+h.Size()])
		off += h.Size()
	}
	return out
}

// audio is a rendered stream's audio frames: past its tag and its Info
// frame.
func audio(t *testing.T, stream []byte) [][]byte {
	t.Helper()
	if string(stream[:3]) != "ID3" {
		t.Fatal("the rendered stream carries no ID3v2 tag")
	}
	size := int(stream[6])<<21 | int(stream[7])<<14 | int(stream[8])<<7 | int(stream[9])
	all := frames(t, stream[10+size:])
	h, _ := mp3.ParseHeader(all[0])
	at := mp3.HeaderLen + h.SideInfoLen()
	if string(all[0][at:at+4]) != "Info" {
		t.Fatal("the rendered stream does not open with its Info frame")
	}
	return all[1:]
}

// decodedSeconds is how long the engine's own decoder reads b to be.
func decodedSeconds(t *testing.T, b []byte) float64 {
	t.Helper()
	res, err := waxflow.New().Transcode(context.Background(), container.BytesSource(b), "mp3",
		io.Discard, waxflow.TranscodeOptions{Format: "wav"})
	if err != nil {
		t.Fatalf("decoding: %v", err)
	}
	return float64(res.Samples) / float64(res.Format.Rate)
}

func noFlush() {}

// Ahead of a stream's audio sit its tag and the Info frame stating its
// own length. Both go, and every frame of audio comes through whole,
// however the bytes arrive, but the last: three seconds end 1427 samples
// of padding into it, a whole frame of nothing else.
func TestCopyKeepsTheAudioAndDropsTheStreamsOwnLength(t *testing.T) {
	stream := rendered(t, "part", 3*time.Second, 44100, 2)
	all := audio(t, stream)
	want := bytes.Join(all[:len(all)-1], nil)
	for name, src := range map[string]io.Reader{
		"whole":            bytes.NewReader(stream),
		"a byte at a time": iotest.OneByteReader(bytes.NewReader(stream)),
	} {
		var out bytes.Buffer
		if _, readErr, writeErr := Copy(&out, src, Shape{}, noFlush); readErr != nil || writeErr != nil {
			t.Fatalf("%s: read %v, write %v", name, readErr, writeErr)
		}
		if !bytes.Equal(out.Bytes(), want) {
			got := out.Bytes()
			t.Fatalf("%s: copied %d bytes opening %q, want the stream's %d bytes of audio frames",
				name, len(got), got[:min(4, len(got))], len(want))
		}
	}
}

// Streams copied one after another read as one stream as long as their
// sum: a decoder finds no length but the frames themselves.
func TestCopiedStreamsDecodeAsOne(t *testing.T) {
	var joined bytes.Buffer
	for _, p := range []struct {
		name string
		d    time.Duration
	}{{"one", 3 * time.Second}, {"two", 4 * time.Second}} {
		if _, readErr, writeErr := Copy(&joined, bytes.NewReader(rendered(t, p.name, p.d, 44100, 2)), Shape{}, noFlush); readErr != nil || writeErr != nil {
			t.Fatalf("%s: read %v, write %v", p.name, readErr, writeErr)
		}
	}
	// Each seam carries the encoder's priming, a few frames at most.
	if got := decodedSeconds(t, joined.Bytes()); got < 7 || got > 7.2 {
		t.Fatalf("the joined streams decode to %.3f s, want the 7 s of both", got)
	}
}

// What follows the frames is not audio (a trailing tag, a frame cut
// short), so it stays behind.
func TestCopyLeavesWhatIsNotAFrame(t *testing.T) {
	stream := rendered(t, "part", 2*time.Second, 22050, 1)
	frames := audio(t, stream)
	whole := bytes.Join(frames, nil)
	id3v1 := append([]byte("TAG"), make([]byte, 125)...)
	for name, c := range map[string]struct {
		in, want []byte
	}{
		"a trailing ID3v1 tag": {append(append([]byte{}, stream...), id3v1...), whole},
		"a last frame cut short": {stream[:len(stream)-len(frames[len(frames)-1])/2],
			bytes.Join(frames[:len(frames)-1], nil)},
	} {
		var out bytes.Buffer
		if _, readErr, writeErr := Copy(&out, bytes.NewReader(c.in), Shape{}, noFlush); readErr != nil || writeErr != nil {
			t.Fatalf("%s: read %v, write %v", name, readErr, writeErr)
		}
		if !bytes.Equal(out.Bytes(), c.want) {
			t.Errorf("%s: copied %d bytes, want the %d bytes of whole frames", name, out.Len(), len(c.want))
		}
	}
}

// A broken source and a gone reader are told apart: the one is the
// stream's failure, the other the listener's leaving.
func TestCopySaysWhichSideFailed(t *testing.T) {
	stream := rendered(t, "part", 2*time.Second, 44100, 2)
	broke := errors.New("the engine went away")
	src := io.MultiReader(bytes.NewReader(stream[:len(stream)/2]), iotest.ErrReader(broke))
	var out bytes.Buffer
	_, readErr, writeErr := Copy(&out, src, Shape{}, noFlush)
	if !errors.Is(readErr, broke) || writeErr != nil {
		t.Fatalf("a broken source = read %v, write %v; want the read error alone", readErr, writeErr)
	}
	frames(t, out.Bytes()) // whole frames only, up to the break

	gone := errors.New("the listener hung up")
	_, readErr, writeErr = Copy(failingWriter{gone}, bytes.NewReader(stream), Shape{}, noFlush)
	if readErr != nil || !errors.Is(writeErr, gone) {
		t.Fatalf("a gone reader = read %v, write %v; want the write error alone", readErr, writeErr)
	}
}

type failingWriter struct{ err error }

func (w failingWriter) Write([]byte) (int, error) { return 0, w.err }

// What was read is reported, so a caller can tell a stream that ended
// early from one that ended whole: the audio frames read against the
// count the stream's own Info frame states, and the frames' shape.
func TestCopyReportsWhatItRead(t *testing.T) {
	// Two seconds end 1751 samples of padding into their last frame at
	// 44.1 kHz, one whole frame of it; at 22.05 kHz only 347, no frame.
	for _, shape := range []struct{ rate, channels, spf, trimmed int }{{44100, 2, 1152, 1}, {22050, 1, 576, 0}} {
		stream := rendered(t, fmt.Sprintf("p%d", shape.rate), 2*time.Second, shape.rate, shape.channels)
		n := len(audio(t, stream))
		got, readErr, writeErr := Copy(io.Discard, bytes.NewReader(stream), Shape{}, noFlush)
		if readErr != nil || writeErr != nil {
			t.Fatal(readErr, writeErr)
		}
		want := Stream{Frames: n, Stated: n, Trimmed: shape.trimmed, Rate: shape.rate, Channels: shape.channels, SamplesPerFrame: shape.spf}
		if got != want {
			t.Errorf("%d Hz: read %+v, want %+v", shape.rate, got, want)
		}
		// Half of it read is half the frames, against the whole count.
		got, _, _ = Copy(io.Discard, bytes.NewReader(stream[:len(stream)/2]), Shape{}, noFlush)
		if got.Stated != n || got.Frames >= n*2/3 || got.Frames == 0 {
			t.Errorf("%d Hz, cut in half: read %+v, want about half of %d frames against %d stated", shape.rate, got, n, n)
		}
	}
}

// decodedPCM is what the engine's own decoder makes of b: the WAV data,
// in the decoder's float samples.
func decodedPCM(t *testing.T, b []byte) []byte {
	t.Helper()
	var out bytes.Buffer
	if _, err := waxflow.New().Transcode(context.Background(), container.BytesSource(b), "mp3",
		struct{ io.Writer }{&out}, waxflow.TranscodeOptions{Format: "wav"}); err != nil {
		t.Fatalf("decoding: %v", err)
	}
	wav := out.Bytes()
	at := bytes.Index(wav, []byte("data"))
	if at < 0 {
		t.Fatal("the decode carries no data chunk")
	}
	return wav[at+8:]
}

// A stream's last frames can decode to nothing but its end padding, which
// its Info frame tells a decoder to trim and a joined stream cannot say.
// They go when the stream ends with every frame it stated, and what is
// left decodes, sample for sample, to the stream's own audio after the
// encoder's head delay.
func TestCopyDropsTrailingFramesOfPaddingAlone(t *testing.T) {
	stream := rendered(t, "part", time.Second, 44100, 2)
	n := len(audio(t, stream))
	var out bytes.Buffer
	got, readErr, writeErr := Copy(&out, bytes.NewReader(stream), Shape{}, noFlush)
	if readErr != nil || writeErr != nil || got.Trimmed != 1 || len(frames(t, out.Bytes())) != n-1 {
		t.Fatalf("copied %d of %d frames (%+v, %v, %v), want all but the last, which is padding alone",
			len(frames(t, out.Bytes())), n, got, readErr, writeErr)
	}
	own := decodedPCM(t, stream) // gapless: the stream's own samples
	joined := decodedPCM(t, out.Bytes())
	const head = (528 + 529) * 2 * 4 // the head delay, in stereo float32 bytes
	if len(joined) < head+len(own) || !bytes.Equal(joined[head:head+len(own)], own) {
		t.Fatalf("the copy decodes to %d bytes that do not hold the stream's own %d at its head delay", len(joined), len(own))
	}

	// Six one-second streams: the seams carry a frame less each.
	var six bytes.Buffer
	for range 6 {
		Copy(&six, bytes.NewReader(stream), Shape{}, noFlush)
	}
	if secs := decodedSeconds(t, six.Bytes()); secs > 6.3 {
		t.Fatalf("six one-second streams joined decode to %.3f s, want under 6.3 (6.426 untrimmed)", secs)
	}

	// A stream that ended short of its stated count has no known padding,
	// so nothing goes.
	cut := stream[:len(stream)*3/4]
	got, _, _ = Copy(io.Discard, bytes.NewReader(cut), Shape{}, noFlush)
	if got.Trimmed != 0 || got.Frames >= got.Stated {
		t.Fatalf("a stream ending early: %+v, want nothing trimmed", got)
	}
}

// noise is n high-entropy bytes, what a cover image's compressed body is
// to a frame scanner.
func noise(seed uint64, n int) []byte {
	r := rand.New(rand.NewPCG(seed, 99))
	b := make([]byte, n)
	for i := range b {
		b[i] = byte(r.UintN(256))
	}
	return b
}

// apeTag is an APEv2 tag as a tagger appends one: an item holding cover
// bytes, a footer, and a header ahead of them when withHeader is set.
func apeTag(cover []byte, withHeader bool) []byte {
	item := binary.LittleEndian.AppendUint32(nil, uint32(len(cover)))
	item = binary.LittleEndian.AppendUint32(item, 2) // binary item
	item = append(append(item, "Cover Art (Front)\x00"...), cover...)
	frame := func(flags uint32) []byte {
		b := append([]byte("APETAGEX"), binary.LittleEndian.AppendUint32(nil, 2000)...)
		b = binary.LittleEndian.AppendUint32(b, uint32(len(item)+32))
		b = binary.LittleEndian.AppendUint32(b, 1)
		b = binary.LittleEndian.AppendUint32(b, flags)
		return append(b, make([]byte, 8)...)
	}
	var out []byte
	if withHeader {
		out = frame(1<<31 | 1<<29)
	}
	out = append(out, item...)
	return append(out, frame(1<<31)...)
}

// id3v2Tag is an ID3v2.4 tag around body, as a tagger appends one at a
// file's end.
func id3v2Tag(body []byte) []byte {
	n := len(body)
	return append([]byte{'I', 'D', '3', 4, 0, 0, byte(n >> 21 & 0x7F), byte(n >> 14 & 0x7F), byte(n >> 7 & 0x7F), byte(n & 0x7F)}, body...)
}

// copyOf copies b whole as no particular shape.
func copyOf(t *testing.T, b []byte) (Stream, []byte) {
	t.Helper()
	var out bytes.Buffer
	got, readErr, writeErr := Copy(&out, bytes.NewReader(b), Shape{}, noFlush)
	if readErr != nil || writeErr != nil {
		t.Fatal(readErr, writeErr)
	}
	return got, out.Bytes()
}

// A library file can end in tags after its last frame (ID3v1, APEv2,
// Lyrics3, an appended ID3v2), whose bytes, a cover's above all, hold
// what parses as frame headers. The copy stops at them: what comes through
// is the stream's own frames, its padding trimmed as without them.
func TestCopyStopsAtTrailingTags(t *testing.T) {
	stream := rendered(t, "part", 3*time.Second, 44100, 2)
	want, clean := copyOf(t, stream)
	id3v1 := append([]byte("TAG"), noise(1, 125)...)
	for name, tail := range map[string][]byte{
		"an ID3v1 tag":                id3v1,
		"an APEv2 tag with a header":  apeTag(noise(2, 32<<10), true),
		"an APEv2 tag with no header": apeTag(noise(3, 32<<10), false),
		"an APEv2 tag, then ID3v1":    append(apeTag(noise(4, 32<<10), false), id3v1...),
		"a Lyrics3 tag, then ID3v1":   append([]byte("LYRICSBEGININD00002\x00\x00LYR00005words000027LYRICS200"), id3v1...),
		"an appended ID3v2 tag":       id3v2Tag(noise(5, 32<<10)),
	} {
		got, out := copyOf(t, append(append([]byte(nil), stream...), tail...))
		if got != want || !bytes.Equal(out, clean) {
			t.Errorf("%s: copied %d bytes (%+v), want the stream's own %d (%+v)", name, len(out), got, len(clean), want)
		}
	}
}

// A part can be tagged files end to end (two MP3s concatenated, as a
// joining tool or a shell writes them). The copy passes each file's tags
// and metadata frame and carries on: it is every file's audio, each
// trimmed of its end padding as one part is, and what it reports counts
// them all, so a second file cut short reads as short.
func TestCopyCarriesOnThroughFilesEndToEnd(t *testing.T) {
	a := rendered(t, "a", 2*time.Second, 44100, 2)
	b := rendered(t, "b", 3*time.Second, 44100, 2)
	wantA, cleanA := copyOf(t, a)
	wantB, cleanB := copyOf(t, b)
	want := Stream{
		Frames: wantA.Frames + wantB.Frames, Stated: wantA.Stated + wantB.Stated, Trimmed: wantA.Trimmed + wantB.Trimmed,
		Rate: 44100, Channels: 2, SamplesPerFrame: 1152,
	}
	clean := append(append([]byte(nil), cleanA...), cleanB...)
	id3v1 := append([]byte("TAG"), noise(6, 125)...)
	for name, between := range map[string][]byte{
		"nothing between":                  nil,
		"an ID3v1 tag between":             id3v1,
		"an APEv2 tag and ID3v1 between":   append(apeTag(noise(7, 32<<10), true), id3v1...),
		"a headerless APEv2 tag between":   apeTag(noise(8, 32<<10), false),
		"a Lyrics3 tag and ID3v1 between":  append([]byte("LYRICSBEGININD00002\x00\x00LYR00005words000027LYRICS200"), id3v1...),
		"an appended ID3v2 tag in between": id3v2Tag(noise(9, 32<<10)),
	} {
		joined := append(append(append([]byte(nil), a...), between...), b...)
		got, out := copyOf(t, joined)
		if got != want || !bytes.Equal(out, clean) {
			t.Errorf("%s: copied %d bytes (%+v), want both files' %d (%+v)", name, len(out), got, len(clean), want)
		}
	}
	if secs := decodedSeconds(t, clean); secs < 5 || secs > 5.2 {
		t.Fatalf("both files decode to %.3f s, want their 5", secs)
	}
	got, _ := copyOf(t, append(append([]byte(nil), a...), b[:len(b)/2]...))
	if short := got.Shortfall(5000, 0); short < 1 {
		t.Fatalf("the second file cut in half reads %+v, short by %.2f s; want about 1.5 s short", got, short)
	}
}

// Bytes past the frames that are no tag at all (damage, a tagger's
// private block) can still parse as frame headers. Only a frame of the
// stream's own shape is taken, and after a byte skipped only one whose
// successor is another such frame or the end: none of the noise comes
// through, and the padding is trimmed as without it.
func TestCopyTakesNoFrameFromNoise(t *testing.T) {
	stream := rendered(t, "part", 3*time.Second, 44100, 2)
	want, clean := copyOf(t, stream)
	for _, size := range []int{32 << 10, 128 << 10} {
		for seed := uint64(1); seed <= 4; seed++ {
			got, out := copyOf(t, append(append([]byte(nil), stream...), noise(seed, size)...))
			if got != want || !bytes.Equal(out, clean) {
				t.Errorf("%d KB of noise, seed %d: copied %d bytes (%+v), want the stream's own %d (%+v)",
					size>>10, seed, len(out), got, len(clean), want)
			}
		}
	}
}

// Frames of another shape after the stream's own are no frames of it: a
// player set up for one rate would meet them mid-stream.
func TestCopyKeepsToTheFirstFramesShape(t *testing.T) {
	a := rendered(t, "a", 2*time.Second, 44100, 2)
	b := rendered(t, "b", 2*time.Second, 22050, 1)
	want, clean := copyOf(t, a)
	got, out := copyOf(t, append(append([]byte(nil), a...), bytes.Join(audio(t, b), nil)...))
	if got != want || !bytes.Equal(out, clean) {
		t.Fatalf("copied %d bytes (%+v), want the first stream's own %d (%+v)", len(out), got, len(clean), want)
	}
}

// A stream copied as a shape it does not have is refused before any of it
// is written; its own shape, or none asked, copies whole.
func TestCopyRefusesAStreamOfAnotherShape(t *testing.T) {
	stream := rendered(t, "part", time.Second, 44100, 2)
	var out bytes.Buffer
	_, readErr, writeErr := Copy(&out, bytes.NewReader(stream), Shape{Rate: 22050, Channels: 1}, noFlush)
	if !errors.Is(readErr, ErrShape) || writeErr != nil || out.Len() != 0 {
		t.Fatalf("copied as 22050 Hz mono: read %v, write %v, %d bytes; want ErrShape and nothing", readErr, writeErr, out.Len())
	}
	for _, shape := range []Shape{{Rate: 44100, Channels: 2}, {}} {
		out.Reset()
		if _, readErr, writeErr := Copy(&out, bytes.NewReader(stream), shape, noFlush); readErr != nil || writeErr != nil || out.Len() == 0 {
			t.Errorf("copied as %+v: read %v, write %v, %d bytes; want it whole", shape, readErr, writeErr, out.Len())
		}
	}
}

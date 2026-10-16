// Package mp3join joins MP3 streams end to end into one stream of bare
// Layer III frames. A stream's first audio frame references no bit
// reservoir before it, so streams join at frame boundaries; what belongs
// to one stream alone (its tags, and the metadata frame stating its
// length, which a player would take for the whole stream's) is left out.
// Response serves such a join as one HTTP response.
package mp3join

import (
	"bufio"
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"math"

	"github.com/colespringer/waxflow/codec/mp3"
)

// frameBuffer is the read buffer over one stream, far past the largest
// Layer III frame (1441 bytes), so a frame is always peekable whole.
const frameBuffer = 64 << 10

// Shape is a stream's sample rate and channel count, which a player sets
// its decoder up for once per stream.
type Shape struct{ Rate, Channels int }

// ErrShape is a stream whose frames are not the shape it was copied as.
var ErrShape = errors.New("mp3join: the stream is not the shape asked for")

// Stream is what Copy found in one stream.
type Stream struct {
	// Frames counts the audio frames read, the metadata frame aside.
	Frames int
	// Stated is the audio frame count the metadata frame states, zero
	// when it states none.
	Stated int
	// Trimmed counts the trailing frames left out as end padding alone.
	Trimmed int
	// Rate and Channels are the first frame's, SamplesPerFrame its length
	// in samples; all zero when the stream held no frame.
	Rate, Channels, SamplesPerFrame int
}

// Shortfall is how far a stream that ended cleanly fell short of its
// length, zero when it did not. A live encode that fails part-way ends as
// cleanly as one that finishes, and a file cut short on disk reads to a
// clean end, so the length is the only sign. That length is the lesser
// of what the stream's own metadata frame states and lengthMS, its length
// as known elsewhere (zero when unknown) less cutMS of its head cut away
// before it began; so a hint either one overstates breaks nothing, and the
// slack, a second or 2% of the length, covers what each one rounds.
func (s Stream) Shortfall(lengthMS, cutMS int64) float64 {
	want := math.Inf(1)
	if s.Stated > 0 && s.Rate > 0 {
		want = float64(s.Stated*s.SamplesPerFrame) / float64(s.Rate)
	}
	if lengthMS > 0 {
		want = min(want, float64(lengthMS-cutMS)/1000)
	}
	if math.IsInf(want, 1) {
		return 0
	}
	read := 0.0
	if s.Rate > 0 {
		read = float64(s.Frames*s.SamplesPerFrame) / float64(s.Rate)
	}
	if read >= want-max(1, want/50) {
		return 0
	}
	return want - read
}

// Copy copies one MP3 stream to dst as bare frames: it drops the
// stream's tags and, when its first frame is a Xing, Info or VBRI frame,
// that frame. Every later frame of the first one's shape passes, but for
// the last ones that frame says decode to its end padding alone, which
// are dropped when the stream ends with every frame it stated. A tag
// (ID3v1, APEv2, Lyrics3, ID3v2) is passed over by its own length, and
// what follows one may be another stream, as in a part that is tagged
// files end to end: its metadata frame is dropped and its count added,
// and the one before keeps or drops its padding by its own count. Bytes
// that are neither stay behind, and after one is skipped a frame counts
// only when its successor is another, a tag or the end: a tag's or a
// damaged stretch's bytes can parse as a header, but rarely as two in a
// row. want, when set, is the shape the stream must have: a first frame
// of another is refused as ErrShape before anything is written. flush
// runs before any read that may wait, so audio leaves as it arrives.
// readErr is the stream breaking (a clean end is nil), writeErr dst's.
func Copy(dst io.Writer, src io.Reader, want Shape, flush func()) (s Stream, readErr, writeErr error) {
	br := bufio.NewReaderSize(src, frameBuffer)
	peek := func(n int) ([]byte, error) {
		if br.Buffered() < n {
			flush()
		}
		return br.Peek(n)
	}
	// The last frames are held back until the stream says whether they
	// were its padding: they are, when it ends with every frame it stated.
	var tail fifo
	held := 0
	// sub counts the frames of the stream being read against the count its
	// metadata frame stated; total is every stream's stated count, which
	// stands only while each one has stated its own.
	var subFrames, subStated, total int
	unstated := false
	report := func() Stream {
		s.Stated = 0
		if !unstated {
			s.Stated = total
		}
		return s
	}
	// closeSub settles what the stream just read held back: its padding,
	// dropped, when it ended with every frame it stated, else its audio.
	closeSub := func() error {
		if subStated > 0 && subFrames == subStated {
			s.Trimmed += tail.len()
			tail.drop()
			return nil
		}
		return tail.drain(dst)
	}
	end := func(err error) (Stream, error, error) {
		if err = streamEnd(err); err != nil {
			return report(), err, nil
		}
		err = closeSub()
		return report(), nil, err
	}
	var first mp3.Header // the first frame's, the stream's shape
	// skipped says bytes were passed over since the last frame; opens says
	// a tag was, so the next frame may open another stream.
	started, skipped, opens := false, false, false
	for {
		head, err := peek(lookahead)
		if n := tagLength(head, peek); n > 0 {
			if _, err := br.Discard(n); err != nil {
				return end(err)
			}
			skipped, opens = true, started
			continue
		}
		if len(head) < mp3.HeaderLen {
			return end(err)
		}
		size := 0
		h, perr := mp3.ParseHeader(head)
		if perr == nil && (!started || h.Kin(first)) {
			size = h.Size()
		}
		if size > mp3.HeaderLen && skipped {
			ref := first
			if !started {
				ref = h
			}
			if !followed(peek, size, ref) {
				size = 0
			}
		}
		if size <= mp3.HeaderLen {
			// Not a frame's start (or the free format, which no encoder
			// here writes): step past the byte and look again.
			if _, err := br.Discard(1); err != nil {
				return end(err)
			}
			skipped = true
			continue
		}
		frame, err := peek(size)
		if len(frame) < size {
			return end(err)
		}
		skipped = false
		opensSub := !started || opens
		opens = false
		if !started {
			if want != (Shape{}) && (h.Rate != want.Rate || h.Channels != want.Channels) {
				return s, fmt.Errorf("%w: %d Hz x %d, not %d Hz x %d", ErrShape, h.Rate, h.Channels, want.Rate, want.Channels), nil
			}
			started, first = true, h
			s.Rate, s.Channels, s.SamplesPerFrame = h.Rate, h.Channels, h.SamplesPerFrame()
		} else if opensSub {
			if err := closeSub(); err != nil {
				return report(), nil, err
			}
			subFrames, subStated, held = 0, 0, 0
		}
		if opensSub {
			// A stream's head: its metadata frame, or audio that states no
			// count, which leaves the whole stream's count unknown.
			t, ok := readTag(frame, h)
			subStated = t.frames
			total += t.frames
			unstated = unstated || t.frames == 0
			if ok {
				held = t.paddingFrames(h.SamplesPerFrame())
				br.Discard(size)
				continue
			}
		}
		s.Frames++
		subFrames++
		if err := tail.push(dst, frame, held); err != nil {
			return report(), nil, err
		}
		br.Discard(size)
	}
}

// lookahead is how far ahead of a frame's start Copy looks: a header, or
// the longest tag signature it knows.
const lookahead = 11

// tagLength answers how many bytes the tag b opens takes, b being what
// lies at the reader's head, and 0 when it opens none. ID3v2 and APEv2
// state their length (an APEv2 header counts what follows it; its footer,
// met first when there is no header, counts what came before), ID3v1 is a
// fixed 128 bytes, and a Lyrics3 tag, whose length sits at its end, is
// passed by its signature: its text holds nothing that reads as a frame.
func tagLength(b []byte, peek func(int) ([]byte, error)) int {
	switch {
	case !opensTag(b):
		return 0
	case id3v2Size(b) > 0:
		return id3v2Size(b)
	case bytes.HasPrefix(b, []byte("TAG")):
		return 128
	case bytes.HasPrefix(b, []byte("LYRICSBEGIN")):
		return len("LYRICSBEGIN")
	case bytes.HasPrefix(b, []byte("APETAGEX")):
		ape, _ := peek(apeTagLen)
		if len(ape) < apeTagLen {
			return len(ape)
		}
		if binary.LittleEndian.Uint32(ape[20:24])&apeIsHeader == 0 {
			return apeTagLen
		}
		return apeTagLen + int(binary.LittleEndian.Uint32(ape[12:16]))
	}
	return 0
}

// opensTag reports whether b opens a tag: ID3v1, APEv2, Lyrics3 or ID3v2.
func opensTag(b []byte) bool {
	return bytes.HasPrefix(b, []byte("TAG")) || bytes.HasPrefix(b, []byte("APETAGEX")) ||
		bytes.HasPrefix(b, []byte("LYRICSBEGIN")) || id3v2Size(b) > 0
}

// apeTagLen is an APEv2 header's or footer's length, and apeIsHeader the
// flag that says which one it is.
const (
	apeTagLen   = 32
	apeIsHeader = 1 << 29
)

// followed reports whether the frame of size bytes at the reader's head
// is followed by another of ref's shape, by the stream's end, or by a
// tag.
func followed(peek func(int) ([]byte, error), size int, ref mp3.Header) bool {
	b, _ := peek(size + lookahead)
	if len(b) <= size {
		return len(b) == size
	}
	next := b[size:]
	if opensTag(next) {
		return true
	}
	h, err := mp3.ParseHeader(next)
	return err == nil && h.Kin(ref) && h.Size() > mp3.HeaderLen
}

// fifo holds a stream's last few frames back, reusing their buffers.
type fifo struct {
	frames [][]byte
	spare  [][]byte
}

func (f *fifo) len() int { return len(f.frames) }

// push queues frame and writes out whatever falls past the last keep.
func (f *fifo) push(dst io.Writer, frame []byte, keep int) error {
	if keep == 0 {
		_, err := dst.Write(frame)
		return err
	}
	var b []byte
	if n := len(f.spare); n > 0 {
		b, f.spare = f.spare[n-1][:0], f.spare[:n-1]
	}
	f.frames = append(f.frames, append(b, frame...))
	if len(f.frames) <= keep {
		return nil
	}
	out := f.frames[0]
	f.frames = append(f.frames[:0], f.frames[1:]...)
	f.spare = append(f.spare, out)
	_, err := dst.Write(out)
	return err
}

// drain writes every frame still held.
func (f *fifo) drain(dst io.Writer) error {
	for _, b := range f.frames {
		if _, err := dst.Write(b); err != nil {
			return err
		}
	}
	f.frames = f.frames[:0]
	return nil
}

// drop lets every frame still held go unwritten, keeping their buffers.
func (f *fifo) drop() {
	f.spare = append(f.spare, f.frames...)
	f.frames = f.frames[:0]
}

// streamEnd reads a short read: a stream's end is no failure, so a frame
// cut short there is simply left behind.
func streamEnd(err error) error {
	if err == io.EOF {
		return nil
	}
	return err
}

// id3v2Size answers the length of the ID3v2 tag head opens, footer
// included, or 0 when head is not one.
func id3v2Size(head []byte) int {
	if len(head) < 10 || string(head[:3]) != "ID3" || head[3] == 0xFF || head[4] == 0xFF {
		return 0
	}
	size := 0
	for _, b := range head[6:10] {
		if b&0x80 != 0 {
			return 0
		}
		size = size<<7 | int(b)
	}
	size += 10
	if head[5]&0x10 != 0 {
		size += 10
	}
	return size
}

// decoderDelay is Layer III's fixed decoder latency in samples. The
// LAME tag's padding field counts it in: a decoder's output ends with the
// field's padding less this.
const decoderDelay = 529

// maxPaddingFrames bounds the frames trimmed as padding: an encoder's
// flush and rounding span two frames at most.
const maxPaddingFrames = 2

// tag is what a metadata frame states.
type tag struct {
	// frames is the stream's audio frame count, zero when unstated.
	frames int
	// padding is the LAME extension's end padding field, zero when the
	// frame carries none.
	padding int
}

// paddingFrames is how many of the stream's last frames decode to end
// padding alone, at spf samples a frame.
func (t tag) paddingFrames(spf int) int {
	if spf <= 0 || t.padding <= decoderDelay {
		return 0
	}
	return min((t.padding-decoderDelay)/spf, maxPaddingFrames)
}

// readTag reads frame as a Xing, Info or VBRI frame: a silent frame whose
// payload states its stream's length and trims. ok is false for an audio
// frame.
func readTag(frame []byte, h mp3.Header) (t tag, ok bool) {
	at := mp3.HeaderLen + h.SideInfoLen()
	if h.Protected {
		at += 2
	}
	if len(frame) >= at+8 {
		if magic := string(frame[at : at+4]); magic == "Xing" || magic == "Info" {
			flags := binary.BigEndian.Uint32(frame[at+4:])
			p := at + 8
			if flags&1 != 0 && len(frame) >= p+4 {
				t.frames = int(binary.BigEndian.Uint32(frame[p:]))
			}
			// The optional fields in flag order: frames, bytes, TOC, quality.
			for i, n := range []int{4, 4, 100, 4} {
				if flags&(1<<i) != 0 {
					p += n
				}
			}
			// The LAME extension: a 9-byte encoder string, then the delay
			// and padding packed in three bytes 12 past it.
			if len(frame) >= p+9+15 {
				switch string(frame[p : p+4]) {
				case "LAME", "Lavc", "Lavf", "WaxF":
					b := frame[p+21:]
					t.padding = int(b[1]&0xF)<<8 | int(b[2])
				}
			}
			return t, true
		}
	}
	// VBRI sits 32 bytes past the header whatever the layout.
	if len(frame) >= 36+26 && string(frame[36:40]) == "VBRI" {
		t.frames = int(binary.BigEndian.Uint32(frame[36+14:]))
		return t, true
	}
	return tag{}, false
}

package analyzer

// A self-contained RIFF WAVE reader for the audio-pull fast path. The
// server's analysis endpoint serves plain PCM WAV at the analysis
// rate, so the common case never needs a decoder at all; anything this
// parser cannot place (compressed WAV flavors, an unexpected rate)
// falls back to the generic WaxFlow decode in transcodeToMono.

import (
	"encoding/binary"
	"fmt"
	"io"
	"math"
)

// WAVE format codes this parser decodes directly.
const (
	wavFormatPCM        = 1
	wavFormatFloat      = 3
	wavFormatExtensible = 0xFFFE
)

// ParseWAV decodes a RIFF WAVE byte stream into mono samples in
// [-1, 1] plus the sample rate. Multi-channel input downmixes by
// averaging. Streamed WAV commonly carries placeholder chunk sizes
// (the writer never knew the final length), so the data chunk is
// clamped to the bytes actually present.
func ParseWAV(b []byte) ([]float32, int, error) {
	if len(b) < 12 || string(b[0:4]) != "RIFF" || string(b[8:12]) != "WAVE" {
		return nil, 0, fmt.Errorf("not a RIFF WAVE stream")
	}
	var (
		haveFmt    bool
		formatCode int
		channels   int
		rate       int
		bits       int
		data       []byte
	)
	off := 12
	for off+8 <= len(b) {
		id := string(b[off : off+4])
		size := int(int64(binary.LittleEndian.Uint32(b[off+4 : off+8])))
		body := b[off+8:]
		clamped := false
		if size > len(body) {
			size = len(body)
			clamped = true
		}
		body = body[:size]
		switch id {
		case "fmt ":
			if len(body) < 16 {
				return nil, 0, fmt.Errorf("fmt chunk is %d bytes, want at least 16", len(body))
			}
			formatCode = int(binary.LittleEndian.Uint16(body[0:2]))
			channels = int(binary.LittleEndian.Uint16(body[2:4]))
			rate = int(binary.LittleEndian.Uint32(body[4:8]))
			bits = int(binary.LittleEndian.Uint16(body[14:16]))
			if formatCode == wavFormatExtensible {
				// The real code is the first two bytes of the
				// extension's SubFormat GUID.
				if len(body) < 26 {
					return nil, 0, fmt.Errorf("extensible fmt chunk is %d bytes, want at least 26", len(body))
				}
				formatCode = int(binary.LittleEndian.Uint16(body[24:26]))
			}
			haveFmt = true
		case "data":
			data = body
		}
		if clamped {
			break // a truncated chunk is the last readable one
		}
		off += 8 + size + size%2 // chunks are word-aligned
	}
	if !haveFmt {
		return nil, 0, fmt.Errorf("no fmt chunk")
	}
	if data == nil {
		return nil, 0, fmt.Errorf("no data chunk")
	}
	if channels < 1 || rate < 1 {
		return nil, 0, fmt.Errorf("fmt chunk claims %d channels at %d Hz", channels, rate)
	}
	samples, err := decodePCM(data, formatCode, bits, channels)
	if err != nil {
		return nil, 0, err
	}
	return samples, rate, nil
}

// decodePCM converts interleaved sample data to mono float32,
// averaging channels.
func decodePCM(data []byte, formatCode, bits, channels int) ([]float32, error) {
	var read func(b []byte) float64
	var bps int
	switch {
	case formatCode == wavFormatPCM && bits == 8:
		bps = 1
		read = func(b []byte) float64 { return (float64(b[0]) - 128) / 128 }
	case formatCode == wavFormatPCM && bits == 16:
		bps = 2
		read = func(b []byte) float64 {
			return float64(int16(binary.LittleEndian.Uint16(b))) / 32768
		}
	case formatCode == wavFormatPCM && bits == 24:
		bps = 3
		read = func(b []byte) float64 {
			v := int32(b[0]) | int32(b[1])<<8 | int32(b[2])<<16
			v = v << 8 >> 8 // sign-extend
			return float64(v) / (1 << 23)
		}
	case formatCode == wavFormatPCM && bits == 32:
		bps = 4
		read = func(b []byte) float64 {
			return float64(int32(binary.LittleEndian.Uint32(b))) / (1 << 31)
		}
	case formatCode == wavFormatFloat && bits == 32:
		bps = 4
		read = func(b []byte) float64 {
			return float64(math.Float32frombits(binary.LittleEndian.Uint32(b)))
		}
	case formatCode == wavFormatFloat && bits == 64:
		bps = 8
		read = func(b []byte) float64 {
			return math.Float64frombits(binary.LittleEndian.Uint64(b))
		}
	default:
		return nil, fmt.Errorf("unsupported WAV encoding: format code %d at %d bits", formatCode, bits)
	}
	frameBytes := bps * channels
	frames := len(data) / frameBytes
	out := make([]float32, frames)
	for f := 0; f < frames; f++ {
		var sum float64
		base := f * frameBytes
		for c := 0; c < channels; c++ {
			sum += read(data[base+c*bps:])
		}
		out[f] = float32(sum / float64(channels))
	}
	return out, nil
}

// memWriteSeeker is an in-memory io.WriteSeeker for the WAV muxer,
// which back-patches its header sizes after the fact.
type memWriteSeeker struct {
	b   []byte
	pos int64
}

func (w *memWriteSeeker) Write(p []byte) (int, error) {
	if need := w.pos + int64(len(p)); need > int64(len(w.b)) {
		if need > int64(cap(w.b)) {
			// Grow geometrically: exact-size growth would copy the
			// whole buffer once per Write, quadratic across a decode.
			newCap := 2 * cap(w.b)
			if newCap < int(need) {
				newCap = int(need)
			}
			if newCap < 64<<10 {
				newCap = 64 << 10
			}
			grown := make([]byte, need, newCap)
			copy(grown, w.b)
			w.b = grown
		} else {
			w.b = w.b[:need]
		}
	}
	copy(w.b[w.pos:], p)
	w.pos += int64(len(p))
	return len(p), nil
}

func (w *memWriteSeeker) Seek(off int64, whence int) (int64, error) {
	switch whence {
	case io.SeekStart:
		w.pos = off
	case io.SeekCurrent:
		w.pos += off
	case io.SeekEnd:
		w.pos = int64(len(w.b)) + off
	default:
		return 0, fmt.Errorf("bad seek whence %d", whence)
	}
	if w.pos < 0 {
		return 0, fmt.Errorf("seek to negative offset %d", w.pos)
	}
	return w.pos, nil
}

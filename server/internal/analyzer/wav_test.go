package analyzer

import (
	"bytes"
	"encoding/binary"
	"math"
	"testing"
)

// wavPCM16 builds a minimal RIFF WAVE file from interleaved 16-bit
// PCM samples: the exact shape the server's analysis pull serves.
func wavPCM16(interleaved []int16, rate, channels int) []byte {
	dataLen := len(interleaved) * 2
	buf := &bytes.Buffer{}
	buf.WriteString("RIFF")
	binary.Write(buf, binary.LittleEndian, uint32(36+dataLen))
	buf.WriteString("WAVE")
	buf.WriteString("fmt ")
	binary.Write(buf, binary.LittleEndian, uint32(16))
	binary.Write(buf, binary.LittleEndian, uint16(wavFormatPCM))
	binary.Write(buf, binary.LittleEndian, uint16(channels))
	binary.Write(buf, binary.LittleEndian, uint32(rate))
	binary.Write(buf, binary.LittleEndian, uint32(rate*channels*2))
	binary.Write(buf, binary.LittleEndian, uint16(channels*2))
	binary.Write(buf, binary.LittleEndian, uint16(16))
	buf.WriteString("data")
	binary.Write(buf, binary.LittleEndian, uint32(dataLen))
	binary.Write(buf, binary.LittleEndian, interleaved)
	return buf.Bytes()
}

// toneInt16 synthesizes a sine at the given frequency, quantized to
// the 16-bit grid so WAV round trips compare exactly.
func toneInt16(freq float64, seconds float64, rate int) []int16 {
	n := int(seconds * float64(rate))
	out := make([]int16, n)
	step := 2 * math.Pi * freq / float64(rate)
	for i := range out {
		out[i] = int16(math.Round(0.5 * 32767 * math.Sin(step*float64(i))))
	}
	return out
}

func TestParseWAVRoundTripMono(t *testing.T) {
	src := toneInt16(440, 0.25, Rate)
	samples, rate, err := ParseWAV(wavPCM16(src, Rate, 1))
	if err != nil {
		t.Fatalf("ParseWAV: %v", err)
	}
	if rate != Rate {
		t.Fatalf("rate = %d, want %d", rate, Rate)
	}
	if len(samples) != len(src) {
		t.Fatalf("got %d samples, want %d", len(samples), len(src))
	}
	for i, s := range samples {
		// int16/32768 is exact in float32, so the trip loses nothing.
		if want := float32(float64(src[i]) / 32768); s != want {
			t.Fatalf("sample %d = %v, want %v", i, s, want)
		}
	}
}

func TestParseWAVDownmixesStereo(t *testing.T) {
	// Left constant +8192, right constant -4096: the mono mix is the
	// average, +2048.
	interleaved := make([]int16, 200)
	for i := 0; i < len(interleaved); i += 2 {
		interleaved[i] = 8192
		interleaved[i+1] = -4096
	}
	samples, rate, err := ParseWAV(wavPCM16(interleaved, 44100, 2))
	if err != nil {
		t.Fatalf("ParseWAV: %v", err)
	}
	if rate != 44100 {
		t.Fatalf("rate = %d, want 44100", rate)
	}
	if len(samples) != 100 {
		t.Fatalf("got %d frames, want 100", len(samples))
	}
	want := float32((8192.0/32768 - 4096.0/32768) / 2)
	for i, s := range samples {
		if s != want {
			t.Fatalf("frame %d = %v, want %v", i, s, want)
		}
	}
}

func TestParseWAVRejectsGarbage(t *testing.T) {
	if _, _, err := ParseWAV([]byte("definitely not a RIFF stream, not even close")); err == nil {
		t.Fatal("expected an error for non-WAV bytes")
	}
	if _, _, err := ParseWAV(nil); err == nil {
		t.Fatal("expected an error for empty input")
	}
}

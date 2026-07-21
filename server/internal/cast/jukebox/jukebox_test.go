package jukebox

import (
	"bytes"
	"encoding/binary"
	"testing"
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
	header, byteRate, bits, err := readWAVHeader(bytes.NewReader(raw))
	if err != nil {
		t.Fatal(err)
	}
	if byteRate != 176400 || bits != 16 {
		t.Fatalf("byteRate %d bits %d", byteRate, bits)
	}
	// The header bytes replay verbatim to the player, chunk walk and
	// all, ending right after the data chunk header.
	if !bytes.Equal(header, raw) {
		t.Fatalf("header %d bytes, want %d", len(header), len(raw))
	}

	if _, _, _, err := readWAVHeader(bytes.NewReader([]byte("not a wav at all"))); err == nil {
		t.Fatal("garbage accepted")
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

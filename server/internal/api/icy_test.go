package api

import (
	"bytes"
	"strings"
	"testing"
)

// icyWire builds a wire image: audio interleaved with metadata blocks
// every metaint bytes.
func icyWire(metaint int, audio []byte, blocks map[int]string) []byte {
	var out bytes.Buffer
	for start := 0; start < len(audio); start += metaint {
		end := min(start+metaint, len(audio))
		out.Write(audio[start:end])
		if end-start < metaint {
			break
		}
		meta := blocks[start/metaint]
		padded := len(meta)
		if padded%16 != 0 {
			padded += 16 - padded%16
		}
		out.WriteByte(byte(padded / 16))
		out.WriteString(meta)
		out.Write(make([]byte, padded-len(meta)))
	}
	return out.Bytes()
}

func TestICYRelayStripsMetadataAndReportsTitles(t *testing.T) {
	audio := []byte(strings.Repeat("abcdefgh", 100))
	wire := icyWire(64, audio, map[int]string{
		0: "StreamTitle='First Song';StreamUrl='';",
		2: "StreamTitle='Second Song';",
	})

	// Feed in awkward chunk sizes so runs and blocks span feeds.
	for _, chunk := range []int{1, 7, 64, 1000} {
		relay := newICYRelay(64)
		var got bytes.Buffer
		var titles []string
		for start := 0; start < len(wire); start += chunk {
			end := min(start+chunk, len(wire))
			relay.feed(wire[start:end], func(p []byte) {
				got.Write(p)
			}, func(block []byte) {
				if title, ok := icyStreamTitle(block); ok {
					titles = append(titles, title)
				}
			})
		}
		if !bytes.Equal(got.Bytes(), audio) {
			t.Fatalf("chunk %d: audio corrupted: got %d bytes, want %d", chunk, got.Len(), len(audio))
		}
		if len(titles) != 2 || titles[0] != "First Song" || titles[1] != "Second Song" {
			t.Fatalf("chunk %d: titles = %q", chunk, titles)
		}
	}
}

func TestICYStreamTitle(t *testing.T) {
	cases := []struct {
		name  string
		block string
		title string
		ok    bool
	}{
		{"plain", "StreamTitle='Artist - Song';StreamUrl='';", "Artist - Song", true},
		{"apostrophe", "StreamTitle='Don't Stop';StreamUrl='';", "Don't Stop", true},
		{"no url tail", "StreamTitle='Solo'", "Solo", true},
		{"cleared", "StreamTitle='';", "", true},
		{"absent", "StreamUrl='http://x';", "", false},
		{"empty block", "", "", false},
	}
	for _, tc := range cases {
		title, ok := icyStreamTitle([]byte(tc.block))
		if title != tc.title || ok != tc.ok {
			t.Errorf("%s: got (%q, %v), want (%q, %v)", tc.name, title, ok, tc.title, tc.ok)
		}
	}
	// Latin-1 bytes decode instead of mojibake: 0xE9 is e-acute.
	title, ok := icyStreamTitle([]byte("StreamTitle='Caf\xe9';"))
	if !ok || title != "Café" {
		t.Errorf("latin-1: got (%q, %v)", title, ok)
	}

	// Truncating a long valid-UTF-8 title must not cut inside a rune:
	// the partial rune drops, and the title stays UTF-8 instead of
	// falling through to the Latin-1 path as mojibake.
	long := "a" + strings.Repeat("€", 100) // 301 bytes; the cut at 300 splits the last euro
	title, ok = icyStreamTitle([]byte("StreamTitle='" + long + "';"))
	want := "a" + strings.Repeat("€", 99)
	if !ok || title != want {
		t.Errorf("truncation: got (%q..., %v), want %d clean euros", title[:12], ok, 99)
	}
}

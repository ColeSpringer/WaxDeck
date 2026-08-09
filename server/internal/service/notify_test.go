package service

import (
	"strings"
	"testing"
	"unicode/utf8"
)

func TestClipHealthMessageKeepsRuneBoundaries(t *testing.T) {
	t.Parallel()
	// A short message passes through untouched.
	if got := clipHealthMessage("boom"); got != "boom" {
		t.Fatalf("short clip = %q", got)
	}
	// A long ASCII message clips at the byte budget exactly.
	long := strings.Repeat("x", 400)
	if got := clipHealthMessage(long); len(got) != 300 {
		t.Fatalf("ascii clip = %d bytes, want 300", len(got))
	}
	// A multi-byte message never clips mid-rune: byte 300 lands inside
	// a euro sign (3 bytes each), and the stored string must stay
	// valid UTF-8 instead of rendering a replacement character in the
	// settings surface.
	multi := strings.Repeat("€", 200)
	got := clipHealthMessage(multi)
	if len(got) > 300 {
		t.Fatalf("multi-byte clip = %d bytes, want at most 300", len(got))
	}
	if !utf8.ValidString(got) {
		t.Fatalf("multi-byte clip is not valid UTF-8: %q", got[len(got)-6:])
	}
	if !strings.HasSuffix(got, "€") {
		t.Fatalf("multi-byte clip ends %q, want a whole rune", got[len(got)-3:])
	}
}

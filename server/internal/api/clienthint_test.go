package api

import (
	"testing"
	"unicode/utf8"
)

func TestSummarizeClient(t *testing.T) {
	cases := []struct {
		name, ua, want string
	}{
		{
			// The row that named this test: a device list that reads as
			// one long identical string per browser session.
			name: "chrome on windows",
			ua:   "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.7922.34 Safari/537.36",
			want: "Chrome on Windows",
		},
		{
			name: "firefox on linux",
			ua:   "Mozilla/5.0 (X11; Linux x86_64; rv:133.0) Gecko/20100101 Firefox/133.0",
			want: "Firefox on Linux",
		},
		{
			name: "safari on macos",
			ua:   "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15",
			want: "Safari on macOS",
		},
		{
			name: "safari on ios reports the phone, not the mac it claims",
			ua:   "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1",
			want: "Safari on iOS",
		},
		{
			// Every Chromium browser claims to be Chrome and Chrome
			// claims to be Safari, so these four are the ordering test.
			name: "edge is not chrome",
			ua:   "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0",
			want: "Edge on Windows",
		},
		{
			name: "opera is not chrome",
			ua:   "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 OPR/116.0.0.0",
			want: "Opera on Windows",
		},
		{
			name: "chrome on android is not linux",
			ua:   "Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36",
			want: "Chrome on Android",
		},
		{
			name: "chrome on ios is chrome, whatever webkit it is wearing",
			ua:   "Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/131.0.0.0 Mobile/15E148 Safari/604.1",
			want: "Chrome on iOS",
		},
		{
			// A real client names itself, so it is left alone: this is
			// the half of the device list that was already useful.
			name: "a subsonic client keeps its own name",
			ua:   "Symfonium/12.3.0",
			want: "Symfonium/12.3.0",
		},
		{
			name: "waxdeck's own native build keeps its own name",
			ua:   "WaxDeck/0.1.0 (Android)",
			want: "WaxDeck/0.1.0 (Android)",
		},
		{
			name: "an absent agent stores nothing rather than a word we made up",
			ua:   "",
			want: "",
		},
		{
			name: "whitespace is not an agent",
			ua:   "   ",
			want: "",
		},
		{
			// A browser marker with no platform it knows still beats
			// storing the whole header.
			name: "a browser on an unknown system is still named",
			ua:   "Mozilla/5.0 (Amiga) Firefox/1.0",
			want: "Firefox",
		},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := summarizeClient(c.ua); got != c.want {
				t.Fatalf("summarizeClient(%q) = %q, want %q", c.ua, got, c.want)
			}
		})
	}
}

// TestSummarizeClientIsIdempotent is what lets the read path summarize
// too, which is what makes sessions stored before this existed read the
// same as ones stored after.
func TestSummarizeClientIsIdempotent(t *testing.T) {
	for _, ua := range []string{
		"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.7922.34 Safari/537.36",
		"Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Mobile/15E148 Safari/604.1",
		"Symfonium/12.3.0",
		"",
	} {
		once := summarizeClient(ua)
		if twice := summarizeClient(once); twice != once {
			t.Fatalf("summarizeClient(%q) = %q, then %q", ua, once, twice)
		}
	}
}

// TestSummarizeClientBoundsAnUnknownAgent covers the fallback: an agent
// nothing recognizes is stored, so it has to be bounded and valid UTF-8
// whatever arrives in the header.
func TestSummarizeClientBoundsAnUnknownAgent(t *testing.T) {
	long := ""
	for len(long) < 400 {
		long += "sömething-"
	}
	got := summarizeClient(long)
	if len(got) > clientLabelMax {
		t.Fatalf("kept %d bytes, want at most %d", len(got), clientLabelMax)
	}
	// Cut on a rune boundary: the multi-byte character above is what
	// makes a naive byte slice produce invalid UTF-8.
	if !utf8.ValidString(got) {
		t.Fatalf("invalid UTF-8: %q", got)
	}
}

// TestSummarizeClientCleansAShortInvalidAgent is the case a bound alone
// misses. A header from a Latin-1 device is already under the cap, so
// anything that only validates what it truncated stores the bad bytes
// verbatim - in a TEXT column, and back out of the devices endpoint for
// as long as the session lives.
func TestSummarizeClientCleansAShortInvalidAgent(t *testing.T) {
	got := summarizeClient("\xffBot")
	if !utf8.ValidString(got) {
		t.Fatalf("invalid UTF-8 survived: %q", got)
	}
	// The readable half is kept rather than the whole value discarded:
	// the byte is dropped where it is, not trimmed off one end.
	if got != "Bot" {
		t.Fatalf("summarizeClient(%q) = %q, want %q", "\xffBot", got, "Bot")
	}
}

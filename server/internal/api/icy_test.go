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

func TestICYMeta(t *testing.T) {
	cases := []struct {
		name  string
		block string
		want  icyMeta
	}{
		{
			"a song with a cover",
			"StreamTitle='Artist - Song';StreamUrl='https://art.example/c.jpg';",
			icyMeta{title: "Artist - Song", titleOK: true, artURL: "https://art.example/c.jpg"},
		},
		{
			// The explicit key wins: StreamUrl predates anybody using it
			// for pictures and is as often a homepage as a cover.
			"artwork beats the older key",
			"StreamTitle='Artist - Song';StreamUrl='https://station.example/';StreamArtwork='https://art.example/c.jpg';",
			icyMeta{title: "Artist - Song", titleOK: true, artURL: "https://art.example/c.jpg"},
		},
		{
			"an empty artwork key falls back",
			"StreamTitle='Artist - Song';StreamArtwork='';StreamUrl='https://art.example/c.jpg';",
			icyMeta{title: "Artist - Song", titleOK: true, artURL: "https://art.example/c.jpg"},
		},
		{
			"a title announced with no picture",
			"StreamTitle='Artist - Song';StreamUrl='';",
			icyMeta{title: "Artist - Song", titleOK: true},
		},
		{
			// A block with a URL and no title is not an announcement.
			"a url on its own",
			"StreamUrl='https://art.example/c.jpg';",
			icyMeta{artURL: "https://art.example/c.jpg"},
		},
		{
			"an advertisement",
			"StreamTitle='Buy A Sofa';StreamUrl='https://sofa.example/banner.png';adw_ad='true';durationMilliseconds='30000';insertionType='preroll';",
			icyMeta{title: "Buy A Sofa", titleOK: true, artURL: "https://sofa.example/banner.png", ad: true},
		},
		{
			// The key rides along on songs too, so it is read rather
			// than merely looked for.
			"a song on a station that marks its ads",
			"StreamTitle='Artist - Song';adw_ad='false';",
			icyMeta{title: "Artist - Song", titleOK: true},
		},
		{"empty block", "", icyMeta{}},
	}
	for _, tc := range cases {
		got := icyMetaOf([]byte(tc.block))
		if got != tc.want {
			t.Errorf("%s: got %+v, want %+v", tc.name, got, tc.want)
		}
	}
}

// A block is a station's own text, and stations invent keys. A key that
// merely ends with a standard name is not that key, and reading it as
// one is a misread the station controls: the artwork URL this server
// goes and fetches, whether a song counts as an advertisement, and what
// the title says are all decided here.
func TestICYValueMatchesWholeFieldsOnly(t *testing.T) {
	cases := []struct {
		name  string
		block string
		want  icyMeta
	}{
		{
			// Would otherwise hand the artwork fetcher a beacon URL.
			"a vendor key ending in StreamUrl",
			"StreamTitle='Real Song';MyStreamUrl='http://tracker.example/beacon';",
			icyMeta{title: "Real Song", titleOK: true},
		},
		{
			"a vendor key ending in StreamArtwork",
			"StreamTitle='Real Song';TheirStreamArtwork='http://tracker.example/b.png';",
			icyMeta{title: "Real Song", titleOK: true},
		},
		{
			// Would otherwise drop an ordinary song off the face.
			"a vendor key ending in insertionType",
			"StreamTitle='Real Song';XinsertionType='none';",
			icyMeta{title: "Real Song", titleOK: true},
		},
		{
			"a vendor key ending in adw_ad",
			"StreamTitle='Real Song';no_adw_ad='true';",
			icyMeta{title: "Real Song", titleOK: true},
		},
		{
			// The decoy comes first, so a first-match parser reads it.
			"a decoy ahead of the real title",
			"NotAStreamTitle='decoy';StreamTitle='Real Song';",
			icyMeta{title: "Real Song", titleOK: true},
		},
		{
			"a decoy ahead of the real artwork",
			"StreamTitle='Real Song';MyStreamUrl='http://decoy.example/x';StreamUrl='http://art.example/c.jpg';",
			icyMeta{title: "Real Song", titleOK: true, artURL: "http://art.example/c.jpg"},
		},
		{
			// Stations pad between fields; a space is still a boundary.
			"space-separated fields still parse",
			"StreamTitle='Real Song'; StreamUrl='http://art.example/c.jpg';",
			icyMeta{title: "Real Song", titleOK: true, artURL: "http://art.example/c.jpg"},
		},
	}
	for _, tc := range cases {
		if got := icyMetaOf([]byte(tc.block)); got != tc.want {
			t.Errorf("%s: got %+v, want %+v", tc.name, got, tc.want)
		}
	}
}

// The insertion key rides ordinary programming on some platforms, so it
// is read for what it says rather than for being there at all. Getting
// this backwards is silent and total: a station sending the key on its
// songs would lose its titles, its announced artwork, and every scrobble
// for as long as it kept sending it.
func TestICYAdMarkersAreReadNotCounted(t *testing.T) {
	cases := []struct {
		name  string
		block string
		ad    bool
	}{
		{"a named ad break", "StreamTitle='Buy A Sofa';insertionType='preroll';", true},
		{"a midroll", "StreamTitle='Buy A Sofa';insertionType='midroll';", true},
		{"case and padding do not matter", "StreamTitle='Buy A Sofa';insertionType=' PostRoll ';", true},
		{"the boolean key on its own", "StreamTitle='Buy A Sofa';adw_ad='true';", true},
		// The important direction: an unrecognised value is a song.
		{"live insertion is programming", "StreamTitle='Real Song';insertionType='live';", false},
		{"a house value is programming", "StreamTitle='Real Song';insertionType='station_id';", false},
		{"an empty value is programming", "StreamTitle='Real Song';insertionType='';", false},
		{"the boolean saying no", "StreamTitle='Real Song';adw_ad='false';", false},
	}
	for _, tc := range cases {
		if got := icyMetaOf([]byte(tc.block)); got.ad != tc.ad {
			t.Errorf("%s: ad = %v, want %v", tc.name, got.ad, tc.ad)
		}
	}
}

// Stations wrap their blocks. A key after a line break is still a key,
// and missing that drops the announced cover and lets ad blocks through.
func TestICYValueAcceptsWrappedBlocks(t *testing.T) {
	block := "StreamTitle='Real Song';\r\nStreamUrl='https://art.example/c.jpg';\r\ninsertionType='midroll';"
	got := icyMetaOf([]byte(block))
	want := icyMeta{
		title:   "Real Song",
		titleOK: true,
		artURL:  "https://art.example/c.jpg",
		ad:      true,
	}
	if got != want {
		t.Fatalf("wrapped block = %+v, want %+v", got, want)
	}
}

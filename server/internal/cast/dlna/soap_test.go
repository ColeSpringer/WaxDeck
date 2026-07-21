package dlna

import (
	"context"
	"encoding/xml"
	"errors"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/cast/dlna/testrenderer"
	"github.com/colespringer/waxdeck/server/internal/connect"
)

func TestFormatHMS(t *testing.T) {
	cases := []struct {
		ms   int64
		want string
	}{
		{0, "0:00:00"},
		{5000, "0:00:05"},
		{65_000, "0:01:05"},
		{3_725_000, "1:02:05"},
		{36_005_000, "10:00:05"},
		{-100, "0:00:00"},
		{5900, "0:00:05"},
	}
	for _, c := range cases {
		if got := formatHMS(c.ms); got != c.want {
			t.Errorf("formatHMS(%d) = %q, want %q", c.ms, got, c.want)
		}
	}
}

func TestParseHMS(t *testing.T) {
	cases := []struct {
		in   string
		want int64
		ok   bool
	}{
		{"0:00:00", 0, true},
		{"0:00:05", 5000, true},
		{"1:02:05", 3_725_000, true},
		{"10:00:05", 36_005_000, true},
		{"0:00:01.500", 1500, true},
		{"0:00:01.5", 1500, true},
		{" 0:00:02 ", 2000, true},
		{"NOT_IMPLEMENTED", 0, false},
		{"", 0, false},
		{"1:02", 0, false},
		{"0:61:00", 0, false},
		{"abc", 0, false},
	}
	for _, c := range cases {
		got, ok := parseHMS(c.in)
		if got != c.want || ok != c.ok {
			t.Errorf("parseHMS(%q) = (%d, %v), want (%d, %v)", c.in, got, ok, c.want, c.ok)
		}
	}
}

func TestDIDLLiteEscaping(t *testing.T) {
	item := connect.MediaItem{
		PID:        "tr-01ARZ3NDEKTSV4RRFFQ69G5FAV",
		URL:        "http://waxdeck.local/stream?id=1&fmt=mp3",
		MimeType:   "audio/mpeg",
		Title:      "Rock & Roll <Part 1>",
		Artist:     "Simon & Garfunkel",
		DurationMS: 185_000,
	}
	didl := didlLite(item)
	if !strings.Contains(didl, "Rock &amp; Roll &lt;Part 1&gt;") {
		t.Errorf("title not escaped in %q", didl)
	}
	if !strings.Contains(didl, `protocolInfo="http-get:*:audio/mpeg:*"`) {
		t.Errorf("protocolInfo missing in %q", didl)
	}
	if !strings.Contains(didl, `duration="0:03:05"`) {
		t.Errorf("duration missing in %q", didl)
	}

	// The document must survive a real XML parse and round the escaped
	// fields back to their original text.
	var doc struct {
		Item struct {
			Title  string `xml:"title"`
			Artist string `xml:"artist"`
			Class  string `xml:"class"`
			Res    struct {
				ProtocolInfo string `xml:"protocolInfo,attr"`
				URL          string `xml:",chardata"`
			} `xml:"res"`
		} `xml:"item"`
	}
	if err := xml.Unmarshal([]byte(didl), &doc); err != nil {
		t.Fatalf("didl does not parse: %v", err)
	}
	if doc.Item.Title != item.Title {
		t.Errorf("title round trip = %q, want %q", doc.Item.Title, item.Title)
	}
	if doc.Item.Artist != item.Artist {
		t.Errorf("artist round trip = %q, want %q", doc.Item.Artist, item.Artist)
	}
	if doc.Item.Class != "object.item.audioItem.musicTrack" {
		t.Errorf("class = %q", doc.Item.Class)
	}
	if doc.Item.Res.URL != item.URL {
		t.Errorf("res url round trip = %q, want %q", doc.Item.Res.URL, item.URL)
	}
}

// TestSOAPRoundTrip exercises the client against the fake renderer's
// real envelopes: an action with arguments out and parsed response
// values back.
func TestSOAPRoundTrip(t *testing.T) {
	r := testrenderer.Start(t)
	cl := clientFor(t, r)
	ctx := context.Background()

	if err := cl.setURI(ctx, "http://media.local/a.mp3", ""); err != nil {
		t.Fatalf("setURI: %v", err)
	}
	if err := cl.play(ctx); err != nil {
		t.Fatalf("play: %v", err)
	}
	if err := cl.seek(ctx, 65_000); err != nil {
		t.Fatalf("seek: %v", err)
	}
	pos, err := cl.positionInfo(ctx)
	if err != nil {
		t.Fatalf("positionInfo: %v", err)
	}
	if pos.RelMS != 65_000 || !pos.RelKnown {
		t.Errorf("RelMS = %d (known %v), want 65000", pos.RelMS, pos.RelKnown)
	}
	if pos.Track != 1 || pos.TrackURI != "http://media.local/a.mp3" {
		t.Errorf("track = %d uri = %q", pos.Track, pos.TrackURI)
	}
	state, err := cl.transportState(ctx)
	if err != nil {
		t.Fatalf("transportState: %v", err)
	}
	if state != statePlaying {
		t.Errorf("state = %q, want PLAYING", state)
	}

	var seek *testrenderer.Action
	for _, a := range r.Actions() {
		if a.Name == "Seek" {
			seek = &a
			break
		}
	}
	if seek == nil {
		t.Fatal("renderer recorded no Seek")
	}
	if seek.Args["Unit"] != "REL_TIME" || seek.Args["Target"] != "0:01:05" {
		t.Errorf("seek args = %v", seek.Args)
	}
}

func TestSOAPFault(t *testing.T) {
	r := testrenderer.Start(t)
	cl := clientFor(t, r)
	httpc := &http.Client{Timeout: 5 * time.Second}
	_, err := soapCall(context.Background(), httpc, cl.desc.AVTransport, svcAVTransport, "Frobnicate", nil)
	if err == nil {
		t.Fatal("unknown action did not fault")
	}
	var upnp *UPnPError
	if !errors.As(err, &upnp) {
		t.Fatalf("error %v is no UPnPError", err)
	}
	if upnp.Code != 401 {
		t.Errorf("fault code = %d, want 401", upnp.Code)
	}
}

func TestProtocolInfo(t *testing.T) {
	r := testrenderer.Start(t)
	cl := clientFor(t, r)
	mimes, err := cl.protocolInfo(context.Background())
	if err != nil {
		t.Fatalf("protocolInfo: %v", err)
	}
	if len(mimes) != 2 || !mimes["audio/mpeg"] || !mimes["audio/wav"] {
		t.Errorf("sink mimes = %v, want audio/mpeg and audio/wav", mimes)
	}

	r.SetSink("http-get:*:audio/flac:*", "http-get:*:*:*")
	mimes, err = cl.protocolInfo(context.Background())
	if err != nil {
		t.Fatalf("protocolInfo: %v", err)
	}
	if len(mimes) != 1 || !mimes["audio/flac"] {
		t.Errorf("sink mimes = %v, want audio/flac only", mimes)
	}
}

// clientFor builds a control client from the fake renderer's own
// description document.
func clientFor(t *testing.T, r *testrenderer.Renderer) *client {
	t.Helper()
	desc, err := fetchDescription(context.Background(), r.Location())
	if err != nil {
		t.Fatalf("fetchDescription: %v", err)
	}
	return newClient(desc)
}

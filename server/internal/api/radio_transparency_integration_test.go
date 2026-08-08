package api

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strconv"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// icyStation describes a station the way the protocol does: a body of
// audio with a metadata block spliced in after every metaint bytes.
type icyStation struct {
	// audio is what a listener must receive, byte for byte.
	audio []byte
	// metaint is the audio-run length between metadata blocks; zero
	// makes a plain stream that announces nothing.
	metaint int
	// blocks are the metadata payloads keyed by which run they follow.
	// A run with no entry gets the zero-length block a station sends
	// when nothing has changed.
	blocks map[int]string
	// headers are sent ahead of the body; icy-metaint is added here.
	headers map[string]string
}

// icyStationServer serves one station in small flushed chunks whose size
// is coprime with metaint, so audio runs and metadata blocks land across
// read boundaries rather than arriving in one tidy buffer. That is the
// relay's actual working condition, and the state machine that spans
// reads is the part worth proving.
func icyStationServer(t *testing.T, st icyStation) *httptest.Server {
	t.Helper()
	wire := st.audio
	if st.metaint > 0 {
		wire = icyWire(st.metaint, st.audio, st.blocks)
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Icy-MetaData"); got != "1" {
			t.Errorf("station was asked with Icy-MetaData %q, want 1", got)
		}
		for k, v := range st.headers {
			w.Header().Set(k, v)
		}
		if st.metaint > 0 {
			w.Header().Set("icy-metaint", strconv.Itoa(st.metaint))
		}
		w.WriteHeader(http.StatusOK)
		rc := http.NewResponseController(w)
		const chunk = 777
		for off := 0; off < len(wire); off += chunk {
			if _, err := w.Write(wire[off:min(off+chunk, len(wire))]); err != nil {
				return
			}
			rc.Flush()
			// Separate reads on the far side, which one buffered write
			// would not produce.
			time.Sleep(time.Millisecond)
		}
	}))
	t.Cleanup(srv.Close)
	return srv
}

// icyTitleBlock is the metadata payload a station sends to announce a
// song.
func icyTitleBlock(title string) string { return "StreamTitle='" + title + "';" }

// synthesizedMP3 is a real encoded stream to relay, so the comparison is
// against audio rather than against a repeating test pattern that could
// survive a mangling by accident.
func synthesizedMP3(t *testing.T) []byte {
	t.Helper()
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "Relay Tone", Codec: fixtures.CodecMP3, Duration: 2 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	audio, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	if len(audio) < 8<<10 {
		t.Fatalf("fixture is %d bytes, too short to span metadata blocks", len(audio))
	}
	return audio
}

// radioTestStation registers a station and answers its play-info.
func radioTestStation(t *testing.T, h *harness, name, streamURL string) (string, RadioPlayInfo) {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/radio/stations", map[string]any{
		"name": name, "streamUrl": streamURL,
	})
	if resp.StatusCode != 201 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("create status = %d (%s)", resp.StatusCode, body)
	}
	st := decode[RadioStation](t, resp)
	pi := decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+st.Pid+"/play-info", h.token))
	return st.Pid, pi
}

// The relay does not transcode, resample, or rewrite anything: it
// de-interleaves the metadata the station asked it to carry and passes
// the audio through untouched. This is the standing answer to "is radio
// quality worse now" -- the bytes a listener receives are the bytes the
// station sent, so any difference heard is the station's own stream or
// the client's decoder, never this hop. The relay's other bounds (the
// per-account cap, the idle watchdog) end a stream; none of them alter
// one.
func TestRadioRelayIsBitTransparent(t *testing.T) {
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateRadioHosts = true
	})
	audio := synthesizedMP3(t)

	station := icyStationServer(t, icyStation{
		audio:   audio,
		metaint: 1024,
		blocks: map[int]string{
			0: icyTitleBlock("Fixture Artist - First Song"),
			3: icyTitleBlock("Fixture Artist - Second Song"),
		},
		headers: map[string]string{
			"icy-name":     "Transparency FM",
			"icy-br":       "128",
			"Content-Type": "audio/mpeg",
		},
	})

	pid, pi := radioTestStation(t, h, "Transparency FM", station.URL+"/stream")

	streamResp, err := http.Get(h.ts.URL + pi.Url)
	if err != nil {
		t.Fatal(err)
	}
	relayed, err := io.ReadAll(streamResp.Body)
	streamResp.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	if streamResp.StatusCode != 200 {
		t.Fatalf("relay status = %d", streamResp.StatusCode)
	}

	// The whole point: identical bytes, not merely a plausible length.
	if !bytes.Equal(relayed, audio) {
		t.Fatalf("relayed %d bytes, station sent %d; equal = %v",
			len(relayed), len(audio), bytes.Equal(relayed, audio))
	}

	// The metadata was consumed here, so a client must not be told to
	// expect it -- a client that honoured a forwarded icy-metaint would
	// carve audio out of a stream that no longer has blocks in it.
	if got := streamResp.Header.Get("Icy-Metaint"); got != "" {
		t.Fatalf("Icy-Metaint = %q, want it stripped", got)
	}
	// Everything else the station said about itself survives the hop.
	if got := streamResp.Header.Get("Icy-Name"); got != "Transparency FM" {
		t.Fatalf("Icy-Name = %q", got)
	}
	if got := streamResp.Header.Get("Icy-Br"); got != "128" {
		t.Fatalf("Icy-Br = %q, want the station's bitrate", got)
	}
	if got := streamResp.Header.Get("Content-Type"); got != "audio/mpeg" {
		t.Fatalf("Content-Type = %q", got)
	}
	if got := streamResp.Header.Get("Cache-Control"); got != "no-store" {
		t.Fatalf("Cache-Control = %q", got)
	}
	if got := streamResp.Header.Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("X-Content-Type-Options = %q", got)
	}

	// The metadata reached the server rather than the listener, and the
	// last announcement is the one reported: titles that arrive split
	// across reads are still read whole.
	after := decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+pid+"/play-info", h.token))
	if after.NowPlaying == nil || *after.NowPlaying != "Fixture Artist - Second Song" {
		t.Fatalf("nowPlaying = %v, want the second announced title", after.NowPlaying)
	}
}

// A station that announces nothing is relayed just as exactly; the
// pass-through path has no metadata state machine in it at all.
func TestRadioRelayIsBitTransparentWithoutMetadata(t *testing.T) {
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateRadioHosts = true
	})
	audio := synthesizedMP3(t)

	station := icyStationServer(t, icyStation{
		audio:   audio,
		headers: map[string]string{"icy-name": "Plain FM", "Content-Type": "audio/mpeg"},
	})

	pid, pi := radioTestStation(t, h, "Plain FM", station.URL+"/stream")

	streamResp, err := http.Get(h.ts.URL + pi.Url)
	if err != nil {
		t.Fatal(err)
	}
	relayed, err := io.ReadAll(streamResp.Body)
	streamResp.Body.Close()
	if err != nil {
		t.Fatal(err)
	}
	if streamResp.StatusCode != 200 {
		t.Fatalf("relay status = %d", streamResp.StatusCode)
	}
	if !bytes.Equal(relayed, audio) {
		t.Fatalf("relayed %d bytes, station sent %d", len(relayed), len(audio))
	}
	after := decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+pid+"/play-info", h.token))
	if after.NowPlaying != nil {
		t.Fatalf("nowPlaying = %q, want nothing from a station that announces nothing", *after.NowPlaying)
	}
}

// The rung this whole change exists for. A station announcing its own
// cover gets that cover drawn, with the external lookup off - because
// nothing about this library was sent anywhere to learn of it. The URL
// arrived down the stream the listener is already receiving, on the
// same footing the station's logo has always been fetched on.
func TestRadioAnnouncedArtIsServedWithoutTheExternalRung(t *testing.T) {
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateRadioHosts = true
	})
	cover := coverPNG(t)
	art := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "image/png")
		w.Write(cover)
	}))
	t.Cleanup(art.Close)

	station := icyStationServer(t, icyStation{
		audio:   synthesizedMP3(t),
		metaint: 1024,
		blocks: map[int]string{
			0: "StreamTitle='Fixture Artist - Announced Song';StreamUrl='" + art.URL + "/cover.png';",
		},
		headers: map[string]string{"icy-name": "Cover FM", "Content-Type": "audio/mpeg"},
	})

	pid, pi := radioTestStation(t, h, "Cover FM", station.URL+"/stream")
	streamResp, err := http.Get(h.ts.URL + pi.Url)
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, streamResp.Body)
	streamResp.Body.Close()

	// The fetch is started by a poll and lands on a later one, exactly
	// as the external rung does: no poll ever waits on a third party.
	var key string
	deadline := time.Now().Add(10 * time.Second)
	for key == "" {
		info := decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+pid+"/play-info", h.token))
		if info.NowPlaying == nil || *info.NowPlaying != "Fixture Artist - Announced Song" {
			t.Fatalf("nowPlaying = %v, want the announced title", info.NowPlaying)
		}
		if info.NowPlayingArtKey != nil {
			key = *info.NowPlayingArtKey
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the announced cover never became available")
		}
		time.Sleep(20 * time.Millisecond)
	}

	resp := get(t, h.ts, "/api/v1/radio/stations/"+pid+"/now-playing-art?v="+url.QueryEscape(key), h.token)
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("announced art status = %d (%s), want 200 with the external rung off", resp.StatusCode, body)
	}
	if !bytes.Equal(body, cover) {
		t.Fatalf("served %d bytes, want the %d the station pointed at", len(body), len(cover))
	}
	// Typed by what the bytes are, like every other picture served from
	// this origin, and hardened the same way.
	if got := resp.Header.Get("Content-Type"); got != "image/png" {
		t.Fatalf("Content-Type = %q", got)
	}
	if got := resp.Header.Get("X-Content-Type-Options"); got != "nosniff" {
		t.Fatalf("X-Content-Type-Options = %q", got)
	}
}

// An advertisement is not a song. The whole block is skipped, so the
// spot's own title and banner never reach a now-playing face and the
// song the station was playing stands.
func TestRadioAdBlocksLeaveTheTitleAlone(t *testing.T) {
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateRadioHosts = true
	})

	station := icyStationServer(t, icyStation{
		audio:   synthesizedMP3(t),
		metaint: 1024,
		blocks: map[int]string{
			0: "StreamTitle='Fixture Artist - Real Song';",
			3: "StreamTitle='Buy A Sofa';adw_ad='true';insertionType='preroll';StreamUrl='http://sofa.example/banner.png';",
		},
		headers: map[string]string{"icy-name": "Spot FM", "Content-Type": "audio/mpeg"},
	})

	pid, pi := radioTestStation(t, h, "Spot FM", station.URL+"/stream")
	streamResp, err := http.Get(h.ts.URL + pi.Url)
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, streamResp.Body)
	streamResp.Body.Close()

	info := decode[RadioPlayInfo](t, get(t, h.ts, "/api/v1/radio/stations/"+pid+"/play-info", h.token))
	if info.NowPlaying == nil || *info.NowPlaying != "Fixture Artist - Real Song" {
		t.Fatalf("nowPlaying = %v, want the song rather than the advertisement", info.NowPlaying)
	}
}

// A station that names its logo in its connect headers gets that logo,
// which beats going looking for one.
func TestRadioLogoHintFromConnectHeaders(t *testing.T) {
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.AllowPrivateRadioHosts = true
	})
	mark := coverPNG(t)
	logo := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "image/png")
		w.Write(mark)
	}))
	t.Cleanup(logo.Close)

	station := icyStationServer(t, icyStation{
		audio: synthesizedMP3(t),
		headers: map[string]string{
			"icy-name":     "Hinted FM",
			"icy-logo":     logo.URL + "/mark.png",
			"Content-Type": "audio/mpeg",
		},
	})

	// The station's row names no logo, so without the hint this would be
	// the discovery walk against a host that serves only audio.
	pid, pi := radioTestStation(t, h, "Hinted FM", station.URL+"/stream")
	streamResp, err := http.Get(h.ts.URL + pi.Url)
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, streamResp.Body)
	streamResp.Body.Close()

	resp := get(t, h.ts, "/api/v1/radio/stations/"+pid+"/logo", h.token)
	body, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("hinted logo status = %d (%s)", resp.StatusCode, body)
	}
	if !bytes.Equal(body, mark) {
		t.Fatalf("served %d bytes, want the %d the station named", len(body), len(mark))
	}
}

// coverPNG is a tiny real raster, so the sniffer and the endpoint agree
// it is a picture.
func coverPNG(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 24, 24))
	for y := range 24 {
		for x := range 24 {
			img.Set(x, y, color.RGBA{uint8(x * 10), uint8(y * 10), 200, 255})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

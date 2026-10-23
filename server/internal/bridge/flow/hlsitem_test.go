package flow

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
	"github.com/colespringer/waxdeck/server/internal/db"
)

// itemSign is one POST /sign the fake engine took.
type itemSign struct {
	Path       string            `json:"path"`
	Params     map[string]string `json:"params"`
	TTLSeconds int64             `json:"ttlSeconds"`
}

// itemSidecar is a fake engine that renders one source as HLS the way the
// real one does: /sign on the master path answers a URL whose v is the
// descriptor, and every child it lists carries that same v.
type itemSidecar struct {
	mu         sync.Mutex
	signs      []itemSign
	signedURLs []string
	streams    []url.Values
	masters    []url.Values
	children   []url.Values
	signStatus int // non-zero refuses every sign with it
	deadMaster int // non-zero answers every master fetch with it
	// overloaded answers every segment as an engine with no live slot
	// free does.
	overloaded bool
	// segments is how many segments the media playlist lists (one when
	// unset); breakMedia cuts the media playlist's connection mid-body.
	segments   int
	breakMedia bool
	// refusal, when set, answers every segment with that status and body,
	// as the engine refuses one whose file moved.
	refusal     int
	refusalBody string
}

// lastSignedURL answers the URL the last sign handed back.
func (s *itemSidecar) lastSignedURL(t *testing.T) string {
	t.Helper()
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.signedURLs) == 0 {
		t.Fatal("nothing was signed")
	}
	return s.signedURLs[len(s.signedURLs)-1]
}

func (s *itemSidecar) lastSign() itemSign {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.signs) == 0 {
		return itemSign{}
	}
	return s.signs[len(s.signs)-1]
}

// itemDescriptor is a single-source descriptor as the engine spells it.
type itemDescriptor struct {
	Ver      int    `json:"ver"`
	Src      string `json:"src,omitempty"`
	ID       string `json:"id,omitempty"`
	Tl       string `json:"tl,omitempty"`
	Format   string `json:"format"`
	Bitrate  int    `json:"bitrate,omitempty"`
	Gain     string `json:"gain,omitempty"`
	Dynamics string `json:"dynamics,omitempty"`
	From     int64  `json:"from,omitempty"`
	To       int64  `json:"to,omitempty"`
}

func (d itemDescriptor) encode() string {
	d.Ver = 1
	raw, _ := json.Marshal(d)
	return base64.RawURLEncoding.EncodeToString(raw)
}

// itemCaps is what the fake reports: HLS on in opus, flac and aac, with
// mp3 a progressive output only, and cuts in the two codecs the real
// engine moves (its cut rung needs a segmented form).
func itemCaps(hls bool, hlsFormats ...string) string {
	if len(hlsFormats) == 0 {
		hlsFormats = []string{"opus", "flac", "aac"}
	}
	formats, _ := json.Marshal(hlsFormats)
	return fmt.Sprintf(`{"schemaVersion":1,
		"outputs":[{"name":"flac","live":true},{"name":"opus","live":true},
			{"name":"mp3","live":true},{"name":"aac","live":true},{"name":"wav","live":true}],
		"delivery":{"progressive":true,"hls":%t,"hlsFormats":%s,"cutFormats":["opus","aac"],
			"timelines":true},
		"dsp":{"dynamics":["off","voice"],"gainMaxVoiceDb":24}}`, hls, formats)
}

// itemCapsWithoutOpus is an engine with no Opus at all, where a lossy
// encode the shape would put in MP3 has only AAC to segment into.
func itemCapsWithoutOpus() string {
	return `{"schemaVersion":1,
		"outputs":[{"name":"flac","live":true},{"name":"mp3","live":true},
			{"name":"aac","live":true},{"name":"wav","live":true}],
		"delivery":{"progressive":true,"hls":true,"hlsFormats":["flac","aac"],"cutFormats":["aac"]},
		"dsp":{"dynamics":["off","voice"],"gainMaxVoiceDb":24}}`
}

func (s *itemSidecar) handler(caps string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		s.mu.Lock()
		defer s.mu.Unlock()
		switch {
		case r.URL.Path == "/caps":
			fmt.Fprint(w, caps)
		case r.URL.Path == "/sign":
			var req itemSign
			json.NewDecoder(r.Body).Decode(&req)
			s.signs = append(s.signs, req)
			if s.signStatus != 0 {
				w.WriteHeader(s.signStatus)
				fmt.Fprint(w, `{"error":"no segmented form","code":"unsupported-format","schemaVersion":1}`)
				return
			}
			p := req.Params
			d := itemDescriptor{Src: p["src"], ID: "5-1", Tl: p["tl"], Format: p["format"],
				Gain: p["gain"], Dynamics: p["dynamics"]}
			d.Bitrate, _ = strconv.Atoi(p["bitrate"])
			d.From, _ = strconv.ParseInt(p["from"], 10, 64)
			d.To, _ = strconv.ParseInt(p["to"], 10, 64)
			if d.Tl != "" {
				d.ID = ""
			}
			exp := time.Now().Add(time.Duration(req.TTLSeconds) * time.Second).Unix()
			q := url.Values{"v": {d.encode()}, "exp": {fmt.Sprint(exp)}, "kid": {"k1"}, "sig": {"mastersig"}}
			s.signedURLs = append(s.signedURLs, req.Path+"?"+q.Encode())
			json.NewEncoder(w).Encode(map[string]any{"schemaVersion": 1, "url": req.Path + "?" + q.Encode(), "exp": exp})
		case r.URL.Path == "/hls/timeline":
			w.WriteHeader(http.StatusCreated)
			json.NewEncoder(w).Encode(map[string]any{
				"schemaVersion": 1, "tl": "digest123", "members": 1, "durationSeconds": 60.0, "envelopeRate": 44100,
				"boundaries": []map[string]int64{{"offsetSamples": 0, "durationSamples": 2646000}},
			})
		case r.URL.Path == "/hls/master.m3u8":
			s.masters = append(s.masters, r.URL.Query())
			if r.Header.Get("X-API-Key") != "" || r.URL.Query().Get("sig") == "" {
				http.Error(w, "unsigned", http.StatusUnauthorized)
				return
			}
			if s.deadMaster != 0 {
				http.Error(w, `{"error":"gone","code":"not-found"}`, s.deadMaster)
				return
			}
			w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
			fmt.Fprintf(w, "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=96000,CODECS=\"opus\"\nmedia.m3u8?v=%s&kid=k1&sig=child\n",
				r.URL.Query().Get("v"))
		case r.URL.Path == "/hls/media.m3u8":
			s.children = append(s.children, r.URL.Query())
			v := r.URL.Query().Get("v")
			w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
			fmt.Fprintf(w, "#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4?v=%s&sig=init\"\n", v)
			for n := range max(s.segments, 1) {
				fmt.Fprintf(w, "#EXTINF:4.0,\nseg/%d.m4s?v=%s&sig=seg%d\n", n, v, n)
				if s.breakMedia && n == 100 {
					w.(http.Flusher).Flush()
					panic(http.ErrAbortHandler)
				}
			}
			fmt.Fprint(w, "#EXT-X-ENDLIST\n")
		case r.URL.Path == "/hls/init.mp4" || strings.HasPrefix(r.URL.Path, "/hls/seg/"):
			s.children = append(s.children, r.URL.Query())
			if s.refusal != 0 && strings.HasPrefix(r.URL.Path, "/hls/seg/") {
				w.Header().Set("Content-Type", "application/json")
				w.WriteHeader(s.refusal)
				fmt.Fprint(w, s.refusalBody)
				return
			}
			if s.overloaded && strings.HasPrefix(r.URL.Path, "/hls/seg/") {
				w.Header().Set("Content-Type", "application/json")
				w.Header().Set("Retry-After", "2")
				w.WriteHeader(http.StatusServiceUnavailable)
				fmt.Fprint(w, `{"error":"live transcode slots are full","code":"overloaded","schemaVersion":1}`)
				return
			}
			if r.Header.Get("X-API-Key") != "" {
				http.Error(w, "unexpected api key", http.StatusBadRequest)
				return
			}
			w.Header().Set("Content-Type", "audio/mp4")
			fmt.Fprint(w, "fmp4bytes")
		case r.URL.Path == "/stream":
			s.streams = append(s.streams, r.URL.Query())
			fmt.Fprint(w, "audio")
		default:
			http.NotFound(w, r)
		}
	}
}

// newItemHLSBridge builds a bridge over the fake engine for one source.
func newItemHLSBridge(t *testing.T, src Source, caps string, store TimelineStore) (*Bridge, *itemSidecar, *fakeGate) {
	t.Helper()
	return newItemHLSBridgeAt(t, filepath.Dir(src.Path), src, caps, store)
}

// newItemHLSBridgeAt is newItemHLSBridge with the library root named.
func newItemHLSBridgeAt(t *testing.T, root string, src Source, caps string, store TimelineStore) (*Bridge, *itemSidecar, *fakeGate) {
	t.Helper()
	sc := &itemSidecar{}
	srv := httptest.NewServer(sc.handler(caps))
	t.Cleanup(srv.Close)
	b, err := New(context.Background(), Config{
		BaseURL:   srv.URL,
		APIKey:    "key",
		Roots:     []Root{{Name: "lib", Path: root}},
		Tokens:    auth.NewMediaTokens([]byte("test-secret-test-secret-test-sec"), 0),
		Resolver:  staticResolver{src},
		Timelines: store,
	})
	if err != nil {
		t.Fatal(err)
	}
	connect(t, b)
	gate := &fakeGate{}
	b.SetTranscodeGate(gate)
	return b, sc, gate
}

func serveHLS(b *Bridge, u string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	b.ServeHLS(rec, httptest.NewRequest(http.MethodGet, u, nil))
	return rec
}

// playlistChild answers the proxied URL of the first child a playlist
// names whose URI starts with prefix, on a line or in a URI attribute.
func playlistChild(t *testing.T, body, prefix string) string {
	t.Helper()
	for _, line := range strings.Split(body, "\n") {
		if strings.HasPrefix(line, prefix) {
			return "/media/hls/" + line
		}
		if i := strings.Index(line, `URI="`+prefix); i >= 0 {
			rest := line[i+len(`URI="`):]
			return "/media/hls/" + rest[:strings.Index(rest, `"`)]
		}
	}
	t.Fatalf("no %s child in %q", prefix, body)
	return ""
}

// A long lossless file, so a capped render of it is a real encode.
var longHLSFLAC = Source{Codec: "flac", Container: "flac", BitrateKbps: 900, DurationMS: 2 * 60 * 60 * 1000}

// A caller that plays HLS gets the encode a stream would have been as one
// item's HLS presentation: seekable, never cut, sized to its length, and
// signed upstream with the encode the live stream would have carried.
func TestPlayInfoRendersAReencodeAsHLSForACallerThatPlaysIt(t *testing.T) {
	b, sc, gate := newItemHLSBridge(t, cutSource(t, "song.flac", longHLSFLAC), itemCaps(true), nil)
	before := time.Now()
	info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X",
		PlayOptions{Cred: "se:1", MaxBitrateKbps: 96, StartMS: 90_500, HLS: true})
	if err != nil {
		t.Fatal(err)
	}
	u, err := url.Parse(info.URL)
	if err != nil {
		t.Fatal(err)
	}
	if u.Path != "/media/hls/master.m3u8" || u.Query().Get("it") == "" || u.Query().Get("mt") == "" || u.Query().Has("t") {
		t.Fatalf("url %s, want an uncut item rendering on the HLS surface", info.URL)
	}
	if info.MimeType != "application/vnd.apple.mpegurl" || !info.Seekable || info.StartOffsetMS != 0 {
		t.Fatalf("info %+v, want a seekable HLS presentation with no cut", info)
	}
	if info.DurationMS != longHLSFLAC.DurationMS || info.AppliedBitrateKbps != 96 {
		t.Fatalf("duration %d applied %d, want the item's length at the cap", info.DurationMS, info.AppliedBitrateKbps)
	}
	// The token outlives a listen of the whole item, as a timeline's does.
	ttl := 2*time.Hour + 15*time.Minute
	if info.ExpiresAt.Before(before.Add(ttl-time.Minute)) || info.ExpiresAt.After(time.Now().Add(ttl+time.Minute)) {
		t.Fatalf("expires %v, want about %v from now", info.ExpiresAt, ttl)
	}
	sign := sc.lastSign()
	if sign.Path != "/hls/master.m3u8" || sign.TTLSeconds != int64(ttl/time.Second) {
		t.Fatalf("sign %+v, want the master signed for %v", sign, ttl)
	}
	want := map[string]string{"src": "lib/song.flac", "format": "opus", "bitrate": "96"}
	if fmt.Sprint(sign.Params) != fmt.Sprint(want) {
		t.Fatalf("signed params %v, want %v", sign.Params, want)
	}
	// Nothing is charged until the presentation is fetched.
	if gate.acquired != 0 {
		t.Fatalf("the mint took %d slots, want none", gate.acquired)
	}
}

// The rendering carries the encode the live stream would have: the
// shape's own format where it has a segmented form, lossless kept
// lossless, the boost's gain and dynamics, a carved track's window and
// the account's ceiling.
func TestPlayInfoHLSCarriesTheEncodeTheStreamWouldGet(t *testing.T) {
	lufs := -20.0
	for name, c := range map[string]struct {
		src     Source
		opts    PlayOptions
		ceiling int
		caps    string
		want    map[string]string
	}{
		"voice boost": {
			src:  Source{Codec: "mp3", Container: "mp3", BitrateKbps: 64, DurationMS: 600_000, SpokenWord: true, IntegratedLUFS: &lufs},
			opts: PlayOptions{VoiceBoost: true},
			want: map[string]string{"src": "lib/a", "format": "opus", "gain": "4.0", "dynamics": "voice"},
		},
		"voice boost under a ceiling": {
			src:     Source{Codec: "flac", Container: "flac", DurationMS: 600_000, SpokenWord: true, IntegratedLUFS: &lufs},
			opts:    PlayOptions{VoiceBoost: true},
			ceiling: 64,
			want:    map[string]string{"src": "lib/a", "format": "opus", "bitrate": "64", "gain": "4.0", "dynamics": "voice"},
		},
		"a lossless carved track": {
			src:  Source{Codec: "flac", Container: "flac", DurationMS: 200_000, Virtual: true, FromSample: 441000, ToSample: 9261000},
			want: map[string]string{"src": "lib/a", "format": "flac", "from": "441000", "to": "9261000"},
		},
		"a carved track the engine moves": {
			src:  Source{Codec: "aac", Container: "mp4", DurationMS: 200_000, Virtual: true, FromSample: 441000},
			want: map[string]string{"src": "lib/a", "format": "aac", "from": "441000"},
		},
		"a carved track in a codec the engine does not cut": {
			src:  Source{Codec: "mp3", Container: "mp3", DurationMS: 200_000, Virtual: true, FromSample: 441000, ToSample: 9261000},
			want: map[string]string{"src": "lib/a", "format": "opus", "from": "441000", "to": "9261000"},
		},
		"a lossy encode on an engine without opus": {
			src:  Source{Codec: "mp3", Container: "mp3", DurationMS: 200_000, Virtual: true, FromSample: 441000},
			caps: itemCapsWithoutOpus(),
			want: map[string]string{"src": "lib/a", "format": "aac", "from": "441000"},
		},
	} {
		t.Run(name, func(t *testing.T) {
			caps := c.caps
			if caps == "" {
				caps = itemCaps(true)
			}
			b, sc, _ := newItemHLSBridge(t, cutSource(t, "a", c.src), caps, nil)
			b.SetTranscodeGate(&fakeGate{ceiling: c.ceiling})
			c.opts.HLS = true
			info, err := b.PlayInfoFor(context.Background(), "us-1", "ep-X", c.opts)
			if err != nil {
				t.Fatal(err)
			}
			if !strings.HasPrefix(info.URL, "/media/hls/master.m3u8?") || !info.Seekable {
				t.Fatalf("info %+v, want an HLS rendering", info)
			}
			if got := sc.lastSign().Params; fmt.Sprint(got) != fmt.Sprint(c.want) {
				t.Fatalf("signed params %v, want %v", got, c.want)
			}
		})
	}
}

// Where no rendering can serve, the stream is what it always was: a
// caller that does not play HLS, a sidecar that renders none, an original
// the client seeks itself, lossless with no lossless segmented form, and
// an engine that refuses the sign.
func TestPlayInfoKeepsTheCutWhereHLSCannotServe(t *testing.T) {
	carvedFLAC := Source{Codec: "flac", Container: "flac", DurationMS: 200_000, Virtual: true, FromSample: 441000}
	for name, c := range map[string]struct {
		src        Source
		caps       string
		opts       PlayOptions
		signStatus int
		seekable   bool
	}{
		"a caller that does not play HLS": {
			src: longFLAC, caps: itemCaps(true), opts: PlayOptions{MaxBitrateKbps: 96, StartMS: 90_500}},
		"a sidecar that renders no HLS": {
			src: longFLAC, caps: itemCaps(false), opts: PlayOptions{MaxBitrateKbps: 96, StartMS: 90_500, HLS: true}},
		"an original": {
			src: longFLAC, caps: itemCaps(true), opts: PlayOptions{StartMS: 90_500, HLS: true}, seekable: true},
		"lossless with no lossless segmented form": {
			src: carvedFLAC, caps: itemCaps(true, "aac", "opus"), opts: PlayOptions{StartMS: 90_500, HLS: true}},
		"an engine that will not sign it": {
			src: longFLAC, caps: itemCaps(true), opts: PlayOptions{MaxBitrateKbps: 96, StartMS: 90_500, HLS: true},
			signStatus: http.StatusUnprocessableEntity},
	} {
		t.Run(name, func(t *testing.T) {
			b, sc, _ := newItemHLSBridge(t, cutSource(t, "song.flac", c.src), c.caps, nil)
			sc.signStatus = c.signStatus
			info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", c.opts)
			if err != nil {
				t.Fatal(err)
			}
			if !strings.HasPrefix(info.URL, "/media/stream?") || info.Seekable != c.seekable {
				t.Fatalf("info %+v, want the progressive stream", info)
			}
			if !c.seekable && (!strings.Contains(info.URL, "&t=90") || info.StartOffsetMS != 90_000) {
				t.Fatalf("url %s offset %d, want the cut at 90 s", info.URL, info.StartOffsetMS)
			}
			ts := b.timelines()
			ts.mu.Lock()
			rows := len(ts.stash)
			ts.mu.Unlock()
			if rows != 0 {
				t.Fatalf("%d renderings stashed, want none", rows)
			}
		})
	}
}

// The presentation plays through this origin: the master from the
// stashed signature, every child under the same token, the bytes as the
// engine wrote them, and each fetch asks the gate about the item.
func TestServeHLSPlaysAnItemRendering(t *testing.T) {
	b, sc, gate := newItemHLSBridge(t, cutSource(t, "song.flac", longHLSFLAC), itemCaps(true), nil)
	info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{Cred: "se:1", MaxBitrateKbps: 96, HLS: true})
	if err != nil {
		t.Fatal(err)
	}
	mt := url.QueryEscape(mustQuery(t, info.URL).Get("mt"))

	master := serveHLS(b, info.URL)
	if master.Code != http.StatusOK {
		t.Fatalf("master = %d: %s", master.Code, master.Body.String())
	}
	if got := sc.masters[0]; got.Get("sig") != "mastersig" || got.Get("v") == "" {
		t.Fatalf("the engine's master was asked as %v, want the stashed signature", got)
	}
	if !strings.Contains(master.Body.String(), "\nmedia.m3u8?c=") || !strings.Contains(master.Body.String(), "&mt="+mt) {
		t.Fatalf("master children not sealed under the token: %s", master.Body.String())
	}
	media := serveHLS(b, playlistChild(t, master.Body.String(), "media.m3u8"))
	if media.Code != http.StatusOK {
		t.Fatalf("media = %d: %s", media.Code, media.Body.String())
	}
	for _, prefix := range []string{"init.mp4", "seg/0.m4s"} {
		u := playlistChild(t, media.Body.String(), prefix)
		if !strings.HasSuffix(u, "&mt="+mt) {
			t.Fatalf("%s child %s not stamped", prefix, u)
		}
		if rec := serveHLS(b, u); rec.Code != http.StatusOK || rec.Body.String() != "fmp4bytes" {
			t.Fatalf("%s = %d %q", prefix, rec.Code, rec.Body.String())
		}
	}
	if len(gate.authorized) != 4 {
		t.Fatalf("the gate was asked %d times, want once a fetch", len(gate.authorized))
	}
	for _, c := range gate.authorized {
		if c.User != "us-1" || c.Cred != "se:1" || c.Purpose != auth.PurposeHLS || c.PID != "tr-X" {
			t.Fatalf("the gate was asked about %+v, want the item under its session", c)
		}
	}
}

// A segment the engine refuses for want of a live slot answers what the
// same item's stream answers: one busy code whichever route was handed
// out.
func TestServeHLSSaysTheEngineIsBusyAsAStreamDoes(t *testing.T) {
	b, sc, _ := newItemHLSBridge(t, cutSource(t, "song.flac", longHLSFLAC), itemCaps(true), nil)
	info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{MaxBitrateKbps: 96, HLS: true})
	if err != nil {
		t.Fatal(err)
	}
	master := serveHLS(b, info.URL)
	media := serveHLS(b, playlistChild(t, master.Body.String(), "media.m3u8"))
	sc.mu.Lock()
	sc.overloaded = true
	sc.mu.Unlock()
	rec := serveHLS(b, playlistChild(t, media.Body.String(), "seg/0.m4s"))
	wantEnvelope(t, rec, http.StatusTooManyRequests, "transcode-limited")
	if got := rec.Header().Get("Retry-After"); got != "2" {
		t.Fatalf("Retry-After = %q, want the engine's 2", got)
	}
}

// childURIs answers every child URI a playlist names, on a line or in a
// URI attribute.
func childURIs(body string) []string {
	var out []string
	for _, line := range strings.Split(body, "\n") {
		switch {
		case strings.Contains(line, `URI="`):
			rest := line[strings.Index(line, `URI="`)+len(`URI="`):]
			out = append(out, rest[:strings.Index(rest, `"`)])
		case line != "" && !strings.HasPrefix(line, "#"):
			out = append(out, line)
		}
	}
	return out
}

// A presentation's URLs say nothing of the file it renders: no library
// path, no folder, no size or modification time, none of the engine's
// own parameters. Each child carries the token and an opaque reference,
// and still plays.
func TestHLSChildURLsShowNothingOfTheFile(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, "Artist Name", "Album Title (2001)")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	src := longHLSFLAC
	src.Path, src.Size, src.MTimeNS = filepath.Join(dir, "01 Track Title.flac"), 5, 1
	if err := os.WriteFile(src.Path, []byte("audio"), 0o644); err != nil {
		t.Fatal(err)
	}
	b, sc, _ := newItemHLSBridgeAt(t, root, src, itemCaps(true), nil)
	info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{MaxBitrateKbps: 96, HLS: true})
	if err != nil {
		t.Fatal(err)
	}
	upstreamV := mustQuery(t, sc.lastSignedURL(t)).Get("v")
	master := serveHLS(b, info.URL)
	media := serveHLS(b, playlistChild(t, master.Body.String(), "media.m3u8"))
	if master.Code != http.StatusOK || media.Code != http.StatusOK {
		t.Fatalf("master %d media %d", master.Code, media.Code)
	}
	var children []string
	for _, body := range []string{master.Body.String(), media.Body.String()} {
		children = append(children, childURIs(body)...)
	}
	if len(children) != 3 {
		t.Fatalf("children %q, want the media playlist, the init header and a segment", children)
	}
	mt := mustQuery(t, info.URL).Get("mt")
	paths := []string{}
	for _, child := range children {
		path, _, _ := strings.Cut(child, "?")
		paths = append(paths, path)
		q := mustQuery(t, child)
		if len(q) != 2 || q.Get("c") == "" || q.Get("mt") != mt {
			t.Errorf("child %q, want only an opaque reference and the token", child)
		}
		sealed, err := base64.RawURLEncoding.DecodeString(q.Get("c"))
		if err != nil {
			t.Errorf("child %q: reference is not base64url: %v", child, err)
		}
		// Long, distinctive strings only: the reference is ciphertext, and
		// a short word turns up in random base64 now and then. The query's
		// keys above already rule out a signature riding along.
		for _, leak := range []string{upstreamV, "Artist Name/Album Title (2001)/01 Track Title.flac"} {
			if strings.Contains(q.Get("c"), leak) || strings.Contains(string(sealed), leak) {
				t.Errorf("child %q carries %q", child, leak)
			}
		}
		if rec := serveHLS(b, "/media/hls/"+child); rec.Code != http.StatusOK {
			t.Errorf("child %q = %d: %s", child, rec.Code, rec.Body.String())
		}
	}
	if fmt.Sprint(paths) != "[media.m3u8 init.mp4 seg/0.m4s]" {
		t.Errorf("child paths %v, want the engine's own names and nothing more", paths)
	}
	// The engine was asked with its own signed query, untouched.
	sc.mu.Lock()
	defer sc.mu.Unlock()
	if len(sc.children) < 3 {
		t.Fatalf("the engine saw %d child fetches, want every child's", len(sc.children))
	}
	for _, q := range sc.children {
		if q.Get("v") != upstreamV || q.Get("sig") == "" || q.Has("mt") || q.Has("c") {
			t.Errorf("the engine was asked %v", q)
		}
	}
}

// A timeline segment the engine refuses for want of a live slot reaches
// hls.js as the engine's 503, which it retries; a 429 it would not retry,
// and the web player reads 429 as the session cap.
func TestServeHLSLeavesATimelinesBusyEngineRetryable(t *testing.T) {
	inner := timelineSidecarMux(t)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/hls/seg/0.m4s" {
			w.Header().Set("Content-Type", "application/json")
			w.Header().Set("Retry-After", "2")
			w.WriteHeader(http.StatusServiceUnavailable)
			fmt.Fprint(w, `{"error":"live transcode slots are full","code":"overloaded","schemaVersion":1}`)
			return
		}
		inner.ServeHTTP(w, r)
	}))
	t.Cleanup(srv.Close)
	dir := t.TempDir()
	path := filepath.Join(dir, "one.flac")
	if err := os.WriteFile(path, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	b, err := New(context.Background(), Config{
		BaseURL: srv.URL, APIKey: "key", Roots: []Root{{Name: "lib", Path: dir}},
		Tokens: auth.NewMediaTokens([]byte("test-secret"), 0),
	})
	if err != nil {
		t.Fatal(err)
	}
	connect(t, b)
	b.SetTranscodeGate(&fakeGate{})
	res, err := b.TimelineFor(context.Background(), "us-alice",
		[]TimelineMember{{PID: "tr-one", Src: Source{Path: path, DurationMS: 60000}}}, TimelineOptions{})
	if err != nil {
		t.Fatal(err)
	}
	master := serveHLS(b, res.URL)
	media := serveHLS(b, playlistChild(t, master.Body.String(), "media.m3u8"))
	rec := serveHLS(b, playlistChild(t, media.Body.String(), "seg/0.m4s"))
	wantEnvelope(t, rec, http.StatusServiceUnavailable, "internal")
	if got := rec.Header().Get("Retry-After"); got != "2" {
		t.Fatalf("Retry-After = %q, want the engine's 2", got)
	}
}

// A child the engine refuses answers in the API's envelope, never the
// engine's own body, which names the file it could not open; the status
// a player acts on stays.
func TestHLSChildRefusalsNameNothingOfTheFile(t *testing.T) {
	const moved = `{"error":"source: no such file: openat Artist Name/Album Title (2001)/01 Track Title.flac: no such file or directory","code":"not-found","schemaVersion":1}`
	for name, c := range map[string]struct {
		status     int
		body       string
		wantStatus int
		wantCode   string
	}{
		"a file that moved":          {http.StatusNotFound, moved, http.StatusNotFound, "not-found"},
		"a lapsed signature":         {http.StatusForbidden, `{"error":"signature expired for lib/Artist Name","code":"signature-expired"}`, http.StatusUnauthorized, "unauthenticated"},
		"a file it cannot read":      {http.StatusInternalServerError, `{"error":"source: open Artist Name/x.flac: permission denied","code":"source-unreadable"}`, http.StatusInternalServerError, "internal"},
		"a request it will not take": {http.StatusBadRequest, `{"error":"segment Artist Name","code":"invalid-request"}`, http.StatusBadRequest, "invalid-request"},
	} {
		t.Run(name, func(t *testing.T) {
			b, sc, _ := newItemHLSBridge(t, cutSource(t, "song.flac", longHLSFLAC), itemCaps(true), nil)
			info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{MaxBitrateKbps: 96, HLS: true})
			if err != nil {
				t.Fatal(err)
			}
			master := serveHLS(b, info.URL)
			media := serveHLS(b, playlistChild(t, master.Body.String(), "media.m3u8"))
			sc.mu.Lock()
			sc.refusal, sc.refusalBody = c.status, c.body
			sc.mu.Unlock()
			rec := serveHLS(b, playlistChild(t, media.Body.String(), "seg/0.m4s"))
			wantEnvelope(t, rec, c.wantStatus, c.wantCode)
			for _, leak := range []string{"Artist", "openat", "source", "signature-expired"} {
				if strings.Contains(rec.Body.String(), leak) {
					t.Errorf("answer %q carries %q", rec.Body.String(), leak)
				}
			}
		})
	}
}

// A playlist fetched again under one token lists the same URIs: what a
// player or a cache in between holds for one still names the bytes the
// other names. Another token's lists others.
func TestAPlaylistFetchedAgainListsTheSameURIs(t *testing.T) {
	b, sc, _ := newItemHLSBridge(t, cutSource(t, "song.flac", longHLSFLAC), itemCaps(true), nil)
	sc.segments = 50
	mint := func(cred string) (url, master string) {
		info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{Cred: cred, MaxBitrateKbps: 96, HLS: true})
		if err != nil {
			t.Fatal(err)
		}
		return info.URL, serveHLS(b, info.URL).Body.String()
	}
	url, master := mint("se:1")
	if again := serveHLS(b, url).Body.String(); again != master {
		t.Fatalf("one token's master listed other URIs the second time:\n%s\nthen\n%s", master, again)
	}
	child := playlistChild(t, master, "media.m3u8")
	first, again := serveHLS(b, child), serveHLS(b, child)
	if first.Code != http.StatusOK || again.Code != http.StatusOK {
		t.Fatalf("media = %d, then %d", first.Code, again.Code)
	}
	if first.Body.String() != again.Body.String() {
		t.Fatalf("one token's playlist listed other URIs the second time:\n%s\nthen\n%s", first.Body.String(), again.Body.String())
	}
	if _, other := mint("se:2"); playlistChild(t, other, "media.m3u8") == child {
		t.Fatal("another token's master listed the same media URI")
	}
}

// A playlist of any length goes out whole: a long single-file book lists
// tens of thousands of segments, and one cut short loses its tail and its
// ENDLIST, which a player reads as a live playlist to wait on.
func TestServeHLSServesAPlaylistOfAnyLength(t *testing.T) {
	b, sc, _ := newItemHLSBridge(t, cutSource(t, "song.flac", longHLSFLAC), itemCaps(true), nil)
	// Past the old 8 MiB cap upstream as well as handed out.
	sc.segments = 80_000
	info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{MaxBitrateKbps: 96, HLS: true})
	if err != nil {
		t.Fatal(err)
	}
	master := serveHLS(b, info.URL)
	media := serveHLS(b, playlistChild(t, master.Body.String(), "media.m3u8"))
	if media.Code != http.StatusOK {
		t.Fatalf("media = %d", media.Code)
	}
	body := media.Body.String()
	if len(body) <= 8<<20 {
		t.Fatalf("playlist is %d bytes, want one past the old 8 MiB cap", len(body))
	}
	if !strings.HasSuffix(body, "#EXT-X-ENDLIST\n") || !strings.Contains(body, "\nseg/79999.m4s?c=") {
		t.Fatalf("playlist of %d bytes lost its tail: ...%s", len(body), body[len(body)-200:])
	}
}

// A playlist the engine breaks off mid-body is not handed on as a shorter
// one: the answer is torn down, as a player has to see it.
func TestServeHLSTearsDownAPlaylistTheEngineBreaksOff(t *testing.T) {
	b, sc, _ := newItemHLSBridge(t, cutSource(t, "song.flac", longHLSFLAC), itemCaps(true), nil)
	sc.segments = 1000
	info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{MaxBitrateKbps: 96, HLS: true})
	if err != nil {
		t.Fatal(err)
	}
	master := serveHLS(b, info.URL)
	child := playlistChild(t, master.Body.String(), "media.m3u8")
	sc.mu.Lock()
	sc.breakMedia = true
	sc.mu.Unlock()
	rec := httptest.NewRecorder()
	aborted := false
	func() {
		defer func() {
			if v := recover(); v != nil {
				if v != http.ErrAbortHandler {
					panic(v)
				}
				aborted = true
			}
		}()
		b.ServeHLS(rec, httptest.NewRequest(http.MethodGet, child, nil))
	}()
	if !aborted && rec.Code < 500 {
		t.Fatalf("a broken-off playlist answered %d with %d bytes, want an error or the answer torn down", rec.Code, rec.Body.Len())
	}
	if strings.Contains(rec.Body.String(), "#EXT-X-ENDLIST") {
		t.Fatal("a broken-off playlist was ended as whole")
	}
}

func mustQuery(t *testing.T, u string) url.Values {
	t.Helper()
	parsed, err := url.Parse(u)
	if err != nil {
		t.Fatal(err)
	}
	return parsed.Query()
}

// A token for one rendering opens that rendering's playlists and segments
// and nothing else: not another rendering's, not a timeline's, and no
// other kind of token opens it.
func TestItemRenderingTokensOpenOnlyTheirRendering(t *testing.T) {
	b, _, _ := newItemHLSBridge(t, cutSource(t, "song.flac", longHLSFLAC), itemCaps(true), nil)
	mint := func(kbps int) PlayInfo {
		t.Helper()
		info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{MaxBitrateKbps: kbps, HLS: true})
		if err != nil {
			t.Fatal(err)
		}
		return info
	}
	low, high := mint(96), mint(192)
	q := mustQuery(t, low.URL)
	mt, it := q.Get("mt"), q.Get("it")
	if it == mustQuery(t, high.URL).Get("it") {
		t.Fatal("two renderings of one item share a key")
	}
	// A child as this server hands it out: the engine's query sealed
	// beside the token.
	sealedChild := func(path, query, token string) string {
		return "/media/hls/" + path + "?c=" + b.tokens.SealQuery(token, query) + "&mt=" + url.QueryEscape(token)
	}
	seg := func(v, token string) string { return sealedChild("seg/0.m4s", "v="+v+"&sig=seg0", token) }
	ownV := itemDescriptor{Src: "lib/song.flac", ID: "5-1", Format: "opus", Bitrate: 96}.encode()
	highV := itemDescriptor{Src: "lib/song.flac", ID: "5-1", Format: "opus", Bitrate: 192}.encode()
	if rec := serveHLS(b, seg(ownV, mt)); rec.Code != http.StatusOK {
		t.Fatalf("its own segment = %d: %s", rec.Code, rec.Body.String())
	}
	// The other rendering's media playlist as its own master handed it
	// out, under its own token.
	highMaster := serveHLS(b, high.URL)
	highChild := playlistChild(t, highMaster.Body.String(), "media.m3u8")
	if rec := serveHLS(b, highChild); rec.Code != http.StatusOK {
		t.Fatalf("the other rendering's own child = %d", rec.Code)
	}
	highMT := mustQuery(t, high.URL).Get("mt")
	underThisToken := strings.Replace(highChild, url.QueryEscape(highMT), url.QueryEscape(mt), 1)

	timelineTok, _ := b.tokens.MintFor(auth.MediaClaims{User: "us-1", Purpose: auth.PurposeHLS, PID: "tl-digest123/aac~off~0"}, 0)
	streamTok, _ := b.tokens.MintFor(auth.MediaClaims{User: "us-1", Purpose: auth.PurposeStream, PID: "tr-X", Shape: "it=" + it}, 0)
	// An item-shaped token naming a timeline would pass the per-item check
	// as one, so it opens nothing.
	forged, _ := b.tokens.MintFor(auth.MediaClaims{User: "us-1", Purpose: auth.PurposeHLS, PID: "tl-x", Shape: "it=" + it}, 0)
	for name, u := range map[string]string{
		"another rendering's master":                                "/media/hls/master.m3u8?it=" + mustQuery(t, high.URL).Get("it") + "&mt=" + url.QueryEscape(mt),
		"another rendering's segment":                               seg(highV, mt),
		"another rendering's child naming this one's it":            underThisToken + "&it=" + url.QueryEscape(it),
		"another rendering's child in the clear with this one's it": "/media/hls/seg/0.m4s?v=" + highV + "&sig=seg0&it=" + url.QueryEscape(it) + "&mt=" + url.QueryEscape(mt),
		"another item's segment":                                    seg(itemDescriptor{Src: "lib/other.flac", ID: "5-1", Format: "opus", Bitrate: 96}.encode(), mt),
		"a timeline's segment":                                      seg(childDescriptor("digest123"), mt),
		"a timeline's master":                                       "/media/hls/master.m3u8?tl=digest123&rk=aac~off~0&mt=" + url.QueryEscape(mt),
		"a segment naming nothing":                                  sealedChild("seg/0.m4s", "sig=seg0", mt),
		"a garbled descriptor":                                      sealedChild("media.m3u8", "v=%%%&sig=child", mt),
		"a timeline token":                                          seg(ownV, timelineTok),
		"a stream token":                                            "/media/hls/master.m3u8?it=" + it + "&mt=" + url.QueryEscape(streamTok),
		"an item token naming a timeline":                           "/media/hls/master.m3u8?it=" + it + "&mt=" + url.QueryEscape(forged),
		"no token":                                                  "/media/hls/master.m3u8?it=" + it,
	} {
		if rec := serveHLS(b, u); rec.Code != http.StatusUnauthorized {
			t.Errorf("%s = %d, want 401", name, rec.Code)
		}
	}
}

// Every fetch re-checks the account's right to the item, as a stream's
// does: an item it lost is not found, an ended session unauthenticated.
func TestItemRenderingFetchesRecheckAccess(t *testing.T) {
	b, _, gate := newItemHLSBridge(t, cutSource(t, "song.flac", longHLSFLAC), itemCaps(true), nil)
	info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{MaxBitrateKbps: 96, HLS: true})
	if err != nil {
		t.Fatal(err)
	}
	master := serveHLS(b, info.URL)
	if master.Code != http.StatusOK {
		t.Fatalf("master = %d", master.Code)
	}
	child := playlistChild(t, master.Body.String(), "media.m3u8")
	for _, c := range []struct {
		err  error
		want int
	}{
		{fmt.Errorf("lost: %w", ErrMediaRefused), http.StatusNotFound},
		{fmt.Errorf("ended: %w", auth.ErrMediaRevoked), http.StatusUnauthorized},
	} {
		gate.authErr = c.err
		for name, u := range map[string]string{"master": info.URL, "child": child} {
			if rec := serveHLS(b, u); rec.Code != c.want {
				t.Errorf("%s after %v = %d, want %d", name, c.err, rec.Code, c.want)
			}
		}
	}
}

// A rendering holds the listener's one slot while it is fetched, the
// slot their timelines hold: taken at the first fetch, shared by every
// rendering of theirs, given back after a quiet spell and taken again by
// the next fetch, which a full server refuses as a stream's open is.
func TestItemRenderingHoldsTheListenersSlot(t *testing.T) {
	src := cutSource(t, "song.flac", longHLSFLAC)
	b, _, gate := newItemHLSBridge(t, src, itemCaps(true), nil)
	mint := func(kbps int) PlayInfo {
		t.Helper()
		info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{MaxBitrateKbps: kbps, HLS: true})
		if err != nil {
			t.Fatal(err)
		}
		return info
	}
	first := mint(96)
	if rec := serveHLS(b, first.URL); rec.Code != http.StatusOK {
		t.Fatalf("master = %d", rec.Code)
	}
	if gate.acquired != 1 || gate.held != 1 || len(gate.kinds) != 1 || gate.kinds[0] != TranscodeStream {
		t.Fatalf("acquired %d held %d kinds %v, want one stream slot", gate.acquired, gate.held, gate.kinds)
	}
	// The next item, and a gapless queue, ride the same slot.
	if rec := serveHLS(b, mint(128).URL); rec.Code != http.StatusOK {
		t.Fatalf("second master = %d", rec.Code)
	}
	if _, err := b.TimelineFor(context.Background(), "us-1",
		[]TimelineMember{{PID: "tr-X", Src: src}}, TimelineOptions{}); err != nil {
		t.Fatal(err)
	}
	if gate.acquired != 1 || gate.held != 1 {
		t.Fatalf("acquired %d held %d, want the one slot shared", gate.acquired, gate.held)
	}

	ageTimelines(b, 2*timelineIdle)
	b.SweepTimelineSlots()
	if gate.held != 0 {
		t.Fatalf("held %d after a quiet spell, want the slot back", gate.held)
	}
	if rec := serveHLS(b, first.URL); rec.Code != http.StatusOK || gate.acquired != 2 || gate.held != 1 {
		t.Fatalf("fetch after the sweep = %d, acquired %d held %d; want the slot taken again", rec.Code, gate.acquired, gate.held)
	}

	ageTimelines(b, 2*timelineIdle)
	b.SweepTimelineSlots()
	gate.refuse = true
	rec := serveHLS(b, first.URL)
	if rec.Code != http.StatusTooManyRequests || !strings.Contains(rec.Body.String(), "transcode-limited") {
		t.Fatalf("a fetch over the cap = %d %s, want 429 transcode-limited", rec.Code, rec.Body.String())
	}
}

// The account's ceiling is read again at every fetch of an item rendering,
// as a stream's is: a lossy rendering above a ceiling lowered since its
// mint, or at the engine's own rate where a ceiling now applies, answers
// the stale stream's refusal, which a player re-mints on, and nothing is
// asked of the engine for it. One inside the ceiling plays on, and a
// lossless one plays out, as a lossless stream started before it does.
func TestItemRenderingFetchesHoldTheLiveCeiling(t *testing.T) {
	lufs := -20.0
	for name, c := range map[string]struct {
		src     Source
		opts    PlayOptions
		ceiling int
		refused bool
	}{
		"a cap above a ceiling lowered since": {longHLSFLAC, PlayOptions{MaxBitrateKbps: 128}, 96, true},
		"a cap inside the ceiling":            {longHLSFLAC, PlayOptions{MaxBitrateKbps: 96}, 128, false},
		"the engine's own rate under a new ceiling": {
			Source{Codec: "mp3", Container: "mp3", BitrateKbps: 64, DurationMS: 600_000, SpokenWord: true, IntegratedLUFS: &lufs},
			PlayOptions{VoiceBoost: true}, 96, true},
		"lossless under a new ceiling": {
			Source{Codec: "flac", Container: "flac", DurationMS: 200_000, Virtual: true, FromSample: 441000, ToSample: 9261000},
			PlayOptions{}, 96, false},
	} {
		t.Run(name, func(t *testing.T) {
			b, sc, gate := newItemHLSBridge(t, cutSource(t, "a", c.src), itemCaps(true), nil)
			c.opts.HLS = true
			info, err := b.PlayInfoFor(context.Background(), "us-1", "tr-X", c.opts)
			if err != nil {
				t.Fatal(err)
			}
			master := serveHLS(b, info.URL)
			media := serveHLS(b, playlistChild(t, master.Body.String(), "media.m3u8"))
			if master.Code != http.StatusOK || media.Code != http.StatusOK {
				t.Fatalf("before the ceiling: master %d, media %d", master.Code, media.Code)
			}
			fetches := map[string]string{
				"master":  info.URL,
				"media":   playlistChild(t, master.Body.String(), "media.m3u8"),
				"segment": playlistChild(t, media.Body.String(), "seg/0.m4s"),
			}
			gate.ceiling = c.ceiling
			sc.mu.Lock()
			asked := len(sc.masters) + len(sc.children)
			sc.mu.Unlock()
			for what, u := range fetches {
				rec := serveHLS(b, u)
				if c.refused {
					wantEnvelope(t, rec, http.StatusGone, "stream-stale")
				} else if rec.Code != http.StatusOK {
					t.Errorf("%s under the ceiling = %d: %s", what, rec.Code, rec.Body.String())
				}
			}
			sc.mu.Lock()
			defer sc.mu.Unlock()
			if c.refused && len(sc.masters)+len(sc.children) != asked {
				t.Errorf("refused fetches asked the engine %d times", len(sc.masters)+len(sc.children)-asked)
			}
		})
	}
}

// The stash row outlives a restart as a timeline's does, so a URL minted
// before it still plays; one the engine no longer serves is let go and
// answers the not-found that says mint again.
func TestItemRenderingStashSurvivesRestart(t *testing.T) {
	src := cutSource(t, "song.flac", longHLSFLAC)
	store, err := db.Open(context.Background(), filepath.Join(t.TempDir(), "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { store.Close() })
	first, _, _ := newItemHLSBridge(t, src, itemCaps(true), store)
	info, err := first.PlayInfoFor(context.Background(), "us-1", "tr-X", PlayOptions{MaxBitrateKbps: 96, HLS: true})
	if err != nil {
		t.Fatal(err)
	}

	second, sc, _ := newItemHLSBridge(t, src, itemCaps(true), store)
	// Same signing key across the restart, as the server's own is.
	second.tokens = first.tokens
	if rec := serveHLS(second, info.URL); rec.Code != http.StatusOK {
		t.Fatalf("master through the restarted bridge = %d: %s", rec.Code, rec.Body.String())
	}

	sc.deadMaster = http.StatusForbidden
	rec := serveHLS(second, info.URL)
	if rec.Code != http.StatusNotFound || !strings.Contains(rec.Body.String(), `"not-found"`) {
		t.Fatalf("a dead rendering = %d %s, want the not-found that says mint again", rec.Code, rec.Body.String())
	}
	rows, err := store.LoadTimelineStash(context.Background(), time.Now().UnixNano())
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 0 {
		t.Fatalf("dead rendering still stored: %+v", rows)
	}
}

// itemRendering keys a rendering by everything that shapes it, and only
// a single-source descriptor has one.
func TestItemRenderingKeys(t *testing.T) {
	base := itemDescriptor{Src: "lib/a.flac", ID: "5-1", Format: "opus", Bitrate: 96}
	k, ok := itemRendering(base.encode())
	if !ok || k == "" {
		t.Fatal("a single-source descriptor has no rendering key")
	}
	for name, d := range map[string]itemDescriptor{
		"another source":   {Src: "lib/b.flac", ID: "5-1", Format: "opus", Bitrate: 96},
		"another identity": {Src: "lib/a.flac", ID: "6-1", Format: "opus", Bitrate: 96},
		"another format":   {Src: "lib/a.flac", ID: "5-1", Format: "aac", Bitrate: 96},
		"another bitrate":  {Src: "lib/a.flac", ID: "5-1", Format: "opus", Bitrate: 128},
		"a gain":           {Src: "lib/a.flac", ID: "5-1", Format: "opus", Bitrate: 96, Gain: "4.0", Dynamics: "voice"},
		"dynamics alone":   {Src: "lib/a.flac", ID: "5-1", Format: "opus", Bitrate: 96, Dynamics: "voice"},
		"a window":         {Src: "lib/a.flac", ID: "5-1", Format: "opus", Bitrate: 96, From: 1},
		"a window's end":   {Src: "lib/a.flac", ID: "5-1", Format: "opus", Bitrate: 96, To: 88200},
	} {
		if other, _ := itemRendering(d.encode()); other == k {
			t.Errorf("%s shares the key", name)
		}
	}
	for name, v := range map[string]string{
		"a timeline": childDescriptor("digest123"),
		"garbage":    "%%%",
		"empty":      "",
	} {
		if _, ok := itemRendering(v); ok {
			t.Errorf("%s has a rendering key", name)
		}
	}
}

package flow

import (
	"testing"

	"github.com/colespringer/waxflow/client"
)

func testCaps() *client.Caps {
	return &client.Caps{
		Outputs: []client.CapsOutput{
			{Name: "wav", Live: true}, {Name: "flac", Live: true},
			{Name: "mp3", Live: true}, {Name: "opus", Live: true},
			{Name: "aac", Live: true},
		},
		Delivery: client.CapsDelivery{
			Progressive: true,
			CutFormats:  []string{"opus", "aac"},
		},
	}
}

func TestShapeForWholeFile(t *testing.T) {
	shape := ShapeFor(Source{Codec: "flac", Container: "flac"}, testCaps(), false)
	if shape.Format != "auto" || shape.MimeType != "audio/flac" || !shape.Seekable {
		t.Fatalf("whole-file shape = %+v", shape)
	}
}

func TestShapeForVirtualTracks(t *testing.T) {
	caps := testCaps()
	cases := []struct {
		codec      string
		wantFormat string
	}{
		// The cut rung: zero-generation packet moves for opus/aac.
		{"opus", "opus"},
		{"aac", "aac"},
		// Lossless sources transcode to FLAC, losing nothing.
		{"flac", "flac"},
		{"alac", "flac"},
		{"pcm", "flac"},
		// Lossy non-cut sources take the opus transcode.
		{"mp3", "opus"},
		{"vorbis", "opus"},
	}
	for _, c := range cases {
		shape := ShapeFor(Source{Virtual: true, Codec: c.codec}, caps, false)
		if shape.Format != c.wantFormat {
			t.Errorf("virtual %s: format = %q, want %q", c.codec, shape.Format, c.wantFormat)
		}
		if shape.Format == "auto" {
			t.Errorf("virtual %s: format auto disqualifies the cut and must never be used", c.codec)
		}
	}

	// Without an opus encoder the lossy fallback is the MP3 floor.
	noOpus := testCaps()
	noOpus.Outputs = []client.CapsOutput{{Name: "flac", Live: true}, {Name: "mp3", Live: true}}
	noOpus.Delivery.CutFormats = nil
	if shape := ShapeFor(Source{Virtual: true, Codec: "mp3"}, noOpus, false); shape.Format != "mp3" {
		t.Errorf("no-opus lossy fallback = %q, want mp3", shape.Format)
	}
}

func TestDeviceFormat(t *testing.T) {
	flacSrc := Source{Codec: "flac", Container: "flac"}
	mp3Src := Source{Codec: "mp3", Container: "mp3"}
	// direct is the shape a whole file gets before any device policy;
	// encoded is what a virtual track or an engaged voice boost leaves.
	direct := Shape{Format: "auto", MimeType: "audio/flac", Seekable: true}
	encoded := Shape{Format: "opus", MimeType: "audio/ogg"}
	cases := []struct {
		name          string
		src           Source
		shape         Shape
		accepts       []string
		caps          *client.Caps
		want          string
		wantAdvertise string
	}{
		{
			name:    "a renderer that declared nothing keeps the floor",
			src:     flacSrc,
			shape:   direct,
			accepts: nil,
			caps:    testCaps(),
			want:    "mp3",
		},
		{
			// The point of the whole feature: a renderer that plays flac
			// gets the flac file's own bytes, not an mp3 transcode and
			// not a flac re-encode.
			name:          "a renderer that plays the source container gets the original bytes",
			src:           flacSrc,
			shape:         direct,
			accepts:       []string{"audio/flac"},
			caps:          testCaps(),
			want:          "",
			wantAdvertise: "audio/flac",
		},
		{
			// The renderer's own spelling comes back, because a resource
			// declaring a type absent from its sink is one a strict
			// renderer refuses.
			name:          "vendor spellings match and are advertised back as sent",
			src:           flacSrc,
			shape:         direct,
			accepts:       []string{"audio/x-flac"},
			caps:          testCaps(),
			want:          "",
			wantAdvertise: "audio/x-flac",
		},
		{
			name:          "audio/mp3 is audio/mpeg",
			src:           mp3Src,
			shape:         Shape{Format: "auto", MimeType: "audio/mpeg", Seekable: true},
			accepts:       []string{"audio/mp3"},
			caps:          testCaps(),
			want:          "",
			wantAdvertise: "audio/mp3",
		},
		{
			// The regression a plain "lossless first" ordering ships:
			// this is the test renderer's own default profile, and
			// ranking wav above mp3 would send 1.4 Mbit/s of PCM for
			// every flac track where mp3 was sent before.
			name:          "wav does not outrank mp3 for a lossless source",
			src:           flacSrc,
			shape:         direct,
			accepts:       []string{"audio/mpeg", "audio/wav"},
			caps:          testCaps(),
			want:          "mp3",
			wantAdvertise: "audio/mpeg",
		},
		{
			// ...but it is still reachable, because a renderer that
			// takes nothing else would reject the floor.
			name:          "wav is the last resort when nothing else matches",
			src:           flacSrc,
			shape:         direct,
			accepts:       []string{"audio/wav"},
			caps:          testCaps(),
			want:          "wav",
			wantAdvertise: "audio/wav",
		},
		{
			name:          "a lossy source reaches wav only as a last resort too",
			src:           mp3Src,
			shape:         Shape{Format: "auto", MimeType: "audio/mpeg", Seekable: true},
			accepts:       []string{"audio/x-wav"},
			caps:          testCaps(),
			want:          "wav",
			wantAdvertise: "audio/x-wav",
		},
		{
			name:          "a lossless source transcodes into the best lossless target",
			src:           Source{Codec: "pcm", Container: "wav"},
			shape:         Shape{Format: "auto", MimeType: "audio/wav", Seekable: true},
			accepts:       []string{"audio/flac", "audio/mpeg"},
			caps:          testCaps(),
			want:          "flac",
			wantAdvertise: "audio/flac",
		},
		{
			// The trap the plain intersection falls into: a renderer
			// advertising flac is saying what it can play, not asking for
			// an mp3 inflated to five times the bytes for no quality.
			name:          "a lossy source is never expanded into a lossless target",
			src:           Source{Codec: "vorbis", Container: "ogg"},
			shape:         Shape{Format: "auto", MimeType: "audio/ogg", Seekable: true},
			accepts:       []string{"audio/flac", "audio/mpeg"},
			caps:          testCaps(),
			want:          "mp3",
			wantAdvertise: "audio/mpeg",
		},
		{
			name:          "a lossy source prefers aac over mp3",
			src:           Source{Codec: "vorbis", Container: "mka"},
			shape:         Shape{Format: "auto", MimeType: "audio/x-matroska", Seekable: true},
			accepts:       []string{"audio/mpeg", "audio/mp4"},
			caps:          testCaps(),
			want:          "aac",
			wantAdvertise: "audio/mp4",
		},
		{
			name:          "parameters do not defeat the match",
			src:           Source{Codec: "vorbis", Container: "mka"},
			shape:         Shape{Format: "auto", MimeType: "audio/x-matroska", Seekable: true},
			accepts:       []string{"audio/mp4; codecs=mp4a.40.2"},
			caps:          testCaps(),
			want:          "aac",
			wantAdvertise: "audio/mp4; codecs=mp4a.40.2",
		},
		{
			// audio/ogg names bytes that already exist, so it matches an
			// ogg source for passthrough.
			name:          "audio/ogg passes an ogg source through",
			src:           Source{Codec: "vorbis", Container: "ogg"},
			shape:         Shape{Format: "auto", MimeType: "audio/ogg", Seekable: true},
			accepts:       []string{"audio/ogg"},
			caps:          testCaps(),
			want:          "",
			wantAdvertise: "audio/ogg",
		},
		{
			// ...but it is never read as an offer of opus, which is the
			// only ogg-framed thing the engine can produce. A renderer
			// meaning Vorbis would get silence.
			name:    "audio/ogg is never read as an offer of opus",
			src:     flacSrc,
			shape:   direct,
			accepts: []string{"audio/ogg"},
			caps:    testCaps(),
			want:    "mp3",
		},
		{
			// Raw ADTS is not the engine's MP4-framed aac output.
			name:    "a renderer advertising only raw aac gets the floor",
			src:     flacSrc,
			shape:   direct,
			accepts: []string{"audio/aac"},
			caps:    testCaps(),
			want:    "mp3",
		},
		{
			// A virtual track has no original bytes to hand over, so the
			// container match must not fire for it.
			name:          "a virtual track is always encoded",
			src:           Source{Codec: "flac", Container: "flac", Virtual: true},
			shape:         Shape{Format: "flac", MimeType: "audio/flac"},
			accepts:       []string{"audio/flac"},
			caps:          testCaps(),
			want:          "flac",
			wantAdvertise: "audio/flac",
		},
		{
			// An engaged voice boost is a DSP stage, so the engine is
			// re-encoding regardless. Answering passthrough here would
			// leave the URL with no forced format, the engine would serve
			// its own opus choice, and the renderer would be handed
			// audio/ogg, which it never listed.
			name:          "an engaged voice boost never passes through",
			src:           mp3Src,
			shape:         encoded,
			accepts:       []string{"audio/mpeg"},
			caps:          testCaps(),
			want:          "mp3",
			wantAdvertise: "audio/mpeg",
		},
		{
			name:    "a target the engine cannot produce is skipped",
			src:     Source{Codec: "pcm", Container: "wav"},
			shape:   Shape{Format: "auto", MimeType: "audio/wav", Seekable: true},
			accepts: []string{"audio/flac"},
			caps: &client.Caps{Outputs: []client.CapsOutput{
				{Name: "mp3", Live: true},
			}},
			want: "mp3",
		},
		{
			name:    "nothing recognizable keeps the floor",
			src:     flacSrc,
			shape:   direct,
			accepts: []string{"video/mpeg", "application/octet-stream"},
			caps:    testCaps(),
			want:    "mp3",
		},
		{
			name:    "no caps at all keeps the floor",
			src:     flacSrc,
			shape:   direct,
			accepts: []string{"audio/flac"},
			caps:    nil,
			want:    "mp3",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, advertise := DeviceFormat(tc.src, tc.shape, tc.caps, tc.accepts, "mp3")
			if got != tc.want {
				t.Fatalf("DeviceFormat(%v) format = %q, want %q", tc.accepts, got, tc.want)
			}
			if advertise != tc.wantAdvertise {
				t.Fatalf("DeviceFormat(%v) advertise = %q, want %q", tc.accepts, advertise, tc.wantAdvertise)
			}
		})
	}
}

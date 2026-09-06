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

func TestCappedShape(t *testing.T) {
	caps := testCaps()
	cases := []struct {
		name       string
		src        Source
		cap        int
		wantFormat string
		wantCapped bool
	}{
		// No cap changes nothing.
		{"uncapped", Source{Codec: "flac"}, 0, "auto", false},
		// A lossy source already inside the cap streams unchanged. The
		// catalog stores kbps, so the case does too.
		{"lossy inside the cap", Source{Codec: "mp3", BitrateKbps: 128}, 192, "auto", false},
		// A lossy source over the cap is a real encode down to it.
		{"lossy over the cap", Source{Codec: "mp3", BitrateKbps: 320}, 128, "opus", true},
		// Unknown bitrate counts as over the cap, never under it.
		{"unknown bitrate", Source{Codec: "mp3"}, 320, "opus", true},
		// Lossless always re-encodes under a cap.
		{"lossless", Source{Codec: "flac", BitrateKbps: 900}, 320, "opus", true},
	}
	for _, c := range cases {
		shape, capped := CappedShape(c.src, caps, ShapeFor(c.src, caps, false), c.cap)
		if capped != c.wantCapped || shape.Format != c.wantFormat {
			t.Errorf("%s: (%q, %v), want (%q, %v)", c.name, shape.Format, capped, c.wantFormat, c.wantCapped)
		}
		if capped && shape.Seekable {
			t.Errorf("%s: a capped shape must never be seekable", c.name)
		}
	}

	// An encode already headed to a lossy format keeps it: a capped
	// voice boost stays on the boost's own pick.
	boosted := ShapeFor(Source{Codec: "flac"}, caps, true)
	if shape, capped := CappedShape(Source{Codec: "flac"}, caps, boosted, 128); !capped || shape.Format != boosted.Format {
		t.Errorf("capped boost = (%q, %v), want the boost format kept", shape.Format, capped)
	}
	// The source's own bitrate excuses only a direct play. A boosted
	// episode under the cap on disk still encodes at the engine's
	// choosing, so the cap rides along.
	underCap := Source{Codec: "mp3", BitrateKbps: 96, SpokenWord: true}
	boostedUnder := ShapeFor(underCap, caps, true)
	if _, capped := CappedShape(underCap, caps, boostedUnder, 128); !capped {
		t.Error("an under-cap source did not keep the cap on its voice-boost encode")
	}
	// A lossless cut re-shapes to the lossy tail, and the MP3 floor
	// stands in where the sidecar lacks opus.
	noOpus := testCaps()
	noOpus.Outputs = []client.CapsOutput{{Name: "flac", Live: true}, {Name: "mp3", Live: true}}
	cut := ShapeFor(Source{Virtual: true, Codec: "flac"}, noOpus, false)
	if shape, capped := CappedShape(Source{Virtual: true, Codec: "flac"}, noOpus, cut, 192); !capped || shape.Format != "mp3" {
		t.Errorf("capped lossless cut without opus = (%q, %v), want mp3", shape.Format, capped)
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

func lufs(v float64) *float64 { return &v }

func TestTimelineGainDB(t *testing.T) {
	member := func(durationMS int64, integrated, peak *float64) TimelineMember {
		return TimelineMember{Src: Source{DurationMS: durationMS, IntegratedLUFS: integrated, TruePeakDB: peak}}
	}
	cases := []struct {
		name    string
		members []TimelineMember
		want    float64
		wantOK  bool
	}{
		{
			name:    "nothing measured levels nothing",
			members: []TimelineMember{member(60000, nil, nil), member(60000, nil, nil)},
		},
		{
			name:    "a loud master is cut to the target",
			members: []TimelineMember{member(60000, lufs(-8), lufs(-0.2))},
			want:    -10,
			wantOK:  true,
		},
		{
			name:    "a quiet master with headroom is lifted",
			members: []TimelineMember{member(60000, lufs(-24), lufs(-12))},
			want:    6,
			wantOK:  true,
		},
		{
			// The mean is weighted by play time, so a ten-minute track
			// decides more of the queue's level than a one-minute one.
			name: "measured members are weighted by duration",
			members: []TimelineMember{
				member(600000, lufs(-20), lufs(-6)),
				member(60000, lufs(-9), lufs(-6)),
			},
			want:   -18 - (-20*600000+-9*60000)/660000,
			wantOK: true,
		},
		{
			name:    "an unmeasured member rides the measured ones' gain",
			members: []TimelineMember{member(60000, lufs(-24), lufs(-12)), member(60000, nil, nil)},
			want:    6,
			wantOK:  true,
		},
		{
			// Quiet but already peaking: boosting to the target would
			// clip, so the peak decides and the queue is nudged down to
			// the headroom line instead.
			name:    "a peaking master is held under the ceiling",
			members: []TimelineMember{member(60000, lufs(-24), lufs(-0.5))},
			want:    -0.5,
			wantOK:  true,
		},
		{
			name:    "a very quiet queue stops at the boost ceiling",
			members: []TimelineMember{member(60000, lufs(-40), nil)},
			want:    replayGainMaxBoostDB,
			wantOK:  true,
		},
		{
			// The two measurements come from one analysis row, so a
			// member with a peak and no loudness is rare - but it must
			// still bound the boost, because it is going into the same
			// stream. The peak sweep runs before the loudness check
			// skips a member, and this is what says so.
			name: "a peak counts even where its member's loudness does not",
			members: []TimelineMember{
				member(60000, lufs(-24), nil),
				member(60000, nil, lufs(-0.5)),
			},
			want:   -0.5,
			wantOK: true,
		},
		{
			name:    "a queue already at the target is left alone",
			members: []TimelineMember{member(60000, lufs(-18.01), lufs(-3))},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got, ok := TimelineGainDB(tc.members)
			if ok != tc.wantOK {
				t.Fatalf("TimelineGainDB ok = %v, want %v", ok, tc.wantOK)
			}
			if ok && (got-tc.want > 1e-9 || tc.want-got > 1e-9) {
				t.Fatalf("TimelineGainDB = %v, want %v", got, tc.want)
			}
		})
	}
}

// SameAsSource decides whether a forced format is a copy of the file or
// a real encode, which is the difference between serving bytes and
// charging a session slot. The false rows are the ones that matter: a
// remux still runs the engine.
func TestSameAsSource(t *testing.T) {
	cases := []struct {
		name   string
		src    Source
		format string
		want   bool
	}{
		{"mp3 in mp3", Source{Codec: "mp3", Container: "mp3"}, "mp3", true},
		{"flac in flac", Source{Codec: "flac", Container: "flac"}, "flac", true},
		{"pcm in wav", Source{Codec: "pcm", Container: "wav"}, "wav", true},
		{"opus in ogg", Source{Codec: "opus", Container: "ogg"}, "opus", true},
		{"opus in its own container", Source{Codec: "opus", Container: "opus"}, "opus", true},
		{"aac in m4a", Source{Codec: "aac", Container: "m4a"}, "aac", true},
		{"aac in an audiobook", Source{Codec: "aac", Container: "m4b"}, "aac", true},
		// The probe labels this one "aac (adts)", so the container fold
		// has to run before the comparison does.
		{"aac in adts is a remux", Source{Codec: "aac", Container: "aac (adts)"}, "aac", false},
		{"a label with a qualifier still folds", Source{Codec: "FLAC", Container: "flac (native)"}, "flac", true},
		{"vorbis in ogg is not opus", Source{Codec: "vorbis", Container: "ogg"}, "opus", false},
		{"alac in mp4 is not aac", Source{Codec: "alac", Container: "mp4"}, "aac", false},
		{"mp3 in matroska is a remux", Source{Codec: "mp3", Container: "mka"}, "mp3", false},
		{"a flac source asked for mp3", Source{Codec: "flac", Container: "flac"}, "mp3", false},
		{"a format nothing here outputs", Source{Codec: "wavpack", Container: "wv"}, "wavpack", false},
		{"no format at all", Source{Codec: "flac", Container: "flac"}, "", false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := SameAsSource(tc.src, tc.format); got != tc.want {
				t.Fatalf("SameAsSource(%q/%q, %q) = %v, want %v",
					tc.src.Codec, tc.src.Container, tc.format, got, tc.want)
			}
		})
	}
}

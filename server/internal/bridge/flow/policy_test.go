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
	shape := ShapeFor(Source{Codec: "flac", Container: "flac"}, testCaps())
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
		shape := ShapeFor(Source{Virtual: true, Codec: c.codec}, caps)
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
	if shape := ShapeFor(Source{Virtual: true, Codec: "mp3"}, noOpus); shape.Format != "mp3" {
		t.Errorf("no-opus lossy fallback = %q, want mp3", shape.Format)
	}
}

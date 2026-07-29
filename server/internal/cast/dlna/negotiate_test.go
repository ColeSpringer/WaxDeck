package dlna

import (
	"slices"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/cast/dlna/testrenderer"
	"github.com/colespringer/waxdeck/server/internal/connect"
)

// The driver reads the renderer's Sink once at dial and reports it as an
// endpoint capability. Everything downstream (which format the resolver
// forces) is decided from this list, so what matters here is that it is
// read at all, that it is the renderer's own answer, and that a renderer
// constraining nothing produces an empty list rather than a wildcard the
// resolver would have to know to ignore.
func TestDriverReportsRendererFormats(t *testing.T) {
	cases := []struct {
		name string
		sink []string
		want []string
	}{
		{
			name: "the default renderer",
			sink: nil, // testrenderer's own default
			want: []string{"audio/mpeg", "audio/wav"},
		},
		{
			name: "a renderer that takes flac",
			sink: []string{"http-get:*:audio/flac:*", "http-get:*:audio/mpeg:*"},
			want: []string{"audio/flac", "audio/mpeg"},
		},
		{
			name: "a renderer that takes mp3 only",
			sink: []string{"http-get:*:audio/mpeg:*"},
			want: []string{"audio/mpeg"},
		},
		{
			// A wildcard constrains nothing, so it must not read as a
			// format: a resolver told the renderer accepts "*" would
			// either match nothing or match everything, and both are
			// wrong answers to "what should I send it".
			name: "a renderer that answers a wildcard",
			sink: []string{"http-get:*:*:*"},
			want: nil,
		},
		{
			name: "a renderer that answers nothing",
			sink: []string{},
			want: nil,
		},
		{
			// The protocol field is not decoration. A renderer that
			// plays flac only over its own internal transport, or over
			// rtsp, cannot be handed flac over http-get; counting those
			// entries would send it a format it never offered to fetch.
			name: "formats offered over other transports do not count",
			sink: []string{
				"internal:*:audio/flac:*",
				"rtsp-rtp-udp:*:audio/L16:*",
				"http-get:*:audio/mpeg:*",
			},
			want: []string{"audio/mpeg"},
		},
		{
			// A wildcard protocol claims every transport, http-get
			// included.
			name: "a wildcard protocol counts",
			sink: []string{"*:*:audio/flac:*"},
			want: []string{"audio/flac"},
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			r := testrenderer.Start(t)
			if tc.sink != nil {
				r.SetSink(tc.sink...)
			}
			d := dialDriver(t, r)
			var sink connect.FormatSink = d
			got := sink.AcceptedFormats()
			if !slices.Equal(got, tc.want) {
				t.Fatalf("accepted formats = %v, want %v", got, tc.want)
			}
		})
	}
}

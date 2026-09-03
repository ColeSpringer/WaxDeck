package api

import (
	"io"
	"maps"
	"net/http"
	"slices"
	"strconv"
	"testing"

	"github.com/colespringer/waxdeck/fixtures"
)

// The delivery half for the two vendored exotics (the scan half is
// service.TestVendoredExoticFormatsScan). A newly decodable format that
// catalogs but cannot be handed to a player is the failure worth
// pinning, and it has two shapes: a container missing from the mime
// table direct-plays with no content type at all, and a source the
// ladder cannot re-encode has nowhere to go under a bitrate cap.
func TestVendoredExoticFormatsStream(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	paths, err := fixtures.WriteVendored(h.library, fixtures.AllExotics...)
	if err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	if len(paths) != len(fixtures.AllExotics) {
		t.Fatalf("wrote %d samples for %d names", len(paths), len(fixtures.AllExotics))
	}
	// Neither sample's tags identify it, so the items are keyed by the
	// container the scan read off them.
	byContainer := map[string]Item{}
	for _, sum := range h.items(t, "").Items {
		it := decode[Item](t, get(t, h.ts, "/api/v1/items/"+sum.Pid, h.token))
		if it.Container != nil {
			byContainer[*it.Container] = it
		}
	}
	// The floor cap is the only one a test can ask for, so which sample
	// re-encodes under it is decided by its own bitrate: the Musepack
	// sits above the floor and the WMA exactly on it, which is the
	// documented rule (a lossy source already at or below the cap
	// streams unchanged) rather than an accident of these two files.
	const floorCap = 32
	cases := []struct {
		container string
		mime      string
	}{
		{"musepack", "audio/x-musepack"},
		{"asf", "audio/x-ms-wma"},
	}
	for _, tc := range cases {
		it, ok := byContainer[tc.container]
		if !ok {
			t.Fatalf("no %s item scanned; containers = %v", tc.container, slices.Sorted(maps.Keys(byContainer)))
		}
		t.Run(tc.container, func(t *testing.T) {
			// Direct play names the container's own media type. An
			// unmapped container answers the empty string here, which
			// is what leaves a client with nothing to hand a decoder.
			pi := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+it.Pid+"/play-info", h.token))
			if pi.MimeType != tc.mime {
				t.Errorf("direct play mimeType = %q, want %q", pi.MimeType, tc.mime)
			}
			if !pi.Seekable {
				t.Errorf("direct play is not seekable: %+v", pi)
			}

			if it.Bitrate == nil {
				t.Fatalf("scan read no bitrate off the source")
			}
			pi = decode[PlayInfo](t, get(t, h.ts,
				"/api/v1/items/"+it.Pid+"/play-info?maxBitrateKbps="+strconv.Itoa(floorCap), h.token))
			if *it.Bitrate <= floorCap {
				if !pi.Seekable || pi.MimeType != tc.mime {
					t.Fatalf("a source at the cap was re-encoded: %+v", pi)
				}
				return
			}
			// Above the cap: a real encode. Not seekable, and the
			// engine is asked for a named format rather than the
			// file's own bytes - which is the whole delivery path for
			// a container no client decodes.
			if pi.Seekable || pi.MimeType == tc.mime {
				t.Fatalf("capped play-info direct-played: %+v", pi)
			}
			resp, err := http.Get(h.ts.URL + pi.Url)
			if err != nil {
				t.Fatal(err)
			}
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			if resp.StatusCode != 200 || len(body) == 0 {
				t.Fatalf("stream fetch status = %d bytes = %d", resp.StatusCode, len(body))
			}
			if h.flowReq.format == "" || h.flowReq.format == "auto" {
				t.Errorf("engine asked for format %q, want a real encode", h.flowReq.format)
			}
		})
	}
}

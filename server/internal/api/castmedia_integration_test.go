package api

import (
	"context"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/connect"
)

// castResolver rebuilds the resolver the harness wired into connect, so
// these tests can drive StreamItems with a chosen endpoint target
// instead of standing up a fake renderer to reach it.
func castResolver(h *harness) *ConnectResolver {
	return &ConnectResolver{Svc: h.svc, Bridge: h.bridge, Media: h.media}
}

// adminUserID is the account the harness bootstrapped, which is the one
// the resolver resolves visibility against.
func adminUserID(t *testing.T, h *harness) string {
	t.Helper()
	return bootstrap(t, h.ts).User.Id
}

func castEntries(t *testing.T, h *harness, titles ...string) []connect.QueueEntry {
	t.Helper()
	byTitle := map[string]ItemSummary{}
	for _, it := range h.items(t, "?mediaType=music").Items {
		byTitle[it.Title] = it
	}
	out := make([]connect.QueueEntry, 0, len(titles))
	for _, title := range titles {
		it, ok := byTitle[title]
		if !ok {
			t.Fatalf("no item titled %q in the demo library: %v", title, byTitle)
		}
		out = append(out, connect.QueueEntry{PID: it.Pid, Title: it.Title, DurationMS: 30_000})
	}
	return out
}

func TestStreamItemsNegotiatesRendererFormat(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	r := castResolver(h)
	entries := castEntries(t, h, "Alpha Song")
	ctx := context.Background()
	userID := adminUserID(t, h)

	cases := []struct {
		name     string
		target   connect.EndpointTarget
		wantFmt  string
		wantMime string
	}{
		{
			// The floor, which is what every renderer got before
			// negotiation existed. A renderer that says nothing still
			// gets it.
			name:     "a renderer that declared nothing",
			target:   connect.EndpointTarget{Kind: connect.KindDLNA},
			wantFmt:  "mp3",
			wantMime: "audio/mpeg",
		},
		{
			// Alpha Song is flac, so a renderer that plays flac gets the
			// file itself: no fmt on the URL, the container's own media
			// type, and no engine session spent.
			name: "a renderer that takes flac gets the flac file",
			target: connect.EndpointTarget{
				Kind:    connect.KindDLNA,
				Formats: []string{"audio/mpeg", "audio/flac"},
			},
			wantFmt:  "",
			wantMime: "audio/flac",
		},
		{
			// ...and the renderer's own spelling comes back on the res
			// element, not ours. A resource declaring a type absent from
			// the sink is one a strict renderer refuses to load.
			name: "a renderer spelling it x-flac gets that spelling back",
			target: connect.EndpointTarget{
				Kind:    connect.KindDLNA,
				Formats: []string{"audio/x-flac"},
			},
			wantFmt:  "",
			wantMime: "audio/x-flac",
		},
		{
			name: "a renderer that takes mp3 only still transcodes",
			target: connect.EndpointTarget{
				Kind:    connect.KindDLNA,
				Formats: []string{"audio/mpeg"},
			},
			wantFmt:  "mp3",
			wantMime: "audio/mpeg",
		},
		{
			// The test renderer's own default profile. Ranking wav above
			// mp3 because it is lossless would send 1.4 Mbit/s of PCM
			// for every flac track on the most ordinary renderer there
			// is, where mp3 was sent before.
			name: "mp3 plus wav does not become wav",
			target: connect.EndpointTarget{
				Kind:    connect.KindDLNA,
				Formats: []string{"audio/mpeg", "audio/wav"},
			},
			wantFmt:  "mp3",
			wantMime: "audio/mpeg",
		},
		{
			// Not negotiable: the jukebox reads a wav preamble off its
			// input and fails on anything else, so what the endpoint
			// might also accept is beside the point.
			name:     "the jukebox is not negotiated",
			target:   connect.EndpointTarget{Kind: connect.KindJukebox, Formats: []string{"audio/flac"}},
			wantFmt:  "wav",
			wantMime: "audio/wav",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			items, err := r.StreamItems(ctx, userID, entries, tc.target, "http://192.0.2.10:4420", 30*time.Minute)
			if err != nil {
				t.Fatal(err)
			}
			if len(items) != 1 {
				t.Fatalf("items = %d, want 1", len(items))
			}
			u, err := url.Parse(items[0].URL)
			if err != nil {
				t.Fatal(err)
			}
			if got := u.Query().Get("fmt"); got != tc.wantFmt {
				t.Errorf("forced format = %q, want %q", got, tc.wantFmt)
			}
			if items[0].MimeType != tc.wantMime {
				t.Errorf("mime type = %q, want %q", items[0].MimeType, tc.wantMime)
			}
		})
	}
}

// A lossy source is the case the intersection reading gets wrong: a
// renderer advertising flac must not make the server inflate an mp3
// into it.
func TestStreamItemsNeverInflatesALossySource(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	r := castResolver(h)
	entries := castEntries(t, h, "Bravo Song") // mp3 in the demo library
	items, err := r.StreamItems(context.Background(), adminUserID(t, h), entries,
		connect.EndpointTarget{Kind: connect.KindDLNA, Formats: []string{"audio/flac"}},
		"http://192.0.2.10:4420", 30*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	u, err := url.Parse(items[0].URL)
	if err != nil {
		t.Fatal(err)
	}
	if got := u.Query().Get("fmt"); got == "flac" {
		t.Fatal("an mp3 source was transcoded to flac for a renderer that merely accepts flac")
	}
	if got := u.Query().Get("fmt"); got != "mp3" {
		t.Fatalf("forced format = %q, want the mp3 floor", got)
	}
}

func TestStreamItemsMintsFetchableArt(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	r := castResolver(h)
	entries := castEntries(t, h, "Alpha Song")
	// The demo fixtures carry no covers, so give this one something to
	// serve; the endpoint's own fallback chain is the art endpoint's and
	// is tested there.
	wantStatus(t, metadataPutBytes(t, h.ts, "/api/v1/items/"+entries[0].PID+"/artwork", h.token, tinyPNG(t)),
		200, "set cover")
	items, err := r.StreamItems(context.Background(), adminUserID(t, h), entries,
		connect.EndpointTarget{Kind: connect.KindCast}, h.ts.URL, 30*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	art := items[0].ArtURL
	if art == "" {
		t.Fatal("a cast item carries no art URL")
	}
	if !strings.HasPrefix(art, h.ts.URL+"/media/art?") {
		t.Fatalf("art URL = %q, want an absolute /media/art URL", art)
	}

	// The point of the endpoint: a device with no session fetches it
	// with nothing but the URL it was handed.
	resp, err := http.Get(art)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("art status = %d, want 200", resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); !strings.HasPrefix(ct, "image/") {
		t.Fatalf("art content type = %q", ct)
	}
	if cc := resp.Header.Get("Cache-Control"); cc != "no-store" {
		t.Fatalf("art Cache-Control = %q, want no-store: the URL carries a credential", cc)
	}

	// The token binds one pid. Pointing the same token at another item
	// is the attack this shape exists to refuse.
	other := castEntries(t, h, "Bravo Song")
	u, _ := url.Parse(art)
	q := u.Query()
	q.Set("pid", other[0].PID)
	u.RawQuery = q.Encode()
	resp2, err := http.Get(u.String())
	if err != nil {
		t.Fatal(err)
	}
	resp2.Body.Close()
	if resp2.StatusCode != 401 {
		t.Fatalf("art for another pid = %d, want 401", resp2.StatusCode)
	}

	// No token at all is the same refusal.
	q.Del("mt")
	u.RawQuery = q.Encode()
	resp3, err := http.Get(u.String())
	if err != nil {
		t.Fatal(err)
	}
	resp3.Body.Close()
	if resp3.StatusCode != 401 {
		t.Fatalf("art without a token = %d, want 401", resp3.StatusCode)
	}
}

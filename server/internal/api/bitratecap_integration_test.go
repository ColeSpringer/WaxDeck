package api

import (
	"io"
	"net/http"
	"testing"
)

// A quality cap re-encodes what direct play would have served, and the
// whole trade is visible on the wire: the mint reports the applied cap
// and the loss of seekability, the engine sees the narrowed bitrate,
// and an out-of-range request is refused as invalid.
func TestPlayInfoBitrateCapRoundTrip(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "?limit=1").Items[0].Pid

	resp := get(t, h.ts, "/api/v1/items/"+pid+"/play-info?maxBitrateKbps=128", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("capped play-info status = %d", resp.StatusCode)
	}
	pi := decode[PlayInfo](t, resp)
	if pi.AppliedBitrateKbps == nil || *pi.AppliedBitrateKbps != 128 {
		t.Fatalf("appliedBitrateKbps = %v, want 128", pi.AppliedBitrateKbps)
	}
	if pi.Seekable {
		t.Fatal("a capped stream advertised seekable, which would let it preload")
	}
	if pi.MimeType != "audio/ogg" {
		t.Fatalf("capped mime = %q, want the opus encode", pi.MimeType)
	}

	streamResp, err := http.Get(h.ts.URL + pi.Url)
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, streamResp.Body)
	streamResp.Body.Close()
	if streamResp.StatusCode != 200 {
		t.Fatalf("capped stream status = %d", streamResp.StatusCode)
	}
	if h.flowReq.format != "opus" || h.flowReq.bitrate != "128" {
		t.Fatalf("engine saw format=%q bitrate=%q, want opus at 128", h.flowReq.format, h.flowReq.bitrate)
	}

	// Out of range is a structured refusal, not a silent ignore.
	resp = get(t, h.ts, "/api/v1/items/"+pid+"/play-info?maxBitrateKbps=1000", h.token)
	if resp.StatusCode != 400 {
		t.Fatalf("out-of-range status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "invalid-request" {
		t.Fatalf("out-of-range code = %q, want invalid-request", e.Code)
	}
}

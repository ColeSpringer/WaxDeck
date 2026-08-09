package api

import (
	"bytes"
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"io"
	"net/http"
	"testing"
)

// coverBytes encodes a distinct solid PNG, standing in for cover art.
func coverBytes(t *testing.T, shade uint8) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 96, 96))
	for y := range 96 {
		for x := range 96 {
			img.Set(x, y, color.RGBA{shade, uint8(255 - int(shade)), shade / 2, 255})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// putArtwork uploads raw image bytes to an artwork endpoint.
func putArtwork(t *testing.T, h *harness, path string, raw []byte) *http.Response {
	t.Helper()
	req, _ := http.NewRequest("PUT", h.ts.URL+path, bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/octet-stream")
	req.Header.Set("Authorization", "Bearer "+h.token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

// getArt fetches an art response without decoding it, so the caller can
// look at headers as well as bytes.
func getArt(t *testing.T, h *harness, path, ifNoneMatch string) *http.Response {
	t.Helper()
	req, _ := http.NewRequest("GET", h.ts.URL+path, nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	if ifNoneMatch != "" {
		req.Header.Set("If-None-Match", ifNoneMatch)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

// subsonicCoverArt fetches a cover through the compatibility surface,
// returning its status, ETag, and bytes.
func subsonicCoverArt(t *testing.T, h *harness, secret, id, ifNoneMatch string) (int, string, []byte) {
	t.Helper()
	salt := "abc123"
	sum := md5.Sum([]byte(secret + salt))
	q := "?u=admin&t=" + hex.EncodeToString(sum[:]) + "&s=" + salt + "&v=1.16.1&c=test&id=" + id
	req, _ := http.NewRequest("GET", h.ts.URL+"/rest/getCoverArt"+q, nil)
	if ifNoneMatch != "" {
		req.Header.Set("If-None-Match", ifNoneMatch)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, resp.Header.Get("ETag"), body
}

// subsonicPlaylists reads the playlist headers off getPlaylists.
func subsonicPlaylists(t *testing.T, h *harness, secret string) []struct {
	ID       string `json:"id"`
	Name     string `json:"name"`
	CoverArt string `json:"coverArt"`
} {
	t.Helper()
	salt := "abc123"
	sum := md5.Sum([]byte(secret + salt))
	q := "?u=admin&t=" + hex.EncodeToString(sum[:]) + "&s=" + salt + "&v=1.16.1&c=test&f=json"
	resp, err := http.Get(h.ts.URL + "/rest/getPlaylists" + q)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	var wrapper struct {
		Response struct {
			Playlists struct {
				Playlist []struct {
					ID       string `json:"id"`
					Name     string `json:"name"`
					CoverArt string `json:"coverArt"`
				} `json:"playlist"`
			} `json:"playlists"`
		} `json:"subsonic-response"`
	}
	if err := json.Unmarshal(body, &wrapper); err != nil {
		t.Fatalf("getPlaylists: %v (body %s)", err, body)
	}
	return wrapper.Response.Playlists.Playlist
}

// TestPlaylistCoverAcrossSurfaces drives one playlist cover end to end
// through both read surfaces. Storing the cover on the catalog entity
// rather than caching it beside one is what makes this possible: the
// first-party art endpoint and the compatibility surface serve the same
// bytes under the same validator, with no per-surface injection.
func TestPlaylistCoverAcrossSurfaces(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)
	items := h.items(t, "")
	if len(items.Items) < 4 {
		t.Fatalf("fixture library has %d items, want at least 4", len(items.Items))
	}
	pids := make([]string, 0, 4)
	for i, it := range items.Items[:4] {
		resp := putArtwork(t, h, "/api/v1/items/"+it.Pid+"/artwork", coverBytes(t, uint8(30+i*60)))
		if resp.StatusCode != 200 {
			body, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			t.Fatalf("item artwork status = %d (%s)", resp.StatusCode, body)
		}
		resp.Body.Close()
		pids = append(pids, it.Pid)
	}

	created := h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Cover art", "kind": "static", "itemPids": pids,
	})
	if created.StatusCode != 201 {
		body, _ := io.ReadAll(created.Body)
		created.Body.Close()
		t.Fatalf("playlist create status = %d (%s)", created.StatusCode, body)
	}
	pl := decode[Playlist](t, created)
	if pl.HasArt == nil || !*pl.HasArt {
		t.Fatalf("hasArt = %v on a playlist whose members all carry covers", pl.HasArt)
	}

	// The first-party art endpoint answers the playlist pid.
	resp := getArt(t, h, "/api/v1/items/"+pl.Pid+"/art", "")
	if resp.StatusCode != 200 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("playlist art status = %d (%s)", resp.StatusCode, body)
	}
	restETag := resp.Header.Get("ETag")
	restBody, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if restETag == "" {
		t.Error("the playlist art response carries no ETag")
	}
	if _, format, err := image.DecodeConfig(bytes.NewReader(restBody)); err != nil || format != "jpeg" {
		t.Errorf("the generated cover is %s (err %v), want the jpeg mosaic", format, err)
	}

	// Revalidation works, so a playlist grid does not refetch every tile.
	if again := getArt(t, h, "/api/v1/items/"+pl.Pid+"/art", restETag); again.StatusCode != 304 {
		t.Errorf("If-None-Match status = %d, want 304", again.StatusCode)
	}

	// The compatibility surface advertises the cover on the playlist
	// header and serves the same bytes under the same validator.
	var listed bool
	for _, p := range subsonicPlaylists(t, h, secret) {
		if p.ID == pl.Pid {
			listed = true
			if p.CoverArt != pl.Pid {
				t.Errorf("subsonic coverArt = %q, want the playlist id %q", p.CoverArt, pl.Pid)
			}
		}
	}
	if !listed {
		t.Fatal("the playlist is missing from getPlaylists")
	}
	status, subETag, subBody := subsonicCoverArt(t, h, secret, pl.Pid, "")
	if status != 200 {
		t.Fatalf("subsonic getCoverArt status = %d", status)
	}
	if subETag != restETag {
		t.Errorf("subsonic ETag = %q, first-party = %q; the same bytes should validate the same", subETag, restETag)
	}
	if !bytes.Equal(subBody, restBody) {
		t.Error("the two surfaces serve different bytes for one cover")
	}
	if status, _, _ := subsonicCoverArt(t, h, secret, pl.Pid, subETag); status != 304 {
		t.Errorf("subsonic If-None-Match status = %d, want 304", status)
	}

	// An owner's upload replaces the mosaic on both surfaces at once.
	custom := coverBytes(t, 210)
	up := putArtwork(t, h, "/api/v1/entities/playlist/"+pl.Pid+"/artwork", custom)
	if up.StatusCode != 200 {
		body, _ := io.ReadAll(up.Body)
		up.Body.Close()
		t.Fatalf("playlist artwork upload status = %d (%s)", up.StatusCode, body)
	}
	up.Body.Close()
	resp = getArt(t, h, "/api/v1/items/"+pl.Pid+"/art", "")
	got, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if !bytes.Equal(got, custom) {
		t.Error("the uploaded cover is not what the art endpoint serves")
	}
	if _, _, subGot := subsonicCoverArt(t, h, secret, pl.Pid, ""); !bytes.Equal(subGot, custom) {
		t.Error("the compatibility surface still serves the mosaic after an upload")
	}

	// Clearing hands the slot back to the generated cover rather than
	// leaving the playlist bare.
	del := h.deleteReq(t, "/api/v1/entities/playlist/"+pl.Pid+"/artwork")
	if del.StatusCode != 204 {
		body, _ := io.ReadAll(del.Body)
		del.Body.Close()
		t.Fatalf("playlist artwork clear status = %d (%s)", del.StatusCode, body)
	}
	del.Body.Close()
	resp = getArt(t, h, "/api/v1/items/"+pl.Pid+"/art", "")
	back, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if bytes.Equal(back, custom) {
		t.Fatal("the cleared cover is still being served")
	}
	if !bytes.Equal(back, restBody) {
		t.Error("the mosaic did not come back after the clear")
	}
}

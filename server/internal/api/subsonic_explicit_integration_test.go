package api

import (
	"crypto/md5"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"
)

// TestSubsonicExplicitStatusFromAdvisoryTag pins the OpenSubsonic
// advisory for music: a track tagged ITUNESADVISORY=1 answers
// explicitStatus="explicit" on the song shape and marks its album, a
// "2" (a declared clean) and an absent tag both stay empty - the
// emission is positive-only and never truthy-parses - a playlist entry
// inherits the same answer because it renders through the same song
// mapping, and the XML rendering carries the attribute the JSON one
// does. A tag-deny account (the admin screen's kids preset) then
// browses the same album and must not receive the flagged track at
// all, even though the admin's browsing has already warmed the caches.
func TestSubsonicExplicitStatusFromAdvisoryTag(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	secret := newSubsonicSecret(t, h)

	items := h.items(t, "")
	var explicitPID, cleanPID, albumID string
	for _, it := range items.Items {
		switch it.Title {
		case "Alpha Song":
			explicitPID = it.Pid
			if it.AlbumPid != nil {
				albumID = *it.AlbumPid
			}
		case "Bravo Song":
			cleanPID = it.Pid
		}
	}
	if explicitPID == "" || cleanPID == "" || albumID == "" {
		t.Fatalf("demo tracks unresolved: explicit=%q clean=%q album=%q", explicitPID, cleanPID, albumID)
	}

	resp := putJSON(t, h.ts, "/api/v1/items/"+explicitPID+"/tags/ITUNESADVISORY", h.token,
		map[string]any{"values": []string{"1"}})
	if resp.StatusCode != 200 {
		t.Fatalf("tagging the explicit track: status %d", resp.StatusCode)
	}
	if out := decode[TagEditResult](t, resp); out.Stored != 1 {
		t.Fatalf("explicit tag stored = %d, want 1", out.Stored)
	}
	resp = putJSON(t, h.ts, "/api/v1/items/"+cleanPID+"/tags/ITUNESADVISORY", h.token,
		map[string]any{"values": []string{"2"}})
	if resp.StatusCode != 200 {
		t.Fatalf("tagging the clean track: status %d", resp.StatusCode)
	}
	// Asserted stored so the clean leg means something: a rejected or
	// misfiled "2" would leave its later empty-advisory assertion
	// identical to the untagged tracks'.
	if out := decode[TagEditResult](t, resp); out.Stored != 1 {
		t.Fatalf("clean tag stored = %d, want 1", out.Stored)
	}

	// The facts sweep is cached against the change-feed position and a
	// background consumer advances it, so poll the edit into view
	// rather than race it (CI runs several times slower than a dev
	// box). The response struct is declared inside the loop: decoding
	// into a reused one keeps absent omitempty fields from a prior
	// iteration, and a stale "explicit" would pass a round the server
	// never sent it in.
	byID := map[string]string{}
	albumStatus := ""
	deadline := time.Now().Add(30 * time.Second)
	for {
		var album struct {
			Status string `json:"status"`
			Album  struct {
				ExplicitStatus string `json:"explicitStatus"`
				Songs          []struct {
					ID             string `json:"id"`
					ExplicitStatus string `json:"explicitStatus"`
				} `json:"song"`
			} `json:"album"`
		}
		subsonicJSON(t, h, "getAlbum", secret, "&id="+url.QueryEscape(albumID), &album)
		if album.Status != "ok" {
			t.Fatalf("getAlbum envelope status = %q", album.Status)
		}
		clear(byID)
		for _, s := range album.Album.Songs {
			byID[s.ID] = s.ExplicitStatus
		}
		albumStatus = album.Album.ExplicitStatus
		if byID[explicitPID] == "explicit" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("the tagged track never reported explicit: %v", byID)
		}
		time.Sleep(50 * time.Millisecond)
	}
	if len(byID) != 4 {
		t.Fatalf("getAlbum songs = %v, want the 4 demo tracks", byID)
	}
	for id, status := range byID {
		if id != explicitPID && status != "" {
			t.Errorf("track %s advisory = %q, want empty (declared clean and unsaid both stay unasserted)", id, status)
		}
	}
	if albumStatus != "explicit" {
		t.Errorf("album advisory = %q, want explicit (any flagged member marks the album)", albumStatus)
	}

	// The XML rendering carries the same attribute (JSON is the only
	// format the helpers pin, and real clients like DSub read XML).
	xmlResp, err := http.Get(h.ts.URL + "/rest/getAlbum?apiKey=" + secret + "&id=" + url.QueryEscape(albumID))
	if err != nil {
		t.Fatal(err)
	}
	xmlBody, _ := io.ReadAll(xmlResp.Body)
	xmlResp.Body.Close()
	if !strings.Contains(string(xmlBody), `explicitStatus="explicit"`) {
		t.Errorf("xml getAlbum carries no explicitStatus attribute: %s", xmlBody)
	}

	// Playlist entries render through the same song mapping, so the
	// advisory rides along.
	created := h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Advisory", "kind": "static", "itemPids": []string{explicitPID, cleanPID},
	})
	if created.StatusCode != 201 {
		t.Fatalf("playlist create status = %d", created.StatusCode)
	}
	pl := decode[Playlist](t, created)
	var got struct {
		Playlist struct {
			Entries []struct {
				ID             string `json:"id"`
				ExplicitStatus string `json:"explicitStatus"`
			} `json:"entry"`
		} `json:"playlist"`
	}
	subsonicJSON(t, h, "getPlaylist", secret, "&id="+url.QueryEscape(pl.Pid), &got)
	if len(got.Playlist.Entries) != 2 {
		t.Fatalf("playlist entries = %+v", got.Playlist.Entries)
	}
	for _, e := range got.Playlist.Entries {
		want := ""
		if e.ID == explicitPID {
			want = "explicit"
		}
		if e.ExplicitStatus != want {
			t.Errorf("playlist entry %s advisory = %q, want %q", e.ID, e.ExplicitStatus, want)
		}
	}

	// A tag-deny account must not receive the flagged track from any
	// browse verb - the sweep behind them all carries the caller's
	// rules now - and must not be handed the admin's cached index,
	// which the polling above has warmed.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "kid", "password": testPassword,
		"permissions": map[string]any{
			"tagDeny": []map[string]string{{"key": "ITUNESADVISORY", "value": "1"}},
		},
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create restricted user status = %d", resp.StatusCode)
	}
	resp.Body.Close()
	kid := loginAs(t, h.ts, "kid", testPassword)
	appPw := postJSON(t, h.ts.URL+"/api/v1/users/me/app-passwords", kid.Token, `{"label":"subsonic kid"}`)
	if appPw.StatusCode != 201 {
		t.Fatalf("kid app password status = %d", appPw.StatusCode)
	}
	kidSecret := decode[AppPasswordCreated](t, appPw).Secret

	var kidAlbum struct {
		Status string `json:"status"`
		Album  struct {
			ExplicitStatus string `json:"explicitStatus"`
			Songs          []struct {
				ID string `json:"id"`
			} `json:"song"`
		} `json:"album"`
	}
	salt := "kidsalt"
	sum := md5.Sum([]byte(kidSecret + salt))
	kidResp, err := http.Get(h.ts.URL + "/rest/getAlbum?u=kid&t=" + hex.EncodeToString(sum[:]) +
		"&s=" + salt + "&v=1.16.1&c=test&f=json&id=" + url.QueryEscape(albumID))
	if err != nil {
		t.Fatal(err)
	}
	decodeSubsonicBody(t, kidResp, &kidAlbum)
	if kidAlbum.Status != "ok" {
		t.Fatalf("kid getAlbum envelope status = %q", kidAlbum.Status)
	}
	if len(kidAlbum.Album.Songs) != 3 {
		t.Fatalf("kid sees %d songs, want 3 (the flagged track hidden)", len(kidAlbum.Album.Songs))
	}
	for _, s := range kidAlbum.Album.Songs {
		if s.ID == explicitPID {
			t.Error("the deny rule's track reached the restricted account")
		}
	}
	if kidAlbum.Album.ExplicitStatus != "" {
		t.Errorf("kid album advisory = %q, want empty (derived from the tracks they can see)", kidAlbum.Album.ExplicitStatus)
	}
}

// decodeSubsonicBody unwraps one subsonic-response envelope from a
// finished HTTP response, for calls made as a caller the shared
// helpers' hardcoded admin identity cannot express.
func decodeSubsonicBody(t *testing.T, resp *http.Response, out any) {
	t.Helper()
	defer resp.Body.Close()
	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		t.Fatalf("status = %d: %s", resp.StatusCode, body)
	}
	if err := unmarshalSubsonic(body, out); err != nil {
		t.Fatalf("%v (body %s)", err, body)
	}
}

func unmarshalSubsonic(body []byte, out any) error {
	var wrapper map[string]json.RawMessage
	if err := json.Unmarshal(body, &wrapper); err != nil {
		return err
	}
	env, ok := wrapper["subsonic-response"]
	if !ok {
		return errors.New("no subsonic-response key")
	}
	return json.Unmarshal(env, out)
}

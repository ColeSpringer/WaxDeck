package api

import (
	"crypto/md5"
	"encoding/hex"
	"io"
	"net/http"
	"net/url"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/auth"
)

// mediaListener creates an account with the given permissions, signs it
// in, and answers its id, token and session id.
func mediaListener(t *testing.T, h *harness, username string, perms map[string]any) (id, token, session string) {
	t.Helper()
	body := map[string]any{"username": username, "password": testPassword}
	if perms != nil {
		body["permissions"] = perms
	}
	resp := h.postJSON(t, "/api/v1/users", body)
	if resp.StatusCode != 201 {
		b, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("create %s = %d: %s", username, resp.StatusCode, b)
	}
	id = decode[UserAccount](t, resp).Id
	token = loginAs(t, h.ts, username, testPassword).Token
	for _, s := range decode[SessionList](t, get(t, h.ts, "/api/v1/auth/sessions", token)).Sessions {
		if s.Current {
			session = s.Id
		}
	}
	return id, token, session
}

// fetchStatus answers a URL's status, reading the body to the end so a
// stream's proxying finishes.
func fetchStatus(t *testing.T, h *harness, u string) int {
	t.Helper()
	resp, err := http.Get(h.ts.URL + u)
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	return resp.StatusCode
}

// A media token opens only the route it was minted for, with only the
// stream parameters the mint chose: a capped account's fmt=opus&br=64
// edited to fmt=flac opens nothing.
func TestMediaTokenOpensOnlyItsRouteAndShape(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "?limit=1").Items[0].Pid
	pi := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-info?maxBitrateKbps=96", h.token))
	if code := fetchStatus(t, h, pi.Url); code != 200 {
		t.Fatalf("the minted stream = %d", code)
	}
	for name, edited := range map[string]string{
		"the stream token on the download route": strings.Replace(pi.Url, "/media/stream?", "/media/download?", 1),
		"an edited format":                       strings.Replace(pi.Url, "fmt=opus", "fmt=flac", 1),
		"a stripped cap":                         strings.Replace(pi.Url, "&br=96", "", 1),
		"an added part":                          pi.Url + "&f=01JZX5N8QW3F4V9T2B7KDEXAMP",
	} {
		if code := fetchStatus(t, h, edited); code != http.StatusUnauthorized {
			t.Errorf("%s = %d, want 401", name, code)
		}
	}
	// A seek stays free: t is the client's to pick.
	if code := fetchStatus(t, h, pi.Url+"&t=1"); code != 200 {
		t.Errorf("a seek = %d, want 200", code)
	}

	art, _ := h.media.MintFor(auth.MediaClaims{User: adminUserID(t, h), Purpose: auth.PurposeArt, PID: pid}, 0)
	if code := fetchStatus(t, h, "/media/stream?pid="+url.QueryEscape(pid)+"&mt="+url.QueryEscape(art)); code != http.StatusUnauthorized {
		t.Errorf("an art token on the stream route = %d, want 401", code)
	}
}

// A lapsed media token is refused in the contract's words: the code a
// player reads to mint the stream again rather than blame the file.
func TestExpiredMediaTokenAnswers401WithTheContractCode(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "?limit=1").Items[0].Pid
	claims := auth.MediaClaims{User: adminUserID(t, h), Purpose: auth.PurposeStream, PID: pid}
	streamURL := func(token string) string {
		return "/media/stream?pid=" + url.QueryEscape(pid) + "&mt=" + url.QueryEscape(token)
	}
	// The same claims inside their lifetime play, so the refusal below is
	// the expiry's alone.
	live, _ := h.media.MintFor(claims, 0)
	if code := fetchStatus(t, h, streamURL(live)); code != 200 {
		t.Fatalf("a live token = %d, want 200", code)
	}

	// The shortest lifetime a mint gives: lapsed once its second is over.
	lapsed, exp := h.media.MintFor(claims, time.Nanosecond)
	time.Sleep(time.Until(exp.Add(time.Second + 10*time.Millisecond)))
	resp, err := http.Get(h.ts.URL + streamURL(lapsed))
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusUnauthorized {
		resp.Body.Close()
		t.Fatalf("a lapsed token = %d, want 401", resp.StatusCode)
	}
	if ct := resp.Header.Get("Content-Type"); ct != "application/json" {
		t.Errorf("content type = %q, want application/json", ct)
	}
	if e := decode[Error](t, resp); e.Code != "unauthenticated" || e.Message == "" {
		t.Fatalf("refusal = %+v, want code unauthenticated and a message", e)
	}
}

// A 64 kbit/s account's minted URL encodes at 64, and no edit of it
// reaches the engine as anything else.
func TestEditedStreamURLCannotEscapeTheCeiling(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "?limit=1").Items[0].Pid
	_, token, _ := mediaListener(t, h, "capped", map[string]any{
		"download": true, "delete": false, "explicitContent": true, "sharedOutputs": true,
		"managePodcasts": true, "maxTranscodeKbps": 64,
	})
	pi := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-info?maxBitrateKbps=128", token))
	if pi.AppliedBitrateKbps == nil || *pi.AppliedBitrateKbps != 64 {
		t.Fatalf("applied = %v, want the 64 ceiling", pi.AppliedBitrateKbps)
	}
	if code := fetchStatus(t, h, pi.Url); code != 200 || h.flowReq.format != "opus" || h.flowReq.bitrate != "64" {
		t.Fatalf("the minted stream = %d, engine saw %q at %q", code, h.flowReq.format, h.flowReq.bitrate)
	}
	for _, edited := range []string{
		strings.Replace(pi.Url, "fmt=opus", "fmt=flac", 1),
		strings.Replace(strings.Replace(pi.Url, "&br=64", "", 1), "&fmt=opus", "", 1),
		strings.Replace(pi.Url, "br=64", "br=320", 1),
	} {
		if code := fetchStatus(t, h, edited); code != http.StatusUnauthorized {
			t.Errorf("%s = %d, want 401", edited, code)
		}
	}
}

// A minted URL stops opening with every way its account or session can
// end, and with the loss of the item: each fetch re-checks.
func TestMediaTokensStopWhenTheirPrincipalDoes(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "?limit=1").Items[0].Pid
	wantStatus(t, h.putJSON(t, "/api/v1/items/"+pid+"/tags/MOOD", map[string]any{"values": []string{"calm"}}),
		200, "tagging the item")
	// A cover, so the art URL serves before each change and every leg
	// tells a refusal from a miss.
	wantStatus(t, metadataPutBytes(t, h.ts, "/api/v1/items/"+pid+"/artwork", h.token, tinyPNG(t)), 200, "a cover")
	lib := decodeStatus[Library](t, h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "elsewhere", "path": t.TempDir(),
	}), 201, "a library the item is not in")
	allowed := map[string]any{"download": true, "delete": false, "explicitContent": true,
		"sharedOutputs": true, "managePodcasts": true}

	cases := []struct {
		name string
		end  func(id, token, session string)
		want int
	}{
		{"sign out", func(_, token, _ string) {
			wantStatus(t, reqAs(t, h, "POST", "/api/v1/auth/logout", token, nil), 204, "logout")
		}, 401},
		{"session revoked", func(id, _, session string) {
			wantStatus(t, h.deleteReq(t, "/api/v1/users/"+id+"/sessions"), 204, "revoke")
		}, 401},
		{"disabled", func(id, _, _ string) {
			wantStatus(t, h.patchJSON(t, "/api/v1/users/"+id, map[string]any{"disabled": true}), 200, "disable")
		}, 401},
		{"deleted", func(id, _, _ string) {
			wantStatus(t, h.deleteReq(t, "/api/v1/users/"+id), 204, "delete")
		}, 401},
		{"grant narrowed", func(id, _, _ string) {
			wantStatus(t, h.patchJSON(t, "/api/v1/users/"+id, map[string]any{
				"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{lib.Pid}},
			}), 200, "narrow")
		}, 404},
		{"tag deny added", func(id, _, _ string) {
			perms := map[string]any{"tagDeny": []map[string]string{{"key": "MOOD", "value": "calm"}}}
			for k, v := range allowed {
				perms[k] = v
			}
			wantStatus(t, h.patchJSON(t, "/api/v1/users/"+id, map[string]any{"permissions": perms}), 200, "deny")
		}, 404},
	}
	for i, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			id, token, session := mediaListener(t, h, "principal"+string(rune('a'+i)), allowed)
			stream := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-info", token)).Url
			download := decode[DownloadInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/download-info", token)).Files[0].Url
			art, _ := h.media.MintFor(auth.MediaClaims{User: id, Cred: "se:" + session, Purpose: auth.PurposeArt, PID: pid}, 0)
			artURL := "/media/art?pid=" + url.QueryEscape(pid) + "&mt=" + url.QueryEscape(art)
			urls := map[string]string{"stream": stream, "download": download, "art": artURL}
			for kind, u := range urls {
				if code := fetchStatus(t, h, u); code >= 400 {
					t.Fatalf("%s before the change = %d", kind, code)
				}
			}
			tc.end(id, token, session)
			for kind, u := range urls {
				if code := fetchStatus(t, h, u); code != tc.want {
					t.Errorf("%s after %s = %d, want %d", kind, tc.name, code, tc.want)
				}
			}
		})
	}
}

// An account refused download-info gets nothing from /media/download its
// stream does not already give it. Its stream of an original, taken there,
// plays those same bytes inline, as the stream route passes them through
// (the route takes such a token whatever the engine is doing, so a direct
// URL minted in an outage outlives it); a stream the engine shapes, a
// capped transcode, opens nothing there; and a download is refused.
func TestNoDownloadAccountGetsNoDownloadFromTheDownloadRoute(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "?limit=1").Items[0].Pid
	id, token, session := mediaListener(t, h, "streamonly", map[string]any{
		"download": false, "delete": false, "explicitContent": true, "sharedOutputs": true, "managePodcasts": true,
	})
	wantStatus(t, get(t, h.ts, "/api/v1/items/"+pid+"/download-info", token), 403, "download-info")
	pi := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-info", token))
	swapped := strings.Replace(pi.Url, "/media/stream?", "/media/download?", 1)
	resp, err := http.Get(h.ts.URL + swapped)
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK || !strings.HasPrefix(resp.Header.Get("Content-Disposition"), "inline") {
		t.Errorf("the stream of an original on the download route = %d %q, want 200 inline",
			resp.StatusCode, resp.Header.Get("Content-Disposition"))
	}
	capped := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-info?maxBitrateKbps=96", token))
	if !strings.Contains(capped.Url, "br=96") {
		t.Fatalf("the capped mint = %s, want a capped stream", capped.Url)
	}
	if code := fetchStatus(t, h, strings.Replace(capped.Url, "/media/stream?", "/media/download?", 1)); code != http.StatusUnauthorized {
		t.Errorf("a capped stream on the download route = %d, want 401", code)
	}
	// A download token from before the right was withdrawn stops too.
	dl, _ := h.media.MintFor(auth.MediaClaims{User: id, Cred: "se:" + session, Purpose: auth.PurposeDownload, PID: pid}, 0)
	if code := fetchStatus(t, h, "/media/download?pid="+url.QueryEscape(pid)+"&mt="+url.QueryEscape(dl)); code != http.StatusForbidden {
		t.Errorf("a download token without the right = %d, want 403", code)
	}
}

// Without the engine the originals stream through /media/download, so
// the route takes a stream token there, inline, as streaming always did.
func TestEngineLessStreamTokenStillPlaysFromTheDownloadRoute(t *testing.T) {
	t.Parallel()
	h := newHarnessDirect(t)
	pid := h.items(t, "?limit=1").Items[0].Pid
	pi := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/play-info", h.token))
	if !strings.HasPrefix(pi.Url, "/media/download?") {
		t.Fatalf("engine-less play-info = %s", pi.Url)
	}
	resp, err := http.Get(h.ts.URL + pi.Url)
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || !strings.HasPrefix(resp.Header.Get("Content-Disposition"), "inline") {
		t.Errorf("engine-less stream = %d %q, want 200 inline", resp.StatusCode, resp.Header.Get("Content-Disposition"))
	}
	info := decode[DownloadInfo](t, get(t, h.ts, "/api/v1/items/"+pid+"/download-info", h.token))
	resp, err = http.Get(h.ts.URL + info.Files[0].Url)
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 200 || !strings.HasPrefix(resp.Header.Get("Content-Disposition"), "attachment") {
		t.Errorf("engine-less download = %d %q, want 200 attachment", resp.StatusCode, resp.Header.Get("Content-Disposition"))
	}
}

// /rest/download is the untouched original or a refusal, by the download
// right, never a transcode on maxBitRate, and the URL it hands out dies
// with the app password that asked.
func TestRestDownloadHonoursThePermission(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	pid := h.items(t, "?limit=1").Items[0].Pid
	appPassword := func(token string) (string, string) {
		t.Helper()
		resp := reqAs(t, h, "POST", "/api/v1/users/me/app-passwords", token, map[string]any{"label": "client"})
		created := decode[AppPasswordCreated](t, resp)
		return created.Secret, created.Id
	}
	noRedirect := &http.Client{CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	rest := func(username, secret, query string) *http.Response {
		t.Helper()
		sum := md5.Sum([]byte(secret + "salt"))
		resp, err := noRedirect.Get(h.ts.URL + "/rest/download?u=" + username + "&t=" + hex.EncodeToString(sum[:]) +
			"&s=salt&v=1.16.1&c=test&f=json&id=" + url.QueryEscape(pid) + query)
		if err != nil {
			t.Fatal(err)
		}
		return resp
	}

	_, refusedToken, _ := mediaListener(t, h, "nodl", map[string]any{
		"download": false, "delete": false, "explicitContent": true, "sharedOutputs": true, "managePodcasts": true,
	})
	refusedSecret, _ := appPassword(refusedToken)
	var refused struct {
		Status string `json:"status"`
		Error  struct {
			Code int `json:"code"`
		} `json:"error"`
	}
	decodeSubsonicBody(t, rest("nodl", refusedSecret, ""), &refused)
	if refused.Status != "failed" || refused.Error.Code != 50 {
		t.Errorf("a download without the right = %+v, want error 50", refused)
	}

	_, token, _ := mediaListener(t, h, "dl", map[string]any{
		"download": true, "delete": false, "explicitContent": true, "sharedOutputs": true, "managePodcasts": true,
	})
	secret, apID := appPassword(token)
	resp := rest("dl", secret, "&maxBitRate=64&format=mp3")
	resp.Body.Close()
	if resp.StatusCode != http.StatusFound || !strings.HasPrefix(resp.Header.Get("Location"), "/media/download?") {
		t.Fatalf("a download = %d to %q, want a redirect to the original", resp.StatusCode, resp.Header.Get("Location"))
	}
	location := resp.Header.Get("Location")
	if code := fetchStatus(t, h, location); code != 200 {
		t.Fatalf("the original = %d", code)
	}
	if h.flowReq.format != "" {
		t.Errorf("a download reached the engine as %q", h.flowReq.format)
	}
	wantStatus(t, reqAs(t, h, "DELETE", "/api/v1/users/me/app-passwords/"+apID, token, nil), 204, "revoke the app password")
	if code := fetchStatus(t, h, location); code != http.StatusUnauthorized {
		t.Errorf("the URL after its app password was revoked = %d, want 401", code)
	}
}

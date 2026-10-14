package api

import (
	"io"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"testing"
)

// The landing page's readers are the least likely to speak the instance
// owner's language, so its chrome and its expiry stamp follow
// Accept-Language. The shared title and the media do not: those are the
// owner's words and the owner's bytes.
func TestSharePageSpeaksTheReadersLanguage(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	h.rescanAndWait(t)

	tracks := h.items(t, "?limit=1")
	if len(tracks.Items) < 1 {
		t.Fatalf("scanned %d items, want at least 1", len(tracks.Items))
	}
	hours := 48
	resp := h.postJSON(t, "/api/v1/shares", map[string]any{
		"pid":            tracks.Items[0].Pid,
		"expiresInHours": hours,
	})
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("create share status = %d, want 201", resp.StatusCode)
	}
	share := decode[Share](t, resp)
	if share.ExpiresAt == nil {
		t.Fatal("share carries no expiry; the stamp is half of what this tests")
	}

	page := func(t *testing.T, acceptLanguage string) string {
		t.Helper()
		req, err := http.NewRequest(http.MethodGet, h.ts.URL+share.Url, nil)
		if err != nil {
			t.Fatal(err)
		}
		if acceptLanguage != "" {
			req.Header.Set("Accept-Language", acceptLanguage)
		}
		got, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		body, _ := io.ReadAll(got.Body)
		got.Body.Close()
		if got.StatusCode != 200 {
			t.Fatalf("landing page status = %d, want 200", got.StatusCode)
		}
		// Without this a shared cache would hand one reader's language
		// to the next reader.
		if v := got.Header.Get("Vary"); !strings.Contains(v, "Accept-Language") {
			t.Errorf("Vary = %q, want it to name Accept-Language", v)
		}
		return string(body)
	}

	// No header at all is the fallback, and it is byte-for-byte what the
	// page said before it was negotiated.
	en := page(t, "")
	if !strings.Contains(en, `<html lang="en">`) || !strings.Contains(en, "Shared with WaxDeck") {
		t.Errorf("fallback page = %.300s", en)
	}
	enStamp := share.ExpiresAt.UTC().Format("Jan 2, 2006")
	if !strings.Contains(en, "link expires "+enStamp) {
		t.Errorf("fallback page does not stamp %q: %.300s", enStamp, en)
	}

	es := page(t, "es-MX,es;q=0.9,en;q=0.5")
	if !strings.Contains(es, `<html lang="es">`) || !strings.Contains(es, "Compartido con WaxDeck") {
		t.Errorf("es page = %.300s", es)
	}
	// The stamp is worded too, or a Spanish page still says "Aug".
	esMonths := [12]string{"ene", "feb", "mar", "abr", "may", "jun", "jul", "ago", "sept", "oct", "nov", "dic"}
	at := share.ExpiresAt.UTC()
	esStamp := "el enlace caduca el " + strconv.Itoa(at.Day()) + " " +
		esMonths[at.Month()-1] + " " + strconv.Itoa(at.Year())
	if !strings.Contains(es, esStamp) {
		t.Errorf("es page does not stamp %q: %.300s", esStamp, es)
	}

	// A language the server has no table for reads English rather than
	// an empty page.
	if fr := page(t, "fr"); !strings.Contains(fr, "Shared with WaxDeck") {
		t.Errorf("unsupported language did not fall back: %.300s", fr)
	}

	// A revoked link's page is localized too: it is the page a reader is
	// most likely to hit, since it outlives the share.
	if resp := h.deleteReq(t, "/api/v1/shares/"+share.Pid); resp.StatusCode != 204 {
		resp.Body.Close()
		t.Fatalf("revoke status = %d, want 204", resp.StatusCode)
	}
	req, err := http.NewRequest(http.MethodGet, h.ts.URL+share.Url, nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Accept-Language", "es")
	gone, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	body, _ := io.ReadAll(gone.Body)
	gone.Body.Close()
	if gone.StatusCode != 404 {
		t.Fatalf("revoked link status = %d, want 404", gone.StatusCode)
	}
	if !strings.Contains(string(body), `<html lang="es">`) ||
		!strings.Contains(string(body), "Este enlace no existe") {
		t.Errorf("revoked-link page = %s", body)
	}
}

// TestShareOversightListing is the acceptance for the console's share
// section: an administrator sees every account's links with a name
// against each, a listener sees only their own and no names at all, and
// the wide listing is administrative.
func TestShareOversightListing(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	h.rescanAndWait(t)

	tracks := h.items(t, "?limit=2")
	if len(tracks.Items) < 2 {
		t.Fatalf("scanned %d items, want at least 2", len(tracks.Items))
	}
	adminTrack, samTrack := tracks.Items[0].Pid, tracks.Items[1].Pid

	resp := h.postJSON(t, "/api/v1/shares", map[string]any{"pid": adminTrack})
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("admin create share status = %d, want 201", resp.StatusCode)
	}
	adminShare := decode[Share](t, resp)

	resp = h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "sam", "password": testPassword, "displayName": "Sam Gamgee",
	})
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("create user status = %d, want 201", resp.StatusCode)
	}
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword)

	resp = postJSON(t, h.ts.URL+"/api/v1/shares", sam.Token, `{"pid":"`+samTrack+`"}`)
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("sam create share status = %d, want 201", resp.StatusCode)
	}
	samShare := decode[Share](t, resp)

	// A listener's own listing holds their link alone, and names nobody:
	// every row would say "Sam Gamgee", which is not a fact about a row.
	mine := decode[SharePage](t, get(t, h.ts, "/api/v1/shares", sam.Token))
	if len(mine.Shares) != 1 || mine.Shares[0].Pid != samShare.Pid {
		t.Fatalf("sam's own listing = %+v, want just %s", mine.Shares, samShare.Pid)
	}
	if mine.Shares[0].Owner != nil {
		t.Fatalf("personal listing names an owner: %q", *mine.Shares[0].Owner)
	}

	// The wide listing is administrative, and refusing it is a 403
	// rather than an empty page: the caller asked for something they may
	// not have, and saying "nothing here" would be a different answer.
	wantStatus(t, get(t, h.ts, "/api/v1/shares?all=true", sam.Token), 403, "sam lists everyone")

	// The administrator's own listing is still their own.
	own := decode[SharePage](t, get(t, h.ts, "/api/v1/shares", h.token))
	if len(own.Shares) != 1 || own.Shares[0].Pid != adminShare.Pid {
		t.Fatalf("admin's own listing = %+v, want just %s", own.Shares, adminShare.Pid)
	}
	if own.Shares[0].Owner != nil {
		t.Fatalf("admin's own listing names an owner: %q", *own.Shares[0].Owner)
	}

	all := decode[SharePage](t, get(t, h.ts, "/api/v1/shares?all=true", h.token))
	owners := map[string]string{}
	for _, s := range all.Shares {
		if s.Owner == nil {
			t.Fatalf("share %s has no owner on the wide listing", s.Pid)
		}
		owners[s.Pid] = *s.Owner
	}
	if len(all.Shares) != 2 {
		t.Fatalf("wide listing = %d shares, want 2", len(all.Shares))
	}
	// A display name where there is one, the username where there is
	// not: the built-in admin has no display name set.
	if owners[samShare.Pid] != "Sam Gamgee" {
		t.Fatalf("sam's share names %q, want %q", owners[samShare.Pid], "Sam Gamgee")
	}
	if owners[adminShare.Pid] != "admin" {
		t.Fatalf("admin's share names %q, want %q", owners[adminShare.Pid], "admin")
	}

	// Revoke is what makes the listing an answer rather than a report,
	// and the endpoint already allowed an administrator somebody else's
	// link. The revoked one leaves the listing.
	wantStatus(t, h.deleteReq(t, "/api/v1/shares/"+samShare.Pid), 204, "admin revokes sam's link")
	all = decode[SharePage](t, get(t, h.ts, "/api/v1/shares?all=true", h.token))
	if len(all.Shares) != 1 || all.Shares[0].Pid != adminShare.Pid {
		t.Fatalf("after revoke the wide listing = %+v, want just %s", all.Shares, adminShare.Pid)
	}
}

// restrictedAccount creates an account granted no library at all and
// returns its token.
func restrictedAccount(t *testing.T, h *harness, username string) string {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": username, "password": testPassword,
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{}},
	})
	if resp.StatusCode != 201 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("create %s status = %d: %s", username, resp.StatusCode, body)
	}
	resp.Body.Close()
	return loginAs(t, h.ts, username, testPassword).Token
}

// An account that can read none of the library imports nothing it cannot
// see, by name, by portable refs or by M3U path, so a list it shares
// publishes nothing hidden; and neither export of somebody else's shared
// list hands it a hidden member.
func TestRestrictedAccountCannotPublishWhatItCannotSee(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	track := h.items(t, "?mediaType=music").Items[0]
	resp := h.postJSON(t, "/api/v1/playlists", map[string]any{
		"name": "Source", "kind": "static", "visibility": "shared", "itemPids": []string{track.Pid},
	})
	src := decode[Playlist](t, resp)
	resp = get(t, h.ts, "/api/v1/playlists/"+src.Pid+"/m3u", h.token)
	doc, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	portable := decode[PortablePlaylist](t, get(t, h.ts, "/api/v1/playlists/"+src.Pid+"/portable", h.token))

	carol := restrictedAccount(t, h, "carol")
	for _, body := range []map[string]any{
		{"source": "text", "payload": deref(track.Artist) + " - " + track.Title},
		{"source": "portable", "refs": portable.Refs},
	} {
		resp = reqAs(t, h, "POST", "/api/v1/playlists/import", carol, body)
		got := decode[PlaylistImportResult](t, resp)
		if got.Resolved != 0 || got.PlaylistPid != nil {
			t.Errorf("%s import = %+v, want nothing resolved", body["source"], got)
		}
	}
	resp = reqAs(t, h, "POST", "/api/v1/playlists/m3u", carol, map[string]any{
		"name": "Paths", "content": string(doc),
	})
	m3u := decode[M3uImportResult](t, resp)
	if m3u.Matched != 0 || m3u.Unmatched != 1 {
		t.Errorf("m3u import = matched %d unmatched %d, want 0/1", m3u.Matched, m3u.Unmatched)
	}

	resp = reqAs(t, h, "POST", "/api/v1/shares", carol, map[string]any{"pid": m3u.Playlist.Pid})
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("sharing the imported list = %d, want 201", resp.StatusCode)
	}
	share := decode[Share](t, resp)
	wantStatus(t, get(t, h.ts, share.Url+"/stream?i=0", ""), 404, "the anonymous stream of the shared import")

	// The admin's shared list, exported by an account that cannot see
	// its one member, names nothing.
	resp = reqAs(t, h, "GET", "/api/v1/playlists/"+src.Pid+"/m3u", carol, nil)
	theirs, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if strings.Contains(string(theirs), "#EXTINF") {
		t.Errorf("a restricted reader's m3u export names hidden members:\n%s", theirs)
	}
	if refs := decode[PortablePlaylist](t, reqAs(t, h, "GET", "/api/v1/playlists/"+src.Pid+"/portable", carol, nil)).Refs; len(refs) != 0 {
		t.Errorf("a restricted reader's portable export carries %d refs, want none", len(refs))
	}
}

// TestShareStopsWhenItsOwnerIsDisabled: a link serves under its owner's
// current reach, so disabling the owner stops every route of it, and
// re-enabling them brings it back.
func TestShareStopsWhenItsOwnerIsDisabled(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	track := h.items(t, "?mediaType=music").Items[0]
	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "dana", "password": testPassword})
	dana := decode[UserAccount](t, resp)
	token := loginAs(t, h.ts, "dana", testPassword).Token
	resp = reqAs(t, h, "POST", "/api/v1/shares", token, map[string]any{"pid": track.Pid, "allowDownload": true})
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("share status = %d", resp.StatusCode)
	}
	share := decode[Share](t, resp)
	routes := []string{share.Url, share.Url + "/stream?i=0", share.Url + "/download?i=0"}
	for _, route := range routes {
		resp := get(t, h.ts, route, "")
		resp.Body.Close()
		if resp.StatusCode >= 400 {
			t.Fatalf("%s before the disable = %d", route, resp.StatusCode)
		}
	}

	resp = h.patchJSON(t, "/api/v1/users/"+dana.Id, map[string]any{"disabled": true})
	resp.Body.Close()
	for _, route := range routes {
		wantStatus(t, get(t, h.ts, route, ""), 404, route+" of a disabled owner")
	}
	resp = h.patchJSON(t, "/api/v1/users/"+dana.Id, map[string]any{"disabled": false})
	resp.Body.Close()
	resp = get(t, h.ts, share.Url+"/stream?i=0", "")
	resp.Body.Close()
	if resp.StatusCode >= 400 {
		t.Errorf("the stream after re-enabling = %d", resp.StatusCode)
	}
}

// kidAccount creates an account whose only narrowing is a tag deny on
// the advisory flag (the admin screen's kids preset) and returns its
// token.
func kidAccount(t *testing.T, h *harness, username string) string {
	t.Helper()
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": username, "password": testPassword,
		"permissions": map[string]any{
			"tagDeny": []map[string]string{{"key": "ITUNESADVISORY", "value": "1"}},
		},
	})
	if resp.StatusCode != 201 {
		body, _ := io.ReadAll(resp.Body)
		resp.Body.Close()
		t.Fatalf("create %s status = %d: %s", username, resp.StatusCode, body)
	}
	resp.Body.Close()
	return loginAs(t, h.ts, username, testPassword).Token
}

// flagExplicit tags the items explicit as the administrator.
func flagExplicit(t *testing.T, h *harness, pids ...string) {
	t.Helper()
	for _, pid := range pids {
		wantStatus(t, putJSON(t, h.ts, "/api/v1/items/"+pid+"/tags/ITUNESADVISORY", h.token,
			map[string]any{"values": []string{"1"}}), 200, "flagging "+pid)
	}
}

// A kids preset account cannot share an album its deny rule hides, and a
// link it minted before the rule stops too.
func TestKidCannotShareAnAlbumItCannotHear(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	items := h.items(t, "?mediaType=music").Items
	album := deref(items[0].AlbumPid)
	var members []string
	for _, it := range items {
		if deref(it.AlbumPid) == album {
			members = append(members, it.Pid)
		}
	}
	title := decode[AlbumDetail](t, get(t, h.ts, "/api/v1/albums/"+album, h.token)).Title
	kid := kidAccount(t, h, "kid")
	resp := reqAs(t, h, "POST", "/api/v1/shares", kid, map[string]any{"pid": album})
	if resp.StatusCode != 201 {
		resp.Body.Close()
		t.Fatalf("sharing the album before any rule bites = %d, want 201", resp.StatusCode)
	}
	early := decode[Share](t, resp)

	flagExplicit(t, h, members...)
	wantStatus(t, reqAs(t, h, "POST", "/api/v1/shares", kid, map[string]any{"pid": album}),
		404, "sharing an album every track of which the account's rules deny")
	wantStatus(t, get(t, h.ts, early.Url+"/stream?i=0", ""), 404, "the earlier link's anonymous stream")
	wantStatus(t, reqAs(t, h, "GET", "/api/v1/albums/"+album, kid, nil), 404, "the denied album's detail")
	hits := decode[SearchResults](t, reqAs(t, h, "GET", "/api/v1/library/search?q="+url.QueryEscape(title), kid, nil))
	for _, a := range hits.Albums {
		if a.Pid == album {
			t.Errorf("the denied album is a search hit for the kid: %+v", a)
		}
	}
}

// A share's cover is revalidated on every use rather than cached as is:
// a link revoked, expired or gone dormant stops serving it with the rest
// of the share, while an unchanged cover costs only a 304.
func TestShareArtIsRevalidatedEveryTime(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	track := h.items(t, "?mediaType=music").Items[0]
	wantStatus(t, metadataPutBytes(t, h.ts, "/api/v1/items/"+track.Pid+"/artwork", h.token, tinyPNG(t)), 200, "set a cover")
	share := decodeStatus[Share](t, h.postJSON(t, "/api/v1/shares", map[string]any{"pid": track.Pid}), 201, "share it")
	art := func(etag string) *http.Response {
		t.Helper()
		req, _ := http.NewRequest(http.MethodGet, h.ts.URL+share.Url+"/art", nil)
		if etag != "" {
			req.Header.Set("If-None-Match", etag)
		}
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		return resp
	}
	first := art("")
	etag := first.Header.Get("ETag")
	if first.StatusCode != 200 || etag == "" || !strings.Contains(first.Header.Get("Cache-Control"), "no-cache") {
		t.Fatalf("share art = %d, ETag %q, Cache-Control %q; want 200, a validator, no-cache",
			first.StatusCode, etag, first.Header.Get("Cache-Control"))
	}
	wantStatus(t, art(etag), http.StatusNotModified, "revalidating an unchanged cover")
	wantStatus(t, art("W/"+etag), http.StatusNotModified, "revalidating with the weak form")
	wantStatus(t, art(`"elsewhere", `+etag), http.StatusNotModified, "revalidating with a list")
	wantStatus(t, h.deleteReq(t, "/api/v1/shares/"+share.Pid), 204, "revoke the share")
	wantStatus(t, art(etag), 404, "revalidating after the revoke")
}

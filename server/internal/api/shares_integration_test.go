package api

import (
	"io"
	"net/http"
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

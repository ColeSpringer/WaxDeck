package api

import "testing"

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

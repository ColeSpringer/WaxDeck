package api

import (
	"testing"
)

// Every signed-in account's session says whether the server is read-only,
// so the app can say why an edit is refused before anyone tries one; the
// refusal itself names the server, not a library.
func TestTheSessionSaysWhenTheServerIsReadOnly(t *testing.T) {
	t.Parallel()
	h := newHarnessDirect(t)
	wantStatus(t, h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "sam", "password": testPassword,
	}), 201, "create a member")
	sam := loginAs(t, h.ts, "sam", testPassword)

	session := func(token string) SessionInfo {
		t.Helper()
		return decode[SessionInfo](t, get(t, h.ts, "/api/v1/auth/session", token))
	}
	wantReadOnly := func(want bool, when string) {
		t.Helper()
		for who, token := range map[string]string{"administrator": h.token, "member": sam.Token} {
			info := session(token)
			if info.Server == nil {
				t.Fatalf("%s: the %s's session carries no server state", when, who)
			}
			if info.Server.ReadOnly != want {
				t.Fatalf("%s: the %s's session says readOnly = %v, want %v", when, who, info.Server.ReadOnly, want)
			}
		}
	}

	wantReadOnly(false, "before the switch")
	if anon := session(""); anon.Authenticated || anon.Server != nil {
		t.Fatalf("an anonymous session = %+v, want no account and no server state", anon)
	}

	settings := decode[AdminSettings](t, get(t, h.ts, "/api/v1/admin/settings", h.token))
	settings.ReadOnly = true
	wantStatus(t, h.putJSON(t, "/api/v1/admin/settings", settings), 200, "turn read-only on")
	wantReadOnly(true, "with the switch on")

	// A write is refused in the server's words.
	resp := h.postJSON(t, "/api/v1/uploads", map[string]any{
		"fileName": "nope.mp3", "sizeBytes": 1024, "mediaType": "music",
	})
	if resp.StatusCode != 409 {
		t.Fatalf("upload while read-only = %d, want 409", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "read-only" || e.Message != "the server is in read-only mode" {
		t.Fatalf("refusal = %+v, want read-only in the server's words", e)
	}

	settings.ReadOnly = false
	wantStatus(t, h.putJSON(t, "/api/v1/admin/settings", settings), 200, "turn read-only off")
	wantReadOnly(false, "with the switch off again")
}

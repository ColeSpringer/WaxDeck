package api

import "testing"

// TestOrganizeProfilesAndPreview covers the profile listing (the
// upstream built-in ships in every profile set) and the preview and
// apply validation paths. The harness roots are in-place, so organize
// has no managed library to lay out; upstream reports that as an
// invalid request, which is the honest answer here too.
func TestOrganizeProfilesAndPreview(t *testing.T) {
	h := newHarness(t)

	resp := get(t, h.ts, "/api/v1/organize/profiles", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("profiles status = %d", resp.StatusCode)
	}
	profiles := decode[OrganizeProfiles](t, resp).Profiles
	found := false
	for _, p := range profiles {
		if p.Name == "waxbin-native" {
			found = true
		}
	}
	if !found {
		t.Fatalf("profiles = %+v, want the waxbin-native built-in", profiles)
	}

	// An unknown profile answers invalid-request, not a 404.
	resp = h.postJSON(t, "/api/v1/organize/preview", map[string]any{"profile": "no-such-profile"})
	if resp.StatusCode != 400 {
		t.Fatalf("unknown-profile preview status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "invalid-request" {
		t.Fatalf("unknown-profile code = %q, want invalid-request", e.Code)
	}

	// A known profile with no managed library: upstream refuses the
	// plan as invalid.
	resp = h.postJSON(t, "/api/v1/organize/preview", map[string]any{"profile": "waxbin-native"})
	if resp.StatusCode != 400 {
		t.Fatalf("in-place preview status = %d, want 400", resp.StatusCode)
	}
	resp.Body.Close()

	resp = h.postJSON(t, "/api/v1/organize/apply", map[string]any{"profile": "no-such-profile"})
	if resp.StatusCode != 400 {
		t.Fatalf("unknown-profile apply status = %d, want 400", resp.StatusCode)
	}
	resp.Body.Close()

	// A malformed scoped pid refuses before planning.
	resp = h.postJSON(t, "/api/v1/organize/preview", map[string]any{
		"profile": "waxbin-native", "itemPids": []string{"garbage"},
	})
	if resp.StatusCode != 400 {
		t.Fatalf("bad scoped pid status = %d, want 400", resp.StatusCode)
	}
	resp.Body.Close()
}

// TestOrganizeAdminGates checks every organize surface is admin-only.
func TestOrganizeAdminGates(t *testing.T) {
	h := newHarness(t)
	resp := h.postJSON(t, "/api/v1/users", map[string]any{"username": "sam", "password": testPassword})
	if resp.StatusCode != 201 {
		t.Fatalf("creating user: status %d", resp.StatusCode)
	}
	resp.Body.Close()
	sam := loginAs(t, h.ts, "sam", testPassword).Token

	if resp := get(t, h.ts, "/api/v1/organize/profiles", sam); resp.StatusCode != 403 {
		t.Fatalf("profiles as non-admin: status %d, want 403", resp.StatusCode)
	}
	for _, path := range []string{"/api/v1/organize/preview", "/api/v1/organize/apply"} {
		resp := reqAs(t, h, "POST", path, sam, map[string]any{"profile": "waxbin-native"})
		if resp.StatusCode != 403 {
			t.Fatalf("%s as non-admin: status %d, want 403", path, resp.StatusCode)
		}
		resp.Body.Close()
	}
}

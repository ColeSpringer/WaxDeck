package api

import (
	"testing"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// TestOrganizeProfilesAndPreview covers the profile listing (the
// upstream built-in ships in every profile set) and the preview and
// apply validation paths. The harness roots are in-place, so organize
// has no managed library to lay out; upstream reports that as an
// invalid request, which is the honest answer here too.
func TestOrganizeProfilesAndPreview(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	resp := get(t, h.ts, "/api/v1/organize/profiles", h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("profiles status = %d", resp.StatusCode)
	}
	listing := decode[OrganizeProfiles](t, resp)
	if listing.ManagedLibraries != 0 {
		t.Fatalf("managedLibraries = %d, want none on in-place roots", listing.ManagedLibraries)
	}
	profiles := listing.Profiles
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
	t.Parallel()
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
	for _, path := range []string{"/api/v1/organize/preview", "/api/v1/organize/apply", "/api/v1/organize/profiles/preview"} {
		resp := reqAs(t, h, "POST", path, sam, map[string]any{"profile": "waxbin-native"})
		if resp.StatusCode != 403 {
			t.Fatalf("%s as non-admin: status %d, want 403", path, resp.StatusCode)
		}
		resp.Body.Close()
	}
	for _, method := range []string{"PUT", "DELETE"} {
		resp := reqAs(t, h, method, "/api/v1/organize/profiles/flat", sam, map[string]any{})
		if resp.StatusCode != 403 {
			t.Fatalf("%s a profile as non-admin: status %d, want 403", method, resp.StatusCode)
		}
		resp.Body.Close()
	}
}

// A saved profile lists with its sample, a managed library can be laid
// out by it, and it cannot be deleted while one is.
func TestOrganizeProfilesAreEditedAtRuntime(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})
	resp := h.putJSON(t, "/api/v1/organize/profiles/flat", map[string]any{"musicTemplate": "{title}.{ext}"})
	if saved := decode[OrganizeProfile](t, resp); resp.StatusCode != 200 || saved.MusicTemplate != "{title}.{ext}" ||
		saved.BuiltIn || saved.Sample.Music != "Amber Waves.flac" || saved.AudiobookTemplate == "" {
		t.Fatalf("saved = %d %+v, want the profile with its sample", resp.StatusCode, saved)
	}
	builtIn := map[string]bool{}
	for _, p := range decode[OrganizeProfiles](t, get(t, h.ts, "/api/v1/organize/profiles", h.token)).Profiles {
		builtIn[p.Name] = p.BuiltIn
	}
	if b, ok := builtIn["flat"]; !ok || b || !builtIn["waxbin-native"] {
		t.Fatalf("listed = %v, want flat saved beside the built-in", builtIn)
	}
	resp = h.postJSON(t, "/api/v1/organize/profiles/preview", map[string]any{"podcastTemplate": "{podcast}/{episode}.{ext}"})
	if sample := decode[OrganizeSample](t, resp); resp.StatusCode != 200 || sample.Podcast != "Night Shift Radio/The Lighthouse Keeper.mp3" {
		t.Fatalf("preview = %d %+v, want the podcast sample", resp.StatusCode, sample)
	}
	wantStatus(t, h.putJSON(t, "/api/v1/organize/profiles/bad", map[string]any{"musicTemplate": "{nope}"}), 400, "a bad template")

	lib := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries[0]
	resp = h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/profile", map[string]any{"profile": "flat"})
	if got := decode[Library](t, resp); resp.StatusCode != 200 || deref(got.Profile) != "flat" {
		t.Fatalf("library profile = %d %+v, want flat", resp.StatusCode, got)
	}
	wantStatus(t, h.deleteReq(t, "/api/v1/organize/profiles/flat"), 409, "delete a profile in use")
	wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/profile", map[string]any{"profile": "waxbin-native"}), 200, "move the library back")
	wantStatus(t, h.deleteReq(t, "/api/v1/organize/profiles/flat"), 204, "delete a profile nothing uses")
	wantStatus(t, h.deleteReq(t, "/api/v1/organize/profiles/waxbin-native"), 400, "delete the built-in")
	wantStatus(t, h.deleteReq(t, "/api/v1/organize/profiles/gone"), 404, "delete an unknown profile")
	wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/profile", map[string]any{"profile": "gone"}), 400, "an unknown profile")
}

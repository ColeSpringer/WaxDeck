package api

import (
	"testing"
)

// TestCreateLibraryRuntime covers the runtime library-root admin endpoint:
// an admin registers a new root and it joins the library list under the
// configured name and media; a duplicate name is a clean conflict; a
// missing path is rejected up front; and a non-admin cannot create one.
func TestCreateLibraryRuntime(t *testing.T) {
	h := newHarness(t)
	newRoot := t.TempDir()

	// Admin creates a library at runtime: 201 with the created library.
	resp := h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name":    "extra",
		"path":    newRoot,
		"media":   "music",
		"managed": false,
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create library status = %d, want 201", resp.StatusCode)
	}
	lib := decode[Library](t, resp)
	if lib.Name != "extra" {
		t.Fatalf("created name = %q, want extra", lib.Name)
	}
	if lib.Media == nil || *lib.Media != "music" {
		t.Fatalf("created media = %v, want music", lib.Media)
	}
	if lib.Pid == "" {
		t.Fatalf("created library has no pid")
	}

	// It joins the library list under the configured name, not the dir base.
	libs := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries
	var found bool
	for _, l := range libs {
		if l.Pid == lib.Pid {
			found = true
			if l.Name != "extra" {
				t.Fatalf("listed name = %q, want extra", l.Name)
			}
		}
	}
	if !found {
		t.Fatalf("created library %s absent from the list", lib.Pid)
	}

	// A duplicate name is a clean 409: the name is the stream-ref mapping key,
	// so a second one would be ambiguous.
	resp = h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "extra",
		"path": t.TempDir(),
	})
	wantStatus(t, resp, 409, "duplicate name")

	// A missing path is rejected up front.
	resp = h.postJSON(t, "/api/v1/libraries", map[string]any{"name": "nopath"})
	wantStatus(t, resp, 400, "missing path")

	// A non-admin cannot create a library.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "listener", "password": "long-enough-pw",
	})
	wantStatus(t, resp, 201, "create non-admin user")
	userToken := loginAs(t, h.ts, "listener", "long-enough-pw").Token
	resp = reqAs(t, h, "POST", "/api/v1/libraries", userToken, map[string]any{
		"name": "sneaky", "path": t.TempDir(),
	})
	wantStatus(t, resp, 403, "non-admin create")
}

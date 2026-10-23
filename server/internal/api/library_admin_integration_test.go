package api

import (
	"path/filepath"
	"testing"
)

// TestCreateLibraryRuntime covers the runtime library-root admin endpoint:
// an admin registers a new root and it joins the library list under the
// configured name and media; a duplicate name is a clean conflict; a
// missing path is rejected up front; and a non-admin cannot create one.
func TestCreateLibraryRuntime(t *testing.T) {
	t.Parallel()
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
	lib := decode[LibraryCreated](t, resp)
	if lib.Name != "extra" {
		t.Fatalf("created name = %q, want extra", lib.Name)
	}
	if lib.ScanStarted == nil || !*lib.ScanStarted {
		t.Fatalf("scanStarted = %v with nothing else running, want true", lib.ScanStarted)
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

	// A relative path is refused in WaxDeck's words, not the catalog's.
	resp = h.postJSON(t, "/api/v1/libraries", map[string]any{"name": "rel", "path": "relative/path"})
	if resp.StatusCode != 400 {
		t.Fatalf("relative path status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "invalid-request" || e.Message != "the library path must be absolute" {
		t.Fatalf("relative path answer = %+v, want it refused as not absolute", e)
	}

	// A folder mounted later registers when asked to.
	later := filepath.Join(t.TempDir(), "later")
	resp = h.postJSON(t, "/api/v1/libraries", map[string]any{"name": "later", "path": later})
	wantStatus(t, resp, 400, "absent folder")
	resp = h.postJSON(t, "/api/v1/libraries", map[string]any{"name": "later", "path": later, "allowAbsent": true})
	if resp.StatusCode != 201 {
		t.Fatalf("absent folder with allowAbsent status = %d, want 201", resp.StatusCode)
	}
	if created := decode[LibraryCreated](t, resp); created.Path == nil || *created.Path != later {
		t.Fatalf("absent folder created at %v, want %s", created.Path, later)
	}

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

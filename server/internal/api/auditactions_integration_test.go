package api

import (
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"
)

// The audit log answers "who did what to what, and what changed". These
// are administrative actions whose entries have to say enough: an account
// edit names its fields with their values from and to, a notification
// target change leaves an entry, a library switch names its library as
// well as its pid, and a restored file is named, not only an id.
func TestAdminActionsAreAudited(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	entries := func(action string) []AuditEvent {
		t.Helper()
		return decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action="+action, h.token)).Events
	}
	// detail reads one entry's detail as a map; absent is empty.
	detail := func(e AuditEvent) map[string]any {
		if e.Detail == nil {
			return map[string]any{}
		}
		return *e.Detail
	}
	// change reads one field of an entry's `changes`.
	change := func(t *testing.T, e AuditEvent, field string) (from, to any) {
		t.Helper()
		changes, _ := detail(e)["changes"].(map[string]any)
		pair, ok := changes[field].(map[string]any)
		if !ok {
			t.Fatalf("changes = %v, want an entry for %s", changes, field)
		}
		return pair["from"], pair["to"]
	}
	libs := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries
	if len(libs) == 0 {
		t.Fatal("the harness holds no library")
	}
	lib := libs[0]

	t.Run("an account edit records each field from and to", func(t *testing.T) {
		sam := decodeStatus[UserAccount](t, h.postJSON(t, "/api/v1/users", map[string]any{
			"username": "sam", "password": testPassword,
		}), 201, "create sam")
		perms := sam.Permissions
		perms.Download = false

		wantStatus(t, h.patchJSON(t, "/api/v1/users/"+sam.Id, map[string]any{
			"displayName":   "Sam",
			"uploadEnabled": true,
			"permissions":   perms,
			"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{lib.Pid}},
		}), 200, "edit sam")

		got := entries("user.update")
		if len(got) != 1 || got[0].TargetName == nil || *got[0].TargetName != "sam" {
			t.Fatalf("user.update entries = %+v, want one about sam", got)
		}
		for field, want := range map[string][2]any{
			"displayName":               {"", "Sam"},
			"uploadEnabled":             {false, true},
			"permissions.download":      {true, false},
			"libraryAccess.mode":        {"all", "granted"},
			"libraryAccess.libraryPids": {[]any{}, []any{lib.Pid}},
		} {
			from, to := change(t, got[0], field)
			if !jsonEqual(from, want[0]) || !jsonEqual(to, want[1]) {
				t.Errorf("%s: from %v to %v, want from %v to %v", field, from, to, want[0], want[1])
			}
		}
		// What the edit left alone is not listed, and nothing about the
		// credential is, whatever the account holds.
		changes, _ := detail(got[0])["changes"].(map[string]any)
		for _, left := range []string{"roles", "disabled", "uploadQuotaBytes", "permissions.delete", "password"} {
			if _, ok := changes[left]; ok {
				t.Errorf("changes lists %s, which the edit did not touch: %v", left, changes)
			}
		}
		raw, _ := json.Marshal(detail(got[0]))
		if s := strings.ToLower(string(raw)); strings.Contains(s, "password") || strings.Contains(s, "hash") {
			t.Errorf("the entry mentions a credential: %s", raw)
		}

		// Saving what the account already holds records nothing.
		wantStatus(t, h.patchJSON(t, "/api/v1/users/"+sam.Id, map[string]any{
			"displayName": "Sam", "permissions": perms,
		}), 200, "save sam again")
		if again := entries("user.update"); len(again) != 1 {
			t.Errorf("a save that changed nothing was audited: %+v", again)
		}

		// A flip lists only the flip.
		perms.Download = true
		wantStatus(t, h.patchJSON(t, "/api/v1/users/"+sam.Id, map[string]any{
			"displayName": "Sam", "permissions": perms,
		}), 200, "give sam downloads back")
		flip := entries("user.update")
		if len(flip) != 2 {
			t.Fatalf("user.update entries = %d, want 2", len(flip))
		}
		if changes, _ := detail(flip[0])["changes"].(map[string]any); len(changes) != 1 {
			t.Errorf("a one-toggle edit lists %v, want only permissions.download", changes)
		}
	})

	t.Run("a notification target change names its kind and label, never its address", func(t *testing.T) {
		const secret = "https://hooks.example.net/secret-path-4417"
		created := createTarget(t, h, "/api/v1/admin/notification-targets", h.token, map[string]any{
			"kind": "webhook", "label": "Ops hook", "config": map[string]any{"url": secret},
			"enabledEvents": []string{"signup-requested"},
		})
		resp := reqAs(t, h, "PUT", "/api/v1/admin/notification-targets/"+created.Pid, h.token, map[string]any{
			"label": "Ops hook (paging)", "config": map[string]any{"url": secret},
			"enabledEvents": []string{"signup-requested"},
		})
		wantStatus(t, resp, 200, "rename the target")
		wantStatus(t, reqAs(t, h, "DELETE", "/api/v1/admin/notification-targets/"+created.Pid, h.token, nil),
			204, "delete the target")

		for _, c := range []struct{ action, label string }{
			{"notification-target.create", "Ops hook"},
			{"notification-target.update", "Ops hook (paging)"},
			{"notification-target.delete", "Ops hook (paging)"},
		} {
			got := entries(c.action)
			if len(got) != 1 {
				t.Fatalf("%s entries = %+v, want one", c.action, got)
			}
			e := got[0]
			if e.TargetPid == nil || *e.TargetPid != created.Pid || e.TargetName == nil || *e.TargetName != c.label {
				t.Errorf("%s names %v / %v, want %s / %s", c.action, e.TargetPid, e.TargetName, created.Pid, c.label)
			}
			if d := detail(e); d["kind"] != "webhook" || d["label"] != c.label {
				t.Errorf("%s detail = %v, want kind webhook and label %q", c.action, d, c.label)
			}
			raw, _ := json.Marshal(e)
			if strings.Contains(string(raw), "secret-path") || strings.Contains(string(raw), "hooks.example.net") {
				t.Errorf("%s carries the target's address: %s", c.action, raw)
			}
		}
	})

	t.Run("a library switch names the library it moved", func(t *testing.T) {
		wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/read-only", map[string]any{"readOnly": true}),
			200, "flag read-only")
		wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/read-only", map[string]any{"readOnly": false}),
			200, "release it")
		wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/folder-fallback", map[string]any{"folderFallback": true}),
			200, "turn the folder fallback on")
		wantStatus(t, h.putJSON(t, "/api/v1/libraries/"+lib.Pid+"/matching",
			map[string]any{"mode": "review", "singlesAutoApply": false}), 200, "set matching")

		for _, action := range []string{"library.read-only", "library.folder-fallback", "library.matching"} {
			got := entries(action)
			if len(got) == 0 {
				t.Fatalf("%s left no entry", action)
			}
			for _, e := range got {
				if e.TargetPid == nil || *e.TargetPid != lib.Pid || e.TargetName == nil || *e.TargetName != lib.Name {
					t.Errorf("%s names %v / %v, want %s / %s", action, e.TargetPid, e.TargetName, lib.Pid, lib.Name)
				}
			}
		}
	})

	t.Run("a restore says what came back", func(t *testing.T) {
		doomed := h.items(t, "?mediaType=music").Items[0]
		wantStatus(t, h.postJSON(t, "/api/v1/library/items/delete", map[string]any{
			"pids": []string{doomed.Pid}, "mode": "trash",
		}), 200, "delete to the trash")
		trash := decode[TrashList](t, get(t, h.ts, "/api/v1/admin/trash", h.token)).Entries
		if len(trash) != 1 {
			t.Fatalf("trash entries = %d, want 1", len(trash))
		}
		wantStatus(t, h.postJSON(t, "/api/v1/admin/trash/"+trash[0].Id+"/restore", nil), 204, "restore")

		got := entries("trash.restore")
		if len(got) != 1 || got[0].TargetPid == nil || *got[0].TargetPid != trash[0].Id {
			t.Fatalf("trash.restore entries = %+v, want one for %s", got, trash[0].Id)
		}
		e := got[0]
		if base := filepath.Base(trash[0].Name); e.TargetName == nil || *e.TargetName != base {
			t.Errorf("trash.restore names %v, want the restored file %q", e.TargetName, base)
		}
		d := detail(e)
		if d["path"] != trash[0].Name || d["reason"] != trash[0].Reason || d["library"] != lib.Name ||
			d["sizeBytes"] != float64(trash[0].SizeBytes) {
			t.Errorf("trash.restore detail = %v, want path %q, reason %q, library %q, size %d",
				d, trash[0].Name, trash[0].Reason, lib.Name, trash[0].SizeBytes)
		}
	})
}

// jsonEqual compares two decoded JSON values by their encoding, so an
// empty list equals an empty list however each side was built.
func jsonEqual(a, b any) bool {
	x, _ := json.Marshal(a)
	y, _ := json.Marshal(b)
	return string(x) == string(y)
}

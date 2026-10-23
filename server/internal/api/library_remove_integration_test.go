package api

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// The listing says which library the server's configuration names, and
// a managed one the server cannot write is refused at the create.
func TestLibraryStateAndAnUnwritableManagedCreate(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newHarness(t)
	libs := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries
	i := slices.IndexFunc(libs, func(l Library) bool { return l.Name == "lib" })
	if i < 0 || libs[i].Configured == nil || !*libs[i].Configured {
		t.Fatalf("libraries = %+v, want lib listed as configured", libs)
	}
	if libs[i].Writable != nil {
		t.Errorf("an in-place library lists writable %v, want it absent", *libs[i].Writable)
	}

	locked := t.TempDir()
	if err := os.Chmod(locked, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Chmod(locked, 0o755) })
	resp := h.postJSON(t, "/api/v1/libraries", map[string]any{"name": "locked", "path": locked, "managed": true})
	if resp.StatusCode != 400 {
		t.Fatalf("an unwritable managed create status = %d, want 400", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "invalid-request" ||
		e.Message != "the library path is not writable by the server, so it cannot be managed; fix its ownership or add it unmanaged" {
		t.Fatalf("an unwritable managed create = %+v, want it refused as unwritable", e)
	}
}

// A library added at runtime is removed through the API: 202 with the
// job, which ends done with what it detached; the listing drops it and
// the audit records it. The configured root and an unknown pid are
// refused, and so is a member.
func TestRemoveLibraryEndToEnd(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	resp := h.postJSON(t, "/api/v1/libraries", map[string]any{"name": "spare", "path": t.TempDir()})
	if resp.StatusCode != 201 {
		t.Fatalf("create status = %d, want 201", resp.StatusCode)
	}
	spare := decode[LibraryCreated](t, resp)
	libs := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries
	i := slices.IndexFunc(libs, func(l Library) bool { return l.Name == "lib" })
	if i < 0 {
		t.Fatalf("libraries = %+v, want lib", libs)
	}

	resp = reqAs(t, h, "DELETE", "/api/v1/libraries/"+libs[i].Pid, h.token, nil)
	if resp.StatusCode != 409 {
		t.Fatalf("removing the configured root status = %d, want 409", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "conflict" {
		t.Fatalf("removing the configured root = %+v, want conflict", e)
	}
	resp = reqAs(t, h, "DELETE", "/api/v1/libraries/lb-01JZX5N8QW3F4V9T2B7KD3M9R6", h.token, nil)
	wantStatus(t, resp, 404, "an unknown library")

	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "listener", "password": "long-enough-pw"})
	wantStatus(t, resp, 201, "create a member")
	member := loginAs(t, h.ts, "listener", "long-enough-pw").Token
	resp = reqAs(t, h, "DELETE", "/api/v1/libraries/"+spare.Pid, member, nil)
	wantStatus(t, resp, 403, "a member removing")

	// The create's scan holds the catalog for a moment: busy until it ends.
	var job Job
	deadline := time.Now().Add(time.Minute)
	for {
		resp = reqAs(t, h, "DELETE", "/api/v1/libraries/"+spare.Pid, h.token, nil)
		if resp.StatusCode == 202 {
			job = decode[Job](t, resp)
			break
		}
		e := decode[Error](t, resp)
		if resp.StatusCode != 409 || e.Code != "catalog-busy" || time.Now().After(deadline) {
			t.Fatalf("remove status = %d (%+v), want 202", resp.StatusCode, e)
		}
		time.Sleep(20 * time.Millisecond)
	}
	if job.Kind != "remove-root" || job.Target == nil || job.Target.Pid != spare.Pid {
		t.Fatalf("job = %+v, want a remove-root job on %s", job, spare.Pid)
	}
	for {
		j := decode[Job](t, get(t, h.ts, "/api/v1/jobs/"+job.Pid, h.token))
		if j.State == "done" {
			if j.Result == nil || (*j.Result)["filesDetached"] == nil || (*j.Result)["itemsArchived"] == nil {
				t.Fatalf("the ended job's result = %v, want its counts", j.Result)
			}
			break
		}
		if j.State != "running" || time.Now().After(deadline) {
			t.Fatalf("the removal ended %s: %v", j.State, deref(j.Error))
		}
		time.Sleep(20 * time.Millisecond)
	}
	h.waitForJobNews(t, job.Pid)
	// Followed in Tasks, it stays listed there once it ends, with what it
	// did.
	listed := decode[JobList](t, get(t, h.ts, "/api/v1/jobs?limit=50", h.token)).Jobs
	if i := slices.IndexFunc(listed, func(j Job) bool { return j.Pid == job.Pid }); i < 0 ||
		listed[i].State != "done" || listed[i].Result == nil || (*listed[i].Result)["filesDetached"] == nil {
		t.Errorf("jobs = %+v, want the ended removal listed with its counts", listed)
	}

	libs = decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries
	if slices.ContainsFunc(libs, func(l Library) bool { return l.Pid == spare.Pid }) {
		t.Errorf("libraries = %+v, want spare gone", libs)
	}
	for {
		page := decode[AuditEventPage](t, get(t, h.ts, "/api/v1/admin/audit?action=library.remove", h.token))
		if slices.ContainsFunc(page.Events, func(e AuditEvent) bool {
			return e.TargetPid != nil && *e.TargetPid == spare.Pid && e.TargetName != nil && *e.TargetName == "spare"
		}) {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("no library.remove audit entry for %s: %+v", spare.Pid, page.Events)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

// A scan names the libraries whose folder it could not reach, and the
// listing flags them once the scan has ended.
func TestAScanNamesTheLibrariesItCouldNotReach(t *testing.T) {
	t.Parallel()
	h := newHarness(t, service.Root{Name: "gone", Path: filepath.Join(t.TempDir(), "gone")})
	pid := h.rescanAndWait(t)
	j := decode[Job](t, get(t, h.ts, "/api/v1/jobs/"+pid, h.token))
	if j.Result == nil {
		t.Fatal("the scan recorded no result")
	}
	if got, _ := (*j.Result)["rootsUnreachable"].([]any); len(got) != 1 || got[0] != "gone" {
		t.Fatalf("rootsUnreachable = %v, want [gone]", (*j.Result)["rootsUnreachable"])
	}
	deadline := time.Now().Add(10 * time.Second)
	for {
		libs := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries
		i := slices.IndexFunc(libs, func(l Library) bool { return l.Name == "gone" })
		if i >= 0 && libs[i].Unreachable != nil && *libs[i].Unreachable {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("libraries = %+v, want gone listed unreachable", libs)
		}
		time.Sleep(20 * time.Millisecond)
	}
}

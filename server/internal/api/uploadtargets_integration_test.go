package api

import (
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// uploadTargets reads the destination picker's list for one token.
func uploadTargets(t *testing.T, h *harness, token string) UploadTargets {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/uploads/targets", token)
	if resp.StatusCode != 200 {
		t.Fatalf("uploads/targets status = %d, want 200", resp.StatusCode)
	}
	return decode[UploadTargets](t, resp)
}

// targetNames flattens the answer to "name(mediaTypes,managed)", which
// is what the filtering assertions read.
func targetNames(page UploadTargets) map[string]UploadTarget {
	out := map[string]UploadTarget{}
	for _, t := range page.Targets {
		out[t.Name] = t
	}
	return out
}

// twoLibraryHarness stands up a second music root beside the demo one,
// which is the shape the picker exists for: more than one candidate for
// the same medium.
func twoLibraryHarness(t *testing.T) *harness {
	t.Helper()
	extra := t.TempDir()
	if _, err := fixtures.Generate(extra, fixtures.Spec{
		Name: "guest", Codec: fixtures.CodecFLAC, Duration: 6 * time.Second,
		Tags: map[string]string{"TITLE": "Guest Song", "ARTIST": "Second Artist"},
	}); err != nil {
		t.Fatal(err)
	}
	return newHarness(t, service.Root{Name: "guests", Path: extra})
}

// TestUploadTargetsListsWhatTheCallerMayName is the picker's read: the
// libraries visible to the caller, with what each accepts.
func TestUploadTargetsListsWhatTheCallerMayName(t *testing.T) {
	t.Parallel()
	h := twoLibraryHarness(t)

	targets := targetNames(uploadTargets(t, h, h.token))
	if len(targets) != 2 {
		t.Fatalf("targets = %+v, want the two roots", targets)
	}
	for name, target := range targets {
		if target.Pid == "" || len(target.MediaTypes) == 0 {
			t.Errorf("%s = %+v, want a pid and what it accepts", name, target)
		}
	}
}

// TestUploadTargetsNeedsUploadRights pins the gate: it is upload rights
// rather than admin, which is the whole reason this is its own narrow
// operation and not a relaxed listLibraries.
func TestUploadTargetsNeedsUploadRights(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "listener", "password": testPassword,
	})
	wantStatus(t, resp, 201, "create a listener")
	listener := loginAs(t, h.ts, "listener", testPassword).Token
	resp = get(t, h.ts, "/api/v1/uploads/targets", listener)
	wantStatus(t, resp, 403, "a listener has no upload rights")

	resp = h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "uploader", "password": testPassword, "uploadEnabled": true,
	})
	wantStatus(t, resp, 201, "create an uploader")
	uploader := loginAs(t, h.ts, "uploader", testPassword).Token
	if len(uploadTargets(t, h, uploader).Targets) == 0 {
		t.Error("a non-admin uploader was offered no targets")
	}
}

// TestUploadTargetsOmitsAReadOnlyLibrary keeps the picker and the create
// call in step: offering a destination whose upload the server would
// refuse is worse than offering none.
func TestUploadTargetsOmitsAReadOnlyLibrary(t *testing.T) {
	t.Parallel()
	h := twoLibraryHarness(t)

	before := targetNames(uploadTargets(t, h, h.token))
	guests, ok := before["guests"]
	if !ok {
		t.Fatalf("no guests root among %+v", before)
	}
	resp := h.putJSON(t, "/api/v1/libraries/"+guests.Pid+"/read-only",
		map[string]any{"readOnly": true})
	wantStatus(t, resp, 200, "mark the guests root read-only")

	after := targetNames(uploadTargets(t, h, h.token))
	if _, still := after["guests"]; still {
		t.Errorf("a read-only library is still offered: %+v", after)
	}
	if _, kept := after["lib"]; !kept {
		t.Errorf("the writable library went with it: %+v", after)
	}

	// And the create call refuses it, which is what the picker is being
	// kept in step with.
	resp = h.postJSON(t, "/api/v1/uploads", map[string]any{
		"fileName": "x.flac", "sizeBytes": 1024, "mediaType": "music",
		"libraryPid": guests.Pid,
	})
	wantStatus(t, resp, 409, "upload into a read-only library")
}

// TestAcquisitionRefusesAReadOnlyLibrary is the ride-along fix: the
// acquisition's own validation stopped at visibility and let a caller
// name a library the settle would then refuse, which a destination
// picker makes ordinary rather than exotic. Its check is now the upload
// surfaces' own, so the two cannot drift apart again.
func TestAcquisitionRefusesAReadOnlyLibrary(t *testing.T) {
	t.Parallel()
	extra := t.TempDir()
	if _, err := fixtures.Generate(extra, fixtures.Spec{
		Name: "guest", Codec: fixtures.CodecFLAC, Duration: 6 * time.Second,
		Tags: map[string]string{"TITLE": "Guest Song", "ARTIST": "Second Artist"},
	}); err != nil {
		t.Fatal(err)
	}
	// An acquisition source has to be running or the request is refused
	// for want of one before it ever reaches the library check.
	src := &fakeAcquireSource{playlistURL: "https://tube.example/watch?v=one"}
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.SourceProviders = append(cfg.SourceProviders, src)
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
		cfg.AllowPrivateFeedHosts = true
	}, service.Root{Name: "guests", Path: extra})

	guests, ok := targetNames(uploadTargets(t, h, h.token))["guests"]
	if !ok {
		t.Fatal("no guests root")
	}
	body := map[string]any{
		"url": "https://tube.example/watch?v=one", "mediaType": "music",
		"libraryPid": guests.Pid,
	}
	// Writable first, so the refusal below is the read-only flag and not
	// something else about this request.
	resp := h.postJSON(t, "/api/v1/acquisitions", body)
	wantStatus(t, resp, 202, "acquire into a writable library")

	resp = h.putJSON(t, "/api/v1/libraries/"+guests.Pid+"/read-only",
		map[string]any{"readOnly": true})
	wantStatus(t, resp, 200, "mark the guests root read-only")

	resp = h.postJSON(t, "/api/v1/acquisitions", body)
	wantStatus(t, resp, 409, "acquire into a read-only library")
}

package api

import (
	"fmt"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// A decision that meets a scan holding the file-mutation scope answers
// catalog-busy, which clears on its own, never a plain conflict naming
// the job runner; once the scan ends the same decision lands.
func TestDecideDuringARescanIsCatalogBusy(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})
	// Enough files that a forced rescan, which rereads every one, is
	// still running when the decision arrives.
	specs := make([]fixtures.Spec, 300)
	for i := range specs {
		specs[i] = fixtures.Spec{
			Name: fmt.Sprintf("filler-%03d", i), Codec: fixtures.CodecFLAC, Duration: time.Second,
			Tags: map[string]string{"TITLE": fmt.Sprintf("Filler %d", i), "ARTIST": "Padding", "ALBUM": "Slow Scan"},
		}
	}
	if _, err := fixtures.Generate(filepath.Join(h.library, "filler"), specs...); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "late-arrival", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Late Arrival", "ARTIST": "Beacon Row", "ALBUM": "Late Arrival"},
	})
	if err != nil {
		t.Fatal(err)
	}
	entry := *uploadFile(t, h, h.token, paths[0], "music", "").ReviewEntryId
	drainMatches(t, h)

	job := decodeStatus[Job](t, h.postJSON(t, "/api/v1/library/rescan", map[string]any{"force": true}), 202, "forced rescan")
	for deadline := time.Now().Add(10 * time.Second); ; time.Sleep(5 * time.Millisecond) {
		if j := decode[Job](t, get(t, h.ts, "/api/v1/jobs/"+job.Pid, h.token)); j.State == "running" {
			break
		} else if j.State != "queued" {
			t.Fatalf("the rescan ended %s before the decision could meet it", j.State)
		}
		if time.Now().After(deadline) {
			t.Fatal("the rescan never started")
		}
	}
	resp := h.postJSON(t, "/api/v1/review/queue/"+entry+"/decide", map[string]any{"action": "as-is"})
	if resp.StatusCode != 409 {
		resp.Body.Close()
		t.Fatalf("decide during the rescan = %d, want 409", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "catalog-busy" || strings.Contains(e.Message, "jobs.") {
		t.Fatalf("refusal = %+v, want catalog-busy in plain words", e)
	}
	// A kind change meeting the same scan is told it is busy too, from
	// the catalog's own lease refusal rather than a copy of its words.
	resp = h.postJSON(t, "/api/v1/items/kind", map[string]any{
		"pids": []string{h.itemTitled(t, h.token, "Filler 0").Pid}, "mediaType": "audiobook",
	})
	if resp.StatusCode != 409 {
		resp.Body.Close()
		t.Fatalf("kind change during the rescan = %d, want 409", resp.StatusCode)
	}
	if e := decode[Error](t, resp); e.Code != "catalog-busy" {
		t.Fatalf("kind change refusal = %+v, want catalog-busy", e)
	}

	for deadline := time.Now().Add(2 * time.Minute); ; time.Sleep(50 * time.Millisecond) {
		if j := decode[Job](t, get(t, h.ts, "/api/v1/jobs/"+job.Pid, h.token)); j.State == "done" {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the rescan did not finish")
		}
	}
	decodeStatus[ReviewDecideResult](t, h.postJSON(t, "/api/v1/review/queue/"+entry+"/decide",
		map[string]any{"action": "as-is"}), 200, "decide after the rescan")
}

// A bulk decision reports each entry the way the single decide would:
// a refusal by its code, a decision that stood with its warnings.
func TestBulkDecideCarriesCodesAndWarnings(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	// The library's alpha under other tags: deciding it joins, warning.
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "alpha", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Bulk Twin", "ARTIST": "Bob", "ALBUM": "Bulk Demo"},
	})
	if err != nil {
		t.Fatal(err)
	}
	entry := *uploadFile(t, h, bob, paths[0], "music", "").ReviewEntryId
	drainMatches(t, h)

	res := decodeStatus[ReviewBulkResult](t, postJSONAs(t, h, bob, "/api/v1/review/decide",
		map[string]any{"entryIds": []string{entry, "rv-missing"}, "action": "as-is"}), 200, "bulk decide")
	if len(res.Results) != 2 {
		t.Fatalf("results = %+v, want two", res.Results)
	}
	joined, missing := res.Results[0], res.Results[1]
	if !joined.Ok || joined.Warnings == nil || !strings.Contains(strings.Join(*joined.Warnings, "\n"), "already in the library") {
		t.Fatalf("joined outcome = %+v, want it decided with its warning", joined)
	}
	if missing.Ok || missing.Code == nil || *missing.Code != "not-found" {
		t.Fatalf("missing outcome = %+v, want not-found", missing)
	}
}

// A submission that declines identification and meets another job
// holding the catalog is imported once that job ends, as it would have
// been on arrival, rather than left for a person to decide.
func TestADeclinedUploadThatMeetsABusyCatalogImportsWhenItFrees(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})
	specs := make([]fixtures.Spec, 300)
	for i := range specs {
		specs[i] = fixtures.Spec{
			Name: fmt.Sprintf("filler-%03d", i), Codec: fixtures.CodecFLAC, Duration: time.Second,
			Tags: map[string]string{"TITLE": fmt.Sprintf("Filler %d", i), "ARTIST": "Padding", "ALBUM": "Slow Scan"},
		}
	}
	if _, err := fixtures.Generate(filepath.Join(h.library, "filler"), specs...); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "while-busy", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "While Busy", "ARTIST": "Beacon Row", "ALBUM": "While Busy"},
	})
	if err != nil {
		t.Fatal(err)
	}
	job := decodeStatus[Job](t, h.postJSON(t, "/api/v1/library/rescan", map[string]any{"force": true}), 202, "forced rescan")
	for deadline := time.Now().Add(10 * time.Second); ; time.Sleep(5 * time.Millisecond) {
		if j := decode[Job](t, get(t, h.ts, "/api/v1/jobs/"+job.Pid, h.token)); j.State == "running" {
			break
		} else if j.State != "queued" {
			t.Fatalf("the rescan ended %s before the upload could meet it", j.State)
		}
		if time.Now().After(deadline) {
			t.Fatal("the rescan never started")
		}
	}
	up := createBatchMemberWith(t, h, h.token, paths[0], "music", "", "", map[string]any{"identify": false})
	sendUploadBytes(t, h, h.token, up.Id, paths[0])
	done := completeUploadSession(t, h, h.token, up.Id)
	if done.ReviewEntryId == nil {
		t.Fatal("the completed upload opened no entry")
	}
	for deadline := time.Now().Add(2 * time.Minute); ; time.Sleep(50 * time.Millisecond) {
		if e := getReview(t, h, *done.ReviewEntryId); e.Status == "as-is" {
			return
		} else if time.Now().After(deadline) {
			t.Fatalf("entry = %s after the rescan, want it imported as-is", e.Status)
		}
	}
}

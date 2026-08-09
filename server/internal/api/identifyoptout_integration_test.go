package api

import (
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/match"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// The identification opt-out: the resolution order (submission over
// preference over on), the mark a declined entry carries, and that
// declining files the entry rather than leaving it waiting.

// obviousRelease answers every search, so a declined entry's empty
// candidate list is a statement about the queue, not the search.
func obviousRelease() []*match.Release {
	return []*match.Release{{
		MBID: "rel-obvious", ReleaseGroupMBID: "rg-obvious",
		Title: "Quiet Wire", Artist: "Hold Steady State", Year: 2021, Media: 1,
		Tracks: []match.ReleaseTrack{{
			RecordingMBID: "00000000-0000-4000-8000-0000000000a1",
			Title:         "Quiet Wire", Position: 1, DurationSec: 3,
		}},
	}}
}

// quietTrack synthesizes one file to upload, titled after its name so
// two of them land in different places. Two calls sharing a name is how
// a test asks for a destination collision on purpose.
func quietTrack(t *testing.T, name string) string {
	t.Helper()
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: name, Codec: fixtures.CodecMP3, Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": name, "ARTIST": "Hold Steady State"},
	})
	if err != nil {
		t.Fatal(err)
	}
	return paths[0]
}

// uploadDeclaring runs a whole single-file upload whose create body
// carries the given extra fields (`identify`, here).
func uploadDeclaring(t *testing.T, h *harness, token, path string, extra map[string]any) Upload {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	body := map[string]any{
		"fileName":  filepath.Base(path),
		"sizeBytes": len(raw),
		"mediaType": "music",
	}
	for k, v := range extra {
		body[k] = v
	}
	resp := postJSONAs(t, h, token, "/api/v1/uploads", body)
	if resp.StatusCode != 201 {
		t.Fatalf("create upload status = %d", resp.StatusCode)
	}
	up := decode[Upload](t, resp)
	sendUploadBytes(t, h, token, up.Id, path)
	return completeUploadSession(t, h, token, up.Id)
}

// entryOf reads the review entry an upload session opened.
func entryOf(t *testing.T, h *harness, token string, up Upload) ReviewEntryDetail {
	t.Helper()
	if up.ReviewEntryId == nil {
		t.Fatalf("upload %s opened no review entry", up.Id)
	}
	resp := get(t, h.ts, "/api/v1/review/queue/"+*up.ReviewEntryId, token)
	if resp.StatusCode != 200 {
		t.Fatalf("review entry status = %d", resp.StatusCode)
	}
	return decode[ReviewEntryDetail](t, resp)
}

func TestUploadDecliningIdentificationImportsWithNoStop(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{releases: obviousRelease()}
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})

	up := uploadDeclaring(t, h, h.token, quietTrack(t, "declined"), map[string]any{"identify": false})
	drainMatches(t, h)

	// Somebody who turns identification off has already said what to do
	// with the files, so nothing waits to be told again.
	entry := entryOf(t, h, h.token, up)
	if entry.Status != "as-is" {
		t.Fatalf("declined entry status = %q, want as-is", entry.Status)
	}
	if entry.Identifying {
		t.Fatal("declined entry is still identifying")
	}
	if len(entry.Candidates) != 0 {
		t.Fatalf("declined entry has %d candidates; nothing was searched", len(entry.Candidates))
	}
	if entry.IdentifyDeclined == nil || !*entry.IdentifyDeclined {
		t.Fatalf("declined entry identifyDeclined = %v, want true", entry.IdentifyDeclined)
	}
	// A decided entry, not no entry: the import has the same record and
	// the same undo as one somebody pressed the button for.
	if entry.DecidedAt == nil {
		t.Fatal("the entry was filed without a decision time")
	}

	// The session settles too, so its bytes stop being charged against
	// the pending-upload quota.
	final := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+up.Id, h.token))
	if final.State != "imported" {
		t.Fatalf("upload state = %q, want imported", final.State)
	}

	h.rescanAndWait(t)
	found := false
	for _, it := range h.items(t, "?limit=200").Items {
		if it.Title == "declined" {
			found = true
		}
	}
	if !found {
		t.Fatal("the declined upload did not reach the library")
	}
}

// The stop is not gone, it is conditional: an import that cannot
// proceed leaves the entry pending for a person, which is what keeps
// this from being a way into the library that skips one.
func TestDeclinedImportThatCannotProceedWaitsForAPerson(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{releases: obviousRelease()}
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})

	// The same track twice. The first lands; the second's destination is
	// then taken, which is the shape of every reason an import refuses -
	// and precisely when somebody should be looking at it.
	first := uploadDeclaring(t, h, h.token, quietTrack(t, "twice"), map[string]any{"identify": false})
	if e := entryOf(t, h, h.token, first); e.Status != "as-is" {
		t.Fatalf("the first copy did not import: %q", e.Status)
	}

	second := uploadDeclaring(t, h, h.token, quietTrack(t, "twice"), map[string]any{"identify": false})
	entry := entryOf(t, h, h.token, second)
	if entry.Status != "pending" {
		t.Fatalf("entry status = %q, want pending - a refused import must not decide itself", entry.Status)
	}
	if entry.IdentifyDeclined == nil || !*entry.IdentifyDeclined {
		t.Fatal("the entry lost the mark that explains its empty candidate list")
	}
	// And its bytes are still staged, so nothing was lost on the way.
	final := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+second.Id, h.token))
	if final.State != "staged" {
		t.Fatalf("upload state = %q, want staged", final.State)
	}
}

func TestIdentifiedEntryDoesNotClaimDeclined(t *testing.T) {
	t.Parallel()
	// The searched-and-found-nothing case: an entry that ran through
	// the engine and came back empty must not read as declined.
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{}
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})

	up := uploadDeclaring(t, h, h.token, quietTrack(t, "searched"), nil)
	drainMatches(t, h)

	entry := entryOf(t, h, h.token, up)
	if entry.Identifying {
		t.Fatal("entry is still identifying after the worker drained")
	}
	if len(entry.Candidates) != 0 {
		t.Fatalf("the canned source answers nothing; got %d candidates", len(entry.Candidates))
	}
	if entry.IdentifyDeclined != nil {
		t.Fatalf("searched-empty entry identifyDeclined = %v, want absent", *entry.IdentifyDeclined)
	}
}

func TestIdentifyDefaultsToTheAccountPreference(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{releases: obviousRelease()}
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})

	// With nothing said either way, the submission is identified.
	on := uploadDeclaring(t, h, h.token, quietTrack(t, "default-on"), nil)
	drainMatches(t, h)
	if e := entryOf(t, h, h.token, on); len(e.Candidates) == 0 || e.IdentifyDeclined != nil {
		t.Fatalf("default entry candidates = %d, declined = %v; want identified", len(e.Candidates), e.IdentifyDeclined)
	}

	resp := h.putJSON(t, "/api/v1/users/me/prefs", map[string]any{"identifyOptOut": true})
	if resp.StatusCode != 200 {
		t.Fatalf("prefs status = %d", resp.StatusCode)
	}
	var prefs Prefs
	if err := json.NewDecoder(resp.Body).Decode(&prefs); err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if prefs.IdentifyOptOut == nil || !*prefs.IdentifyOptOut {
		t.Fatalf("stored identifyOptOut = %v, want true", prefs.IdentifyOptOut)
	}

	// Silent submissions now follow the preference.
	off := uploadDeclaring(t, h, h.token, quietTrack(t, "default-off"), nil)
	drainMatches(t, h)
	e := entryOf(t, h, h.token, off)
	if e.IdentifyDeclined == nil || !*e.IdentifyDeclined {
		t.Fatalf("entry under the opt-out identifyDeclined = %v, want true", e.IdentifyDeclined)
	}
	if e.Status != "as-is" {
		t.Fatalf("entry under the opt-out status = %q, want as-is", e.Status)
	}

	// And a submission that says so overrides it.
	forced := uploadDeclaring(t, h, h.token, quietTrack(t, "forced-on"), map[string]any{"identify": true})
	drainMatches(t, h)
	if e := entryOf(t, h, h.token, forced); len(e.Candidates) == 0 || e.IdentifyDeclined != nil {
		t.Fatalf("explicit identify:true candidates = %d, declined = %v; want identified", len(e.Candidates), e.IdentifyDeclined)
	}
}

func TestBatchDecidesIdentificationForItsMembers(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{releases: obviousRelease()}
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})

	media := t.TempDir()
	paths, err := fixtures.Generate(media,
		batchTrackSpec("one", "Quiet Wire", "Signal Test", "Hold Steady State", "1", 3),
		batchTrackSpec("two", "Loud Wire", "Signal Test", "Hold Steady State", "2", 4),
	)
	if err != nil {
		t.Fatal(err)
	}

	resp := postJSONAs(t, h, h.token, "/api/v1/uploads/batches",
		map[string]any{"grouping": "album", "mediaType": "music", "identify": false})
	if resp.StatusCode != 201 {
		t.Fatalf("create batch status = %d", resp.StatusCode)
	}
	batch := decode[UploadBatch](t, resp)

	// A member asking for identification is ignored: the batch decided.
	first := createBatchMemberWith(t, h, h.token, paths[0], "music", batch.Id, "",
		map[string]any{"identify": true})
	sendUploadBytes(t, h, h.token, first.Id, paths[0])
	completeUploadSession(t, h, h.token, first.Id)
	uploadBatchMember(t, h, h.token, paths[1], "music", batch.Id, "")

	final := finalizeBatch(t, h, h.token, batch.Id)
	drainMatches(t, h)
	if len(final.ReviewEntryIds) == 0 {
		t.Fatal("finalize opened no entries")
	}
	for _, id := range final.ReviewEntryIds {
		entry := getReview(t, h, id)
		if entry.IdentifyDeclined == nil || !*entry.IdentifyDeclined {
			t.Fatalf("batch entry %s identifyDeclined = %v, want true", id, entry.IdentifyDeclined)
		}
		if len(entry.Candidates) != 0 {
			t.Fatalf("batch entry %s has %d candidates", id, len(entry.Candidates))
		}
		if entry.Status != "as-is" {
			t.Fatalf("batch entry %s status = %q, want as-is", id, entry.Status)
		}
	}
}

func TestAcquisitionCarriesTheIdentifyChoice(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeAcquireSource{
		playlistURL: "https://tube.example/playlist?list=PLquiet",
		files:       map[string]string{},
	}
	paths, err := fixtures.Generate(media,
		fixtures.Spec{Name: "acq-one", Codec: fixtures.CodecMP3, Duration: 3 * time.Second,
			Tags: map[string]string{"TITLE": "Quiet Wire", "ARTIST": "Hold Steady State"}},
	)
	if err != nil {
		t.Fatal(err)
	}
	src.entries = []struct{ title, url string }{{"Quiet Wire", "https://tube.example/watch?v=quiet"}}
	src.files["https://tube.example/watch?v=quiet"] = paths[0]

	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{releases: obviousRelease()}
		cfg.SourceProviders = append(cfg.SourceProviders, src)
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
		cfg.AllowPrivateFeedHosts = true
	})

	resp := postJSONAs(t, h, h.token, "/api/v1/acquisitions", map[string]any{
		"url": src.playlistURL, "mediaType": "music", "identify": false,
	})
	if resp.StatusCode != 202 {
		t.Fatalf("acquisition status = %d", resp.StatusCode)
	}
	task := decode[ToolTask](t, resp)
	drainTools(t, h)
	drainMatches(t, h)

	got := decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+task.Id, h.token))
	if got.State != "done" || got.ResultPids == nil || len(*got.ResultPids) != 1 {
		t.Fatalf("acquire task = %+v", got)
	}
	entry := getReview(t, h, (*got.ResultPids)[0])
	if entry.IdentifyDeclined == nil || !*entry.IdentifyDeclined {
		t.Fatalf("acquired entry identifyDeclined = %v, want true", entry.IdentifyDeclined)
	}
	if len(entry.Candidates) != 0 {
		t.Fatalf("acquired entry has %d candidates", len(entry.Candidates))
	}
	if entry.Status != "as-is" {
		t.Fatalf("acquired entry status = %q, want as-is", entry.Status)
	}
}

// A declined submission must not merely be un-enqueued; nothing may be
// left waiting in the match queue for a later sweep to pick up.
func TestDecliningLeavesNothingInTheMatchQueue(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{releases: obviousRelease()}
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})
	uploadDeclaring(t, h, h.token, quietTrack(t, "queue-empty"), map[string]any{"identify": false})
	if h.svc.DrainMatchQueue(t.Context()) {
		t.Fatal("the match queue had work after a declined submission")
	}
}

package api

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"
)

// postJSONAs is postJSON with a caller-chosen bearer token.
func postJSONAs(t *testing.T, h *harness, token, path string, body any) *http.Response {
	t.Helper()
	var buf []byte
	if body != nil {
		var err error
		if buf, err = json.Marshal(body); err != nil {
			t.Fatal(err)
		}
	}
	req, err := http.NewRequest("POST", h.ts.URL+path, bytes.NewReader(buf))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	return resp
}

// createBatch opens a batch and fails the test on anything but 201.
func createBatch(t *testing.T, h *harness, token, grouping, mediaType string) UploadBatch {
	t.Helper()
	resp := postJSONAs(t, h, token, "/api/v1/uploads/batches",
		map[string]any{"grouping": grouping, "mediaType": mediaType})
	if resp.StatusCode != 201 {
		t.Fatalf("create batch status = %d", resp.StatusCode)
	}
	return decode[UploadBatch](t, resp)
}

// finalizeBatch completes a batch and fails the test on anything but
// 200.
func finalizeBatch(t *testing.T, h *harness, token, id string) UploadBatch {
	t.Helper()
	resp := postJSONAs(t, h, token, "/api/v1/uploads/batches/"+id+"/complete", nil)
	if resp.StatusCode != 200 {
		t.Fatalf("finalize batch status = %d", resp.StatusCode)
	}
	return decode[UploadBatch](t, resp)
}

// uploadBatchMember runs the whole member flow: create in the batch,
// send bytes, complete. batchPath rides the create.
func uploadBatchMember(t *testing.T, h *harness, token, path, mediaType, batchID, batchPath string) Upload {
	t.Helper()
	up := createBatchMember(t, h, token, path, mediaType, batchID, batchPath)
	sendUploadBytes(t, h, token, up.Id, path)
	return completeUploadSession(t, h, token, up.Id)
}

// createBatchMember opens a member session without sending bytes.
func createBatchMember(t *testing.T, h *harness, token, path, mediaType, batchID, batchPath string) Upload {
	t.Helper()
	return createBatchMemberWith(t, h, token, path, mediaType, batchID, batchPath, nil)
}

// createBatchMemberWith opens a member session carrying extra create
// fields, for the cases where what a member declares is the subject.
func createBatchMemberWith(t *testing.T, h *harness, token, path, mediaType, batchID, batchPath string, extra map[string]any) Upload {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	body := map[string]any{
		"fileName":  filepath.Base(path),
		"sizeBytes": len(raw),
		"mediaType": mediaType,
		"batchId":   batchID,
	}
	if batchPath != "" {
		body["batchPath"] = batchPath
	}
	for k, v := range extra {
		body[k] = v
	}
	resp := postJSONAs(t, h, token, "/api/v1/uploads", body)
	if resp.StatusCode != 201 {
		t.Fatalf("create member status = %d", resp.StatusCode)
	}
	return decode[Upload](t, resp)
}

// sendUploadBytes puts the whole file as one chunk.
func sendUploadBytes(t *testing.T, h *harness, token, uploadID, path string) {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	req, _ := http.NewRequest("PUT", h.ts.URL+"/api/v1/uploads/"+uploadID+"/data?offset=0",
		bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/octet-stream")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("send bytes status = %d", resp.StatusCode)
	}
}

// completeUploadSession seals one session.
func completeUploadSession(t *testing.T, h *harness, token, uploadID string) Upload {
	t.Helper()
	resp := postJSONAs(t, h, token, "/api/v1/uploads/"+uploadID+"/complete", nil)
	if resp.StatusCode != 200 {
		t.Fatalf("complete session status = %d", resp.StatusCode)
	}
	return decode[Upload](t, resp)
}

// batchTrackSpec synthesizes one taggable member file.
func batchTrackSpec(name, title, album, artist string, trackNo string, sec int) fixtures.Spec {
	tags := map[string]string{"TITLE": title}
	if album != "" {
		tags["ALBUM"] = album
	}
	if artist != "" {
		tags["ARTIST"] = artist
	}
	if trackNo != "" {
		tags["TRACKNUMBER"] = trackNo
	}
	return fixtures.Spec{
		Name: name, Codec: fixtures.CodecMP3,
		Duration: time.Duration(sec) * time.Second, Tags: tags,
	}
}

// TestUploadBatchValidation covers create and join refusals: rights,
// ownership, closed batches, media-type and library mismatches, and
// batchPath sanitizing.
func TestUploadBatchValidation(t *testing.T) {
	h := newHarness(t)
	staging := t.TempDir()
	paths, err := fixtures.Generate(staging,
		batchTrackSpec("val-one", "Val One", "Val", "Nobody", "1", 3))
	if err != nil {
		t.Fatal(err)
	}

	// A second account without upload rights cannot open a batch.
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "plain", "password": "long-enough-pw",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	plainToken := loginAs(t, h.ts, "plain", "long-enough-pw").Token
	if r := postJSONAs(t, h, plainToken, "/api/v1/uploads/batches",
		map[string]any{"grouping": "album", "mediaType": "music"}); r.StatusCode != 403 {
		t.Fatalf("batch without rights status = %d, want 403", r.StatusCode)
	}

	// Unknown grouping is refused.
	if r := h.postJSON(t, "/api/v1/uploads/batches",
		map[string]any{"grouping": "mixtape", "mediaType": "music"}); r.StatusCode != 400 {
		t.Fatalf("unknown grouping status = %d, want 400", r.StatusCode)
	}

	b := createBatch(t, h, h.token, "album", "music")
	if b.State != "open" || len(b.ReviewEntryIds) != 0 {
		t.Fatalf("fresh batch = %+v", b)
	}

	memberBody := func(mutate func(map[string]any)) map[string]any {
		body := map[string]any{
			"fileName": "val-one.mp3", "sizeBytes": 100,
			"mediaType": "music", "batchId": b.Id,
		}
		if mutate != nil {
			mutate(body)
		}
		return body
	}
	refuse := func(name string, body map[string]any) {
		t.Helper()
		r := h.postJSON(t, "/api/v1/uploads", body)
		if r.StatusCode != 400 {
			t.Fatalf("%s status = %d, want 400", name, r.StatusCode)
		}
	}
	refuse("batchPath without batchId", map[string]any{
		"fileName": "val-one.mp3", "sizeBytes": 100,
		"mediaType": "music", "batchPath": "somewhere",
	})
	refuse("media-type mismatch", memberBody(func(m map[string]any) { m["mediaType"] = "audiobook"; m["fileName"] = "val-one.m4b" }))
	refuse("library mismatch", memberBody(func(m map[string]any) { m["libraryPid"] = "lb-01JZX5N8QW3F4V9T2B7KD3M9R6" }))
	refuse("parent traversal", memberBody(func(m map[string]any) { m["batchPath"] = "a/../../b" }))
	refuse("absolute path", memberBody(func(m map[string]any) { m["batchPath"] = "/rooted" }))
	refuse("backslashes", memberBody(func(m map[string]any) { m["batchPath"] = `a\b` }))

	// Another user's batch reads as absent even with upload rights.
	grantBody, _ := json.Marshal(map[string]any{"uploadEnabled": true})
	page := decode[UserPage](t, get(t, h.ts, "/api/v1/users?limit=100", h.token))
	for _, u := range page.Users {
		if u.Username != "plain" {
			continue
		}
		req, _ := http.NewRequest("PATCH", h.ts.URL+"/api/v1/users/"+u.Id, bytes.NewReader(grantBody))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+h.token)
		r, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		if r.StatusCode != 200 {
			t.Fatalf("grant status = %d", r.StatusCode)
		}
	}
	if r := postJSONAs(t, h, plainToken, "/api/v1/uploads", memberBody(nil)); r.StatusCode != 400 {
		t.Fatalf("foreign batch join status = %d, want 400", r.StatusCode)
	}
	if r := postJSONAs(t, h, plainToken, "/api/v1/uploads/batches/"+b.Id+"/complete", nil); r.StatusCode != 404 {
		t.Fatalf("foreign finalize status = %d, want 404", r.StatusCode)
	}
	if r := h.postJSON(t, "/api/v1/uploads/batches/ub-01JZX5N8QW3F4V9T2B7KD3M9R6/complete", nil); r.StatusCode != 404 {
		t.Fatalf("unknown finalize status = %d, want 404", r.StatusCode)
	}

	// A finalized batch refuses new members.
	uploadBatchMember(t, h, h.token, paths[0], "music", b.Id, "")
	finalizeBatch(t, h, h.token, b.Id)
	if r := h.postJSON(t, "/api/v1/uploads", memberBody(nil)); r.StatusCode != 400 {
		t.Fatalf("closed batch join status = %d, want 400", r.StatusCode)
	}
}

// TestUploadBatchGroupings drives all three grouping intents through
// upload, finalize, and the review entries they open.
func TestUploadBatchGroupings(t *testing.T) {
	h := newHarness(t)
	staging := t.TempDir()

	// Album: three files completed out of order land in one entry,
	// track-ordered.
	paths, err := fixtures.Generate(staging,
		batchTrackSpec("alb-1", "Opening", "Long Form", "Ensemble", "1", 3),
		batchTrackSpec("alb-2", "Middle", "Long Form", "Ensemble", "2", 3),
		batchTrackSpec("alb-3", "Closing", "Long Form", "Ensemble", "3", 3),
	)
	if err != nil {
		t.Fatal(err)
	}
	album := createBatch(t, h, h.token, "album", "music")
	for _, i := range []int{2, 0, 1} { // shuffled completion order
		up := uploadBatchMember(t, h, h.token, paths[i], "music", album.Id, "")
		if up.State != "staged" {
			t.Fatalf("member state = %q", up.State)
		}
		if up.ReviewEntryId != nil {
			t.Fatalf("member got its own entry before finalize: %+v", up)
		}
		if up.BatchId == nil || *up.BatchId != album.Id {
			t.Fatalf("member batchId = %v", up.BatchId)
		}
	}
	done := finalizeBatch(t, h, h.token, album.Id)
	if done.State != "finalized" || len(done.ReviewEntryIds) != 1 {
		t.Fatalf("album batch after finalize = %+v", done)
	}
	entry := getReview(t, h, done.ReviewEntryIds[0])
	if entry.TrackCount != 3 || len(entry.Tracks) != 3 {
		t.Fatalf("album entry tracks = %d/%d, want 3", entry.TrackCount, len(entry.Tracks))
	}
	for i, want := range []string{"Opening", "Middle", "Closing"} {
		if entry.Tracks[i].Title != want {
			t.Fatalf("album track %d = %q, want %q", i, entry.Tracks[i].Title, want)
		}
	}

	// Tracks: three files, three entries.
	paths, err = fixtures.Generate(staging,
		batchTrackSpec("trk-1", "Solo A", "Scattered", "Various", "1", 3),
		batchTrackSpec("trk-2", "Solo B", "Scattered", "Various", "2", 3),
		batchTrackSpec("trk-3", "Solo C", "Scattered", "Various", "3", 3),
	)
	if err != nil {
		t.Fatal(err)
	}
	tracks := createBatch(t, h, h.token, "tracks", "music")
	for _, p := range paths {
		uploadBatchMember(t, h, h.token, p, "music", tracks.Id, "")
	}
	done = finalizeBatch(t, h, h.token, tracks.Id)
	if len(done.ReviewEntryIds) != 3 {
		t.Fatalf("tracks batch entries = %d, want 3", len(done.ReviewEntryIds))
	}
	for _, id := range done.ReviewEntryIds {
		if e := getReview(t, h, id); e.TrackCount != 1 {
			t.Fatalf("tracks entry %s trackCount = %d, want 1", id, e.TrackCount)
		}
	}

	// Auto with tags: two albums cluster into two units.
	paths, err = fixtures.Generate(staging,
		batchTrackSpec("aut-1", "First Half", "Alpha Set", "Group A", "1", 3),
		batchTrackSpec("aut-2", "Second Half", "Alpha Set", "Group A", "2", 3),
		batchTrackSpec("aut-3", "Lone Cut", "Beta Set", "Group B", "1", 3),
	)
	if err != nil {
		t.Fatal(err)
	}
	auto := createBatch(t, h, h.token, "auto", "music")
	for _, p := range paths {
		uploadBatchMember(t, h, h.token, p, "music", auto.Id, "")
	}
	done = finalizeBatch(t, h, h.token, auto.Id)
	if len(done.ReviewEntryIds) != 2 {
		t.Fatalf("auto batch entries = %d, want 2", len(done.ReviewEntryIds))
	}
	counts := map[int]int{}
	for _, id := range done.ReviewEntryIds {
		counts[getReview(t, h, id).TrackCount]++
	}
	if counts[2] != 1 || counts[1] != 1 {
		t.Fatalf("auto unit sizes = %v, want one 2-track and one 1-track", counts)
	}

	// Auto without album tags: the batchPath hint folds disc
	// subfolders into one unit.
	paths, err = fixtures.Generate(staging,
		batchTrackSpec("cd1-track", "Disc One Cut", "", "", "", 3),
		batchTrackSpec("cd2-track", "Disc Two Cut", "", "", "", 3),
	)
	if err != nil {
		t.Fatal(err)
	}
	folded := createBatch(t, h, h.token, "auto", "music")
	uploadBatchMember(t, h, h.token, paths[0], "music", folded.Id, "Boxset/CD1")
	uploadBatchMember(t, h, h.token, paths[1], "music", folded.Id, "Boxset/CD2")
	done = finalizeBatch(t, h, h.token, folded.Id)
	if len(done.ReviewEntryIds) != 1 {
		t.Fatalf("disc-fold entries = %d, want 1 (batchPath hint not applied)", len(done.ReviewEntryIds))
	}
	if e := getReview(t, h, done.ReviewEntryIds[0]); e.TrackCount != 2 {
		t.Fatalf("disc-fold entry trackCount = %d, want 2", e.TrackCount)
	}
}

// TestUploadBatchStragglerAndIdempotency proves the finalize race's
// second ordering deterministically: a member completing after the
// flip opens its own per-file entry, exactly one entry either way. A
// repeated finalize answers the same batch.
func TestUploadBatchStragglerAndIdempotency(t *testing.T) {
	h := newHarness(t)
	staging := t.TempDir()
	paths, err := fixtures.Generate(staging,
		batchTrackSpec("str-1", "On Time", "Straggle", "Ensemble", "1", 3),
		batchTrackSpec("str-2", "Late", "Straggle", "Ensemble", "2", 3),
	)
	if err != nil {
		t.Fatal(err)
	}
	b := createBatch(t, h, h.token, "album", "music")
	uploadBatchMember(t, h, h.token, paths[0], "music", b.Id, "")

	// The second member has all its bytes but has not completed when
	// the batch finalizes.
	late := createBatchMember(t, h, h.token, paths[1], "music", b.Id, "")
	sendUploadBytes(t, h, h.token, late.Id, paths[1])

	done := finalizeBatch(t, h, h.token, b.Id)
	if len(done.ReviewEntryIds) != 1 {
		t.Fatalf("batch entries = %d, want 1 (the staged member)", len(done.ReviewEntryIds))
	}
	batchEntry := done.ReviewEntryIds[0]
	if e := getReview(t, h, batchEntry); e.TrackCount != 1 {
		t.Fatalf("batch entry trackCount = %d, want 1", e.TrackCount)
	}

	// The straggler completes against the closed batch: its
	// conditional persist hits zero rows and it opens its own entry.
	sealed := completeUploadSession(t, h, h.token, late.Id)
	if sealed.ReviewEntryId == nil {
		t.Fatal("straggler opened no entry")
	}
	if *sealed.ReviewEntryId == batchEntry {
		t.Fatal("straggler landed in the closed batch's entry")
	}
	if e := getReview(t, h, *sealed.ReviewEntryId); e.TrackCount != 1 {
		t.Fatalf("straggler entry trackCount = %d, want 1", e.TrackCount)
	}

	// Finalize again: idempotent, same entry list, and the straggler's
	// own entry never joins it.
	again := finalizeBatch(t, h, h.token, b.Id)
	if again.State != "finalized" || len(again.ReviewEntryIds) != 1 || again.ReviewEntryIds[0] != batchEntry {
		t.Fatalf("re-finalize = %+v, want the same single entry", again)
	}
}

// TestUploadBatchExpiry covers the janitor: an overdue batch
// auto-finalizes with what arrived (state expired, conflict on a late
// client finalize), an empty overdue batch expires without entries,
// and members of a still-open batch are exempt from session expiry.
func TestUploadBatchExpiry(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	staging := t.TempDir()
	paths, err := fixtures.Generate(staging,
		batchTrackSpec("exp-1", "Kept Work", "Expiring", "Ensemble", "1", 3))
	if err != nil {
		t.Fatal(err)
	}

	// A member of an open batch survives session expiry.
	b := createBatch(t, h, h.token, "album", "music")
	member := uploadBatchMember(t, h, h.token, paths[0], "music", b.Id, "")
	if _, err := h.store.Writer().ExecContext(ctx,
		"UPDATE uploads SET expires_at_ns = 1 WHERE id = ?", member.Id); err != nil {
		t.Fatal(err)
	}
	for h.svc.DrainExpiredUploads(ctx) {
	}
	kept := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+member.Id, h.token))
	if kept.State != "staged" {
		t.Fatalf("open-batch member state after sweep = %q, want staged", kept.State)
	}

	// The batch goes overdue: the janitor finalizes it with the staged
	// member, and a late client finalize answers conflict.
	if _, err := h.store.Writer().ExecContext(ctx,
		"UPDATE upload_batches SET expires_at_ns = 1 WHERE id = ?", b.Id); err != nil {
		t.Fatal(err)
	}
	if !h.svc.DrainExpiredUploadBatches(ctx) {
		t.Fatal("janitor found no overdue batch")
	}
	entried := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+member.Id, h.token))
	if entried.ReviewEntryId == nil {
		t.Fatal("expired batch opened no entry for its staged member")
	}
	if r := h.postJSON(t, "/api/v1/uploads/batches/"+b.Id+"/complete", nil); r.StatusCode != 409 {
		t.Fatalf("finalize after expiry status = %d, want 409", r.StatusCode)
	}

	// Once the batch is closed the member is back under normal
	// retention: the next sweep reaps it and discards its entry.
	for h.svc.DrainExpiredUploads(ctx) {
	}
	reaped := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+member.Id, h.token))
	if reaped.State != "discarded" {
		t.Fatalf("closed-batch member state after sweep = %q, want discarded", reaped.State)
	}

	// An overdue batch with nothing staged expires empty.
	empty := createBatch(t, h, h.token, "auto", "music")
	if _, err := h.store.Writer().ExecContext(ctx,
		"UPDATE upload_batches SET expires_at_ns = 1 WHERE id = ?", empty.Id); err != nil {
		t.Fatal(err)
	}
	if !h.svc.DrainExpiredUploadBatches(ctx) {
		t.Fatal("janitor found no overdue empty batch")
	}
	if r := h.postJSON(t, "/api/v1/uploads/batches/"+empty.Id+"/complete", nil); r.StatusCode != 409 {
		t.Fatalf("finalize after empty expiry status = %d, want 409", r.StatusCode)
	}
}

// TestUploadBatchRepairPaths covers the two interrupted-finalize
// states the repair machinery heals: an expired batch whose entry
// opening never ran (the janitor's repair arm re-lists it), and a
// member whose link was lost after its entry opened (the retry
// re-links into the recorded entry instead of double-opening).
func TestUploadBatchRepairPaths(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	staging := t.TempDir()
	paths, err := fixtures.Generate(staging,
		batchTrackSpec("rep-1", "Healed One", "Repairs", "Ensemble", "1", 3),
		batchTrackSpec("rep-2", "Healed Two", "Repairs", "Ensemble", "2", 3),
	)
	if err != nil {
		t.Fatal(err)
	}

	// An expired batch with staged members and no entries: the state a
	// crash between the janitor's flip and its entry opening leaves.
	b := createBatch(t, h, h.token, "album", "music")
	m1 := uploadBatchMember(t, h, h.token, paths[0], "music", b.Id, "")
	if _, err := h.store.Writer().ExecContext(ctx,
		"UPDATE upload_batches SET state = 'expired' WHERE id = ?", b.Id); err != nil {
		t.Fatal(err)
	}
	if !h.svc.DrainExpiredUploadBatches(ctx) {
		t.Fatal("janitor did not pick up the half-expired batch")
	}
	healed := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+m1.Id, h.token))
	if healed.ReviewEntryId == nil {
		t.Fatal("repair arm opened no entry for the stranded member")
	}
	// Fully processed: the batch drops out of the janitor's listing.
	if h.svc.DrainExpiredUploadBatches(ctx) {
		t.Fatal("janitor re-listed a fully repaired batch")
	}

	// A finalized batch whose member lost its link after the entry
	// opened: the retry must re-link into the recorded entry, never
	// open a second one over the same file.
	b2 := createBatch(t, h, h.token, "tracks", "music")
	m2 := uploadBatchMember(t, h, h.token, paths[1], "music", b2.Id, "")
	done := finalizeBatch(t, h, h.token, b2.Id)
	if len(done.ReviewEntryIds) != 1 {
		t.Fatalf("batch entries = %d, want 1", len(done.ReviewEntryIds))
	}
	if _, err := h.store.Writer().ExecContext(ctx,
		"UPDATE uploads SET review_entry_id = '' WHERE id = ?", m2.Id); err != nil {
		t.Fatal(err)
	}
	again := finalizeBatch(t, h, h.token, b2.Id)
	if len(again.ReviewEntryIds) != 1 || again.ReviewEntryIds[0] != done.ReviewEntryIds[0] {
		t.Fatalf("re-finalize entries = %v, want the original %v", again.ReviewEntryIds, done.ReviewEntryIds)
	}
	relinked := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+m2.Id, h.token))
	if relinked.ReviewEntryId == nil || *relinked.ReviewEntryId != done.ReviewEntryIds[0] {
		t.Fatalf("member relink = %v, want %s", relinked.ReviewEntryId, done.ReviewEntryIds[0])
	}
}

// TestUploadBatchConcurrentFinalize races two finalizes of one batch:
// exactly one set of entries may open, whichever call flips.
func TestUploadBatchConcurrentFinalize(t *testing.T) {
	h := newHarness(t)
	staging := t.TempDir()
	paths, err := fixtures.Generate(staging,
		batchTrackSpec("race-1", "Race One", "Racing", "Ensemble", "1", 3),
		batchTrackSpec("race-2", "Race Two", "Racing", "Ensemble", "2", 3),
	)
	if err != nil {
		t.Fatal(err)
	}
	b := createBatch(t, h, h.token, "album", "music")
	for _, p := range paths {
		uploadBatchMember(t, h, h.token, p, "music", b.Id, "")
	}
	// Raw requests: the shared helpers t.Fatal, which is illegal off
	// the test goroutine.
	type outcome struct {
		batch UploadBatch
		err   error
	}
	results := make(chan outcome, 2)
	for range 2 {
		go func() {
			var out outcome
			req, err := http.NewRequest("POST",
				h.ts.URL+"/api/v1/uploads/batches/"+b.Id+"/complete", nil)
			if err != nil {
				out.err = err
				results <- out
				return
			}
			req.Header.Set("Authorization", "Bearer "+h.token)
			resp, err := http.DefaultClient.Do(req)
			if err != nil {
				out.err = err
				results <- out
				return
			}
			defer resp.Body.Close()
			if resp.StatusCode != 200 {
				out.err = fmt.Errorf("finalize status %d", resp.StatusCode)
				results <- out
				return
			}
			out.err = json.NewDecoder(resp.Body).Decode(&out.batch)
			results <- out
		}()
	}
	one, two := <-results, <-results
	if one.err != nil || two.err != nil {
		t.Fatalf("concurrent finalizes errored: %v / %v", one.err, two.err)
	}
	first, second := one.batch, two.batch
	if len(first.ReviewEntryIds) != 1 || len(second.ReviewEntryIds) != 1 {
		t.Fatalf("concurrent finalizes opened %d/%d entries, want 1/1",
			len(first.ReviewEntryIds), len(second.ReviewEntryIds))
	}
	if first.ReviewEntryIds[0] != second.ReviewEntryIds[0] {
		t.Fatalf("concurrent finalizes disagree: %v vs %v",
			first.ReviewEntryIds, second.ReviewEntryIds)
	}
	if e := getReview(t, h, first.ReviewEntryIds[0]); e.TrackCount != 2 {
		t.Fatalf("entry trackCount = %d, want 2", e.TrackCount)
	}
}

// TestUploadQuotaAndEffectiveRights covers the listing's quota
// snapshot and the self view's effective uploadEnabled.
func TestUploadQuotaAndEffectiveRights(t *testing.T) {
	h := newHarness(t)

	// The admin's own self view says uploads are enabled even though
	// the stored flag was never set.
	session := decode[SessionInfo](t, get(t, h.ts, "/api/v1/auth/session", h.token))
	if session.User == nil || !session.User.UploadEnabled {
		t.Fatalf("admin effective uploadEnabled = %+v, want true", session.User)
	}

	// A fresh account starts without the right; granting flips the
	// self view.
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "quotauser", "password": "long-enough-pw",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	acct := decode[UserAccount](t, resp)
	login := loginAs(t, h.ts, "quotauser", "long-enough-pw")
	if login.User.UploadEnabled {
		t.Fatal("fresh account claims upload rights")
	}
	grantBody, _ := json.Marshal(map[string]any{
		"uploadEnabled": true, "uploadQuotaBytes": 1 << 20,
	})
	req, _ := http.NewRequest("PATCH", h.ts.URL+"/api/v1/users/"+acct.Id, bytes.NewReader(grantBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+h.token)
	r, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if r.StatusCode != 200 {
		t.Fatalf("grant status = %d", r.StatusCode)
	}
	granted := loginAs(t, h.ts, "quotauser", "long-enough-pw")
	if !granted.User.UploadEnabled {
		t.Fatal("granted account still claims no upload rights")
	}

	// The listing carries the caller's own quota: the declared size of
	// live sessions against the cap.
	userToken := granted.Token
	body, _ := json.Marshal(map[string]any{
		"fileName": "quota-probe.mp3", "sizeBytes": 4096, "mediaType": "music",
	})
	req, _ = http.NewRequest("POST", h.ts.URL+"/api/v1/uploads", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+userToken)
	r, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if r.StatusCode != 201 {
		t.Fatalf("probe session status = %d", r.StatusCode)
	}
	page := decode[UploadPage](t, get(t, h.ts, "/api/v1/uploads", userToken))
	if page.Quota == nil {
		t.Fatal("uploads page carries no quota")
	}
	if page.Quota.BytesInUse != 4096 {
		t.Fatalf("bytesInUse = %d, want 4096", page.Quota.BytesInUse)
	}
	if page.Quota.QuotaBytes == nil || *page.Quota.QuotaBytes != 1<<20 {
		t.Fatalf("quotaBytes = %v, want %d", page.Quota.QuotaBytes, 1<<20)
	}

	// The uncapped admin sees usage with no cap.
	adminPage := decode[UploadPage](t, get(t, h.ts, "/api/v1/uploads", h.token))
	if adminPage.Quota == nil || adminPage.Quota.QuotaBytes != nil {
		t.Fatalf("admin quota = %+v, want usage with no cap", adminPage.Quota)
	}
}

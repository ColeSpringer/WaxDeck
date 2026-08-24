package api

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"

	"github.com/colespringer/waxdeck/fixtures"
	"github.com/colespringer/waxdeck/server/internal/match"
	"github.com/colespringer/waxdeck/server/internal/service"
)

// cannedSource is a deterministic CandidateSource for the pipeline
// tests: search answers from a fixed release set, fingerprints and
// groups answer nothing.
type cannedSource struct {
	releases []*match.Release
}

func (c *cannedSource) ReleaseByMBID(_ context.Context, mbid string) (*match.Release, error) {
	for _, r := range c.releases {
		if r.MBID == mbid {
			return r, nil
		}
	}
	return nil, nil
}

func (c *cannedSource) ReleasesByGroup(context.Context, string) ([]*match.Release, error) {
	return nil, nil
}

func (c *cannedSource) LookupFingerprint(context.Context, match.Fingerprint) ([]match.FingerprintHit, error) {
	return nil, nil
}

func (c *cannedSource) SearchReleases(context.Context, string, string, int) ([]*match.Release, error) {
	return c.releases, nil
}

func (c *cannedSource) SearchRecordings(context.Context, string, string) ([]*match.Release, error) {
	return c.releases, nil
}

// drainMatches runs the identify worker until idle.
func drainMatches(t *testing.T, h *harness) {
	t.Helper()
	deadline := time.Now().Add(30 * time.Second)
	for h.svc.DrainMatchQueue(context.Background()) {
		if time.Now().After(deadline) {
			t.Fatal("identify worker did not drain")
		}
	}
}

// getReview fetches one review entry.
func getReview(t *testing.T, h *harness, id string) ReviewEntryDetail {
	t.Helper()
	resp := get(t, h.ts, "/api/v1/review/queue/"+id, h.token)
	if resp.StatusCode != 200 {
		t.Fatalf("review entry status = %d", resp.StatusCode)
	}
	return decode[ReviewEntryDetail](t, resp)
}

// nightfallRelease is the canned right answer for the messy fixture
// album the loose-files test generates.
func nightfallRelease() *match.Release {
	return &match.Release{
		MBID:             "rel-nightfall",
		ReleaseGroupMBID: "rg-nightfall",
		Title:            "Nightfall Circuit",
		Artist:           "The Cardinal Waves",
		Year:             2014,
		Media:            1,
		Tracks: []match.ReleaseTrack{
			{RecordingMBID: "00000000-0000-4000-8000-000000000001", Title: "Harbor Lights", Disc: 1, Position: 1, DurationSec: 3},
			{RecordingMBID: "00000000-0000-4000-8000-000000000002", Title: "Copper Sky", Disc: 1, Position: 2, DurationSec: 4},
			{RecordingMBID: "00000000-0000-4000-8000-000000000003", Title: "Meridian Line", Disc: 1, Position: 3, DurationSec: 5},
		},
	}
}

// messyNightfallSpecs synthesizes the album with wrong artist
// spelling, a renamed album, and no track numbers.
func messyNightfallSpecs() []fixtures.Spec {
	mk := func(name, title string, sec int) fixtures.Spec {
		return fixtures.Spec{
			Name:     name,
			Codec:    fixtures.CodecFLAC,
			Duration: time.Duration(sec) * time.Second,
			Tags: map[string]string{
				"TITLE":  title,
				"ARTIST": "The Cardnal Waves",
				"ALBUM":  "Nightfall Circuit",
			},
		}
	}
	return []fixtures.Spec{
		mk("nf-one", "Harbor Lights", 3),
		mk("nf-two", "Copper Sky", 4),
		mk("nf-three", "Meridian Line", 5),
	}
}

// TestLooseAlbumMatchesAndAutoApplies is the loose-files acceptance:
// a messy fixture album clusters, matches the canned release, auto
// applies, and the applied fields survive a rescan because the apply
// locks them.
func TestLooseAlbumMatchesAndAutoApplies(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{releases: []*match.Release{nightfallRelease()}}
	})
	if _, err := fixtures.Generate(h.library, messyNightfallSpecs()...); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	page := h.items(t, "?limit=100")
	var seedPid string
	for _, it := range page.Items {
		if it.Title == "Harbor Lights" {
			seedPid = it.Pid
		}
	}
	if seedPid == "" {
		t.Fatalf("messy album track not scanned: %+v", page.Items)
	}

	resp := h.postJSON(t, "/api/v1/items/"+seedPid+"/rematch", nil)
	if resp.StatusCode != 202 {
		t.Fatalf("rematch status = %d", resp.StatusCode)
	}
	entryID := decode[RematchResult](t, resp).ReviewEntryId
	drainMatches(t, h)

	entry := getReview(t, h, entryID)
	if entry.Identifying {
		t.Fatal("entry still identifying after drain")
	}
	if entry.Status != "auto-applied" {
		var comps any
		if len(entry.Candidates) > 0 {
			comps = entry.Candidates[0].Components
		}
		t.Fatalf("entry status = %q, want auto-applied (best %+v, components %+v, tracks %+v)",
			entry.Status, entry.Best, comps, entry.Tracks)
	}
	if entry.Best == nil || entry.Best.Mbid != "rel-nightfall" {
		t.Fatalf("wrong applied candidate: %+v", entry.Best)
	}
	if len(entry.Candidates) == 0 || len(entry.Candidates[0].Pairings) != 3 {
		t.Fatalf("candidate evidence missing: %+v", entry.Candidates)
	}

	// The catalog now carries the corrected fields.
	assertApplied := func() {
		t.Helper()
		page := h.items(t, "?limit=100")
		found := 0
		for _, it := range page.Items {
			if it.Album != nil && *it.Album == "Nightfall Circuit" && it.Artist != nil && *it.Artist == "The Cardinal Waves" {
				found++
			}
		}
		if found != 3 {
			t.Fatalf("%d tracks carry the applied metadata, want 3", found)
		}
	}
	assertApplied()

	// A rescan re-reads the files' old tags; the applied fields are
	// locked and must survive.
	h.rescanAndWait(t)
	assertApplied()

	// Calibration counts the auto apply.
	stats := decode[ReviewStats](t, get(t, h.ts, "/api/v1/review/stats", h.token))
	if stats.AutoApplied < 1 {
		t.Fatalf("stats = %+v, want an auto apply", stats)
	}

	// Reverting restores the messy fields and shows up in calibration.
	resp = h.postJSON(t, "/api/v1/review/queue/"+entryID+"/revert", nil)
	if resp.StatusCode != 200 {
		t.Fatalf("revert status = %d", resp.StatusCode)
	}
	page = h.items(t, "?limit=100")
	reverted := 0
	for _, it := range page.Items {
		if it.Artist != nil && *it.Artist == "The Cardnal Waves" {
			reverted++
		}
	}
	if reverted != 3 {
		t.Fatalf("%d tracks reverted, want 3", reverted)
	}
	stats = decode[ReviewStats](t, get(t, h.ts, "/api/v1/review/stats", h.token))
	if stats.RevertedAutoApplied < 1 {
		t.Fatalf("stats after revert = %+v", stats)
	}
}

// uploadFile drives the chunked upload flow for one file and returns
// the completed session.
func uploadFile(t *testing.T, h *harness, token, path, mediaType, sum string) Upload {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	body := map[string]any{
		"fileName":  filepath.Base(path),
		"sizeBytes": len(raw),
		"mediaType": mediaType,
	}
	if sum != "" {
		body["sha256"] = sum
	}
	buf, _ := json.Marshal(body)
	req, _ := http.NewRequest("POST", h.ts.URL+"/api/v1/uploads", bytes.NewReader(buf))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 201 {
		t.Fatalf("create upload status = %d", resp.StatusCode)
	}
	up := decode[Upload](t, resp)

	half := len(raw) / 2
	for _, chunk := range []struct {
		offset int
		data   []byte
	}{{0, raw[:half]}, {half, raw[half:]}} {
		req, _ := http.NewRequest("PUT",
			h.ts.URL+"/api/v1/uploads/"+up.Id+"/data?offset="+itoaTest(chunk.offset),
			bytes.NewReader(chunk.data))
		req.Header.Set("Content-Type", "application/octet-stream")
		req.Header.Set("Authorization", "Bearer "+token)
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		if resp.StatusCode != 200 {
			t.Fatalf("chunk at %d status = %d", chunk.offset, resp.StatusCode)
		}
		resp.Body.Close()
	}

	req, _ = http.NewRequest("POST", h.ts.URL+"/api/v1/uploads/"+up.Id+"/complete", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	resp, err = http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("complete status = %d", resp.StatusCode)
	}
	return decode[Upload](t, resp)
}

func itoaTest(n int) string {
	if n == 0 {
		return "0"
	}
	digits := []byte{}
	for n > 0 {
		digits = append([]byte{byte('0' + n%10)}, digits...)
		n /= 10
	}
	return string(digits)
}

// TestUploadIdentifyReviewImport is the upload acceptance across all
// three media types: chunked upload, identify, review decision, and
// the file entering the library.
func TestUploadIdentifyReviewImport(t *testing.T) {
	t.Parallel()
	podcasts := t.TempDir()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{releases: []*match.Release{{
			MBID: "rel-single", ReleaseGroupMBID: "rg-single",
			Title: "Lone Signal", Artist: "Beacon Row", Year: 2019, Media: 1,
			Tracks: []match.ReleaseTrack{{
				RecordingMBID: "00000000-0000-4000-8000-000000000010", Title: "Lone Signal",
				Disc: 1, Position: 1, DurationSec: 4,
			}},
		}}}
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
		cfg.PodcastDir = podcasts
		cfg.PodcastRootName = "podcasts"
	})

	staging := t.TempDir()

	// Music: approve the identified candidate; the file imports and the
	// candidate's metadata applies.
	paths, err := fixtures.Generate(staging, fixtures.Spec{
		Name: "lone-signal", Codec: fixtures.CodecMP3, Duration: 4 * time.Second,
		Tags: map[string]string{"TITLE": "Lone Signal", "ARTIST": "Beacon Row", "ALBUM": "Lone Signal"},
	})
	if err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(paths[0])
	sum := sha256.Sum256(raw)
	up := uploadFile(t, h, h.token, paths[0], "music", hex.EncodeToString(sum[:]))
	if up.State != "staged" || up.ReviewEntryId == nil {
		t.Fatalf("completed upload = %+v", up)
	}
	drainMatches(t, h)
	entry := getReview(t, h, *up.ReviewEntryId)
	if entry.Status != "pending" && entry.Status != "auto-applied" {
		t.Fatalf("music entry status = %q", entry.Status)
	}
	if entry.Status == "pending" {
		if len(entry.Candidates) == 0 {
			t.Fatalf("music entry has no candidates")
		}
		resp := h.postJSON(t, "/api/v1/review/queue/"+entry.Id+"/decide",
			map[string]any{"action": "approve"})
		if resp.StatusCode != 200 {
			t.Fatalf("approve status = %d", resp.StatusCode)
		}
	}
	h.rescanAndWait(t)
	page := h.items(t, "?limit=200")
	foundMusic := false
	for _, it := range page.Items {
		if it.Title == "Lone Signal" && it.Artist != nil && *it.Artist == "Beacon Row" {
			foundMusic = true
		}
	}
	if !foundMusic {
		t.Fatal("uploaded track did not enter the library")
	}
	final := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+up.Id, h.token))
	if final.State != "imported" {
		t.Fatalf("upload state = %q, want imported", final.State)
	}

	// Audiobook: accepted as-is (no matching for books), imported.
	bookPaths, err := fixtures.Generate(staging, fixtures.Spec{
		Name: "harbor-tales", Codec: fixtures.CodecAAC, Container: fixtures.ContainerMP4,
		Duration: 5 * time.Second,
		Tags: map[string]string{
			"TITLE": "Harbor Tales", "ARTIST": "N. Wright", "ALBUM": "Harbor Tales",
			"ALBUMARTIST": "N. Wright",
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	m4b := filepath.Join(staging, "harbor-tales.m4b")
	if err := os.Rename(bookPaths[0], m4b); err != nil {
		t.Fatal(err)
	}
	bup := uploadFile(t, h, h.token, m4b, "audiobook", "")
	if bup.ReviewEntryId == nil {
		t.Fatalf("book upload has no review entry: %+v", bup)
	}
	drainMatches(t, h)
	resp := h.postJSON(t, "/api/v1/review/queue/"+*bup.ReviewEntryId+"/decide",
		map[string]any{"action": "as-is"})
	if resp.StatusCode != 200 {
		t.Fatalf("book as-is status = %d", resp.StatusCode)
	}
	h.rescanAndWait(t)
	foundBook := false
	for _, it := range h.items(t, "?mediaType=audiobook&limit=200").Items {
		if it.Title == "Harbor Tales" {
			foundBook = true
		}
	}
	if !foundBook {
		t.Fatal("uploaded audiobook did not enter the library")
	}

	// Podcast episode: as-is ingest under a manual show.
	epPaths, err := fixtures.Generate(staging, fixtures.Spec{
		Name: "field-notes-12", Codec: fixtures.CodecMP3, Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Field Notes 12", "ARTIST": "Field Notes"},
	})
	if err != nil {
		t.Fatal(err)
	}
	eup := uploadFile(t, h, h.token, epPaths[0], "podcast", "")
	if eup.ReviewEntryId == nil {
		t.Fatalf("episode upload has no review entry: %+v", eup)
	}
	drainMatches(t, h)
	resp = h.postJSON(t, "/api/v1/review/queue/"+*eup.ReviewEntryId+"/decide",
		map[string]any{"action": "as-is"})
	if resp.StatusCode != 200 {
		t.Fatalf("episode as-is status = %d", resp.StatusCode)
	}
	eFinal := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+eup.Id, h.token))
	if eFinal.State != "imported" {
		t.Fatalf("episode upload state = %q, want imported", eFinal.State)
	}

	// A byte-identical re-upload warns about the duplicate at
	// completion (essence match against the imported copy).
	dupPaths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "lone-signal", Codec: fixtures.CodecMP3, Duration: 4 * time.Second,
		Tags: map[string]string{"TITLE": "Lone Signal", "ARTIST": "Beacon Row", "ALBUM": "Lone Signal"},
	})
	if err != nil {
		t.Fatal(err)
	}
	dup := uploadFile(t, h, h.token, dupPaths[0], "music", "")
	if dup.Duplicate == nil {
		t.Fatal("re-upload of identical audio carried no duplicate warning")
	}
}

// TestDecideImportFailureKeepsEntryAndBytes pins the failure contract
// of a decide whose import cannot land (here: an unwritable library
// root). The decide must answer a conflict naming the real reason, the
// entry must stay pending, and the staged bytes must survive - so the
// same decision succeeds once the cause is fixed. The regression it
// guards: a failed import was reported as "the planner quarantined the
// file" while the entry was marked decided, the session marked
// imported, and the staged bytes deleted.
func TestDecideImportFailureKeepsEntryAndBytes(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h := newHarnessWith(t, func(cfg *service.Config) {
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})

	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "stuck-signal", Codec: fixtures.CodecMP3, Duration: 4 * time.Second,
		Tags: map[string]string{"TITLE": "Stuck Signal", "ARTIST": "Beacon Row", "ALBUM": "Stuck Signal"},
	})
	if err != nil {
		t.Fatal(err)
	}
	up := uploadFile(t, h, h.token, paths[0], "music", "")
	if up.ReviewEntryId == nil {
		t.Fatalf("upload has no review entry: %+v", up)
	}
	drainMatches(t, h)

	if err := os.Chmod(h.library, 0o555); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(h.library, 0o755) })

	resp := h.postJSON(t, "/api/v1/review/queue/"+*up.ReviewEntryId+"/decide",
		map[string]any{"action": "as-is"})
	if resp.StatusCode != 409 {
		t.Fatalf("decide with unwritable library status = %d, want 409", resp.StatusCode)
	}
	apiErr := decode[Error](t, resp)
	if !strings.Contains(apiErr.Message, "permission denied") {
		t.Fatalf("conflict message = %q, want the import's own reason", apiErr.Message)
	}

	entry := getReview(t, h, *up.ReviewEntryId)
	if entry.Status != "pending" {
		t.Fatalf("entry status after failed decide = %q, want pending", entry.Status)
	}
	mid := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+up.Id, h.token))
	if mid.State != "staged" {
		t.Fatalf("upload state after failed decide = %q, want staged", mid.State)
	}

	if err := os.Chmod(h.library, 0o755); err != nil {
		t.Fatal(err)
	}
	resp = h.postJSON(t, "/api/v1/review/queue/"+*up.ReviewEntryId+"/decide",
		map[string]any{"action": "as-is"})
	if resp.StatusCode != 200 {
		t.Fatalf("retried decide status = %d, want 200", resp.StatusCode)
	}
	final := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+up.Id, h.token))
	if final.State != "imported" {
		t.Fatalf("upload state after retry = %q, want imported", final.State)
	}
	h.rescanAndWait(t)
	found := false
	for _, it := range h.items(t, "?limit=200").Items {
		if it.Title == "Stuck Signal" {
			found = true
		}
	}
	if !found {
		t.Fatal("retried decide did not land the track in the library")
	}
}

// TestDiscardRefusedAfterPartialImport drives a unit where one track
// imports and its sibling cannot (its rendered destination is already
// occupied): the decide must fail carrying the planner's own verdict,
// the imported half must settle while the failed half keeps its staged
// bytes, and discarding the pending entry must be refused while the
// imported item still exists - discard would otherwise orphan it.
func TestDiscardRefusedAfterPartialImport(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
	})
	staging := t.TempDir()

	// Occupy the destination: import a track, then stage a same-tagged
	// sibling whose path renders identically.
	paths, err := fixtures.Generate(staging,
		batchTrackSpec("occupant", "First Half", "Split Decision", "Beacon Row", "1", 3))
	if err != nil {
		t.Fatal(err)
	}
	occ := uploadFile(t, h, h.token, paths[0], "music", "")
	drainMatches(t, h)
	resp := h.postJSON(t, "/api/v1/review/queue/"+*occ.ReviewEntryId+"/decide",
		map[string]any{"action": "as-is"})
	if resp.StatusCode != 200 {
		t.Fatalf("occupant as-is status = %d", resp.StatusCode)
	}

	member, err := fixtures.Generate(staging,
		batchTrackSpec("collider", "First Half", "Split Decision", "Beacon Row", "1", 5),
		batchTrackSpec("survivor", "Second Half", "Split Decision", "Beacon Row", "2", 4))
	if err != nil {
		t.Fatal(err)
	}
	batch := createBatch(t, h, h.token, "album", "music")
	collider := uploadBatchMember(t, h, h.token, member[0], "music", batch.Id, "")
	survivor := uploadBatchMember(t, h, h.token, member[1], "music", batch.Id, "")
	done := finalizeBatch(t, h, h.token, batch.Id)
	if len(done.ReviewEntryIds) != 1 {
		t.Fatalf("batch entries = %d, want 1", len(done.ReviewEntryIds))
	}
	entryID := done.ReviewEntryIds[0]
	drainMatches(t, h)

	resp = h.postJSON(t, "/api/v1/review/queue/"+entryID+"/decide",
		map[string]any{"action": "as-is"})
	if resp.StatusCode != 409 {
		t.Fatalf("partial decide status = %d, want 409", resp.StatusCode)
	}
	apiErr := decode[Error](t, resp)
	if !strings.Contains(apiErr.Message, "destination already exists") {
		t.Fatalf("conflict message = %q, want the planner's verdict", apiErr.Message)
	}
	if e := getReview(t, h, entryID); e.Status != "pending" {
		t.Fatalf("entry status after partial decide = %q, want pending", e.Status)
	}
	if u := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+collider.Id, h.token)); u.State != "staged" {
		t.Fatalf("collider state = %q, want staged", u.State)
	}
	if u := decode[Upload](t, get(t, h.ts, "/api/v1/uploads/"+survivor.Id, h.token)); u.State != "imported" {
		t.Fatalf("survivor state = %q, want imported", u.State)
	}

	resp = h.postJSON(t, "/api/v1/review/queue/"+entryID+"/decide",
		map[string]any{"action": "discard"})
	if resp.StatusCode != 409 {
		t.Fatalf("discard after partial import status = %d, want 409", resp.StatusCode)
	}
	apiErr = decode[Error](t, resp)
	if !strings.Contains(apiErr.Message, "already entered the library") {
		t.Fatalf("discard refusal message = %q", apiErr.Message)
	}

	// Deleting the still-staged half must be refused the same way: it
	// would discard the pending entry and orphan the landed items.
	req, _ := http.NewRequest("DELETE", h.ts.URL+"/api/v1/uploads/"+collider.Id, nil)
	req.Header.Set("Authorization", "Bearer "+h.token)
	dresp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	dresp.Body.Close()
	if dresp.StatusCode != 409 {
		t.Fatalf("delete of partial unit's staged upload status = %d, want 409", dresp.StatusCode)
	}

	// The expiry janitor must defer the row, not reclaim it: bytes kept,
	// expiry re-armed, entry still pending.
	row, err := h.store.UploadByID(context.Background(), collider.Id)
	if err != nil {
		t.Fatal(err)
	}
	row.ExpiresAtNS = 1
	if err := h.store.UpdateUpload(context.Background(), row); err != nil {
		t.Fatal(err)
	}
	h.svc.DrainExpiredUploads(context.Background())
	row, err = h.store.UploadByID(context.Background(), collider.Id)
	if err != nil {
		t.Fatal(err)
	}
	if row.State != "staged" {
		t.Fatalf("expired collider state = %q, want staged", row.State)
	}
	if row.ExpiresAtNS <= time.Now().UnixNano() {
		t.Fatal("collider expiry was not re-armed")
	}
	if e := getReview(t, h, entryID); e.Status != "pending" {
		t.Fatalf("entry status after expiry sweep = %q, want pending", e.Status)
	}
}

// TestUploadPermissionsAndQuota covers the grant and the quota gates.
func TestUploadPermissionsAndQuota(t *testing.T) {
	t.Parallel()
	h := newHarness(t)

	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "uploader", "password": "long-enough-pw",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	acct := decode[UserAccount](t, resp)
	userToken := loginAs(t, h.ts, "uploader", "long-enough-pw").Token

	// No upload rights: refused.
	body := map[string]any{"fileName": "x.mp3", "sizeBytes": 1000, "mediaType": "music"}
	raw, _ := json.Marshal(body)
	req, _ := http.NewRequest("POST", h.ts.URL+"/api/v1/uploads", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+userToken)
	r1, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if r1.StatusCode != 403 {
		t.Fatalf("upload without rights status = %d, want 403", r1.StatusCode)
	}

	// Granted with a tiny quota: a too-large declaration answers the
	// typed quota error. Account updates are PATCH.
	grantBody, _ := json.Marshal(map[string]any{
		"uploadEnabled": true, "uploadQuotaBytes": 500,
	})
	patchReq, _ := http.NewRequest("PATCH", h.ts.URL+"/api/v1/users/"+acct.Id, bytes.NewReader(grantBody))
	patchReq.Header.Set("Content-Type", "application/json")
	patchReq.Header.Set("Authorization", "Bearer "+h.token)
	resp, err = http.DefaultClient.Do(patchReq)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != 200 {
		t.Fatalf("grant status = %d", resp.StatusCode)
	}
	req, _ = http.NewRequest("POST", h.ts.URL+"/api/v1/uploads", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+userToken)
	r2, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if r2.StatusCode != 413 {
		t.Fatalf("over-quota status = %d, want 413", r2.StatusCode)
	}
	var e Error
	if err := json.NewDecoder(r2.Body).Decode(&e); err != nil || e.Code != "quota-exceeded" {
		t.Fatalf("over-quota error = %+v (%v)", e, err)
	}

	// An unsupported extension is refused up front.
	badBody, _ := json.Marshal(map[string]any{"fileName": "x.exe", "sizeBytes": 10, "mediaType": "music"})
	req, _ = http.NewRequest("POST", h.ts.URL+"/api/v1/uploads", bytes.NewReader(badBody))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+h.token)
	r3, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	if r3.StatusCode != 415 {
		t.Fatalf("bad extension status = %d, want 415", r3.StatusCode)
	}
}

// TestReviewDecisionsAndVisibility covers skip, unofficial, bulk, the
// matching mode surface, and non-admin visibility.
func TestReviewDecisionsAndVisibility(t *testing.T) {
	t.Parallel()
	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.MatchSource = &cannedSource{releases: []*match.Release{nightfallRelease()}}
	})
	if _, err := fixtures.Generate(h.library, messyNightfallSpecs()...); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)

	// Force everything to review: the mode gates auto apply.
	libs := decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token))
	if len(libs.Libraries) == 0 {
		t.Fatal("no libraries")
	}
	libPid := libs.Libraries[0].Pid
	resp := h.putJSON(t, "/api/v1/libraries/"+libPid+"/matching", map[string]any{"mode": "review"})
	if resp.StatusCode != 200 {
		t.Fatalf("set matching mode status = %d", resp.StatusCode)
	}
	// The read reflects the stored mode, and an unknown library is a
	// not-found rather than a fabricated default.
	got := decode[LibraryMatching](t, get(t, h.ts, "/api/v1/libraries/"+libPid+"/matching", h.token))
	if string(got.Mode) != "review" {
		t.Fatalf("read matching mode = %q, want review", got.Mode)
	}
	bogus := get(t, h.ts, "/api/v1/libraries/lb-01JZX5N8QW3F4V9T2B7KD3M9R6/matching", h.token)
	if bogus.StatusCode != 404 {
		t.Fatalf("unknown library matching status = %d, want 404", bogus.StatusCode)
	}

	var seedPid string
	for _, it := range h.items(t, "?limit=100").Items {
		if it.Title == "Harbor Lights" {
			seedPid = it.Pid
		}
	}
	resp = h.postJSON(t, "/api/v1/items/"+seedPid+"/rematch", nil)
	entryID := decode[RematchResult](t, resp).ReviewEntryId
	drainMatches(t, h)

	entry := getReview(t, h, entryID)
	if entry.Status != "pending" {
		t.Fatalf("review mode entry status = %q, want pending", entry.Status)
	}
	if entry.Best == nil {
		t.Fatal("pending entry should still carry candidates")
	}

	// Mark it unofficial: terminal state, listed under the filter.
	resp = h.postJSON(t, "/api/v1/review/queue/"+entryID+"/decide", map[string]any{"action": "unofficial"})
	if resp.StatusCode != 200 {
		t.Fatalf("unofficial decide status = %d", resp.StatusCode)
	}
	listed := decode[ReviewEntryPage](t, get(t, h.ts, "/api/v1/review/queue?status=unofficial", h.token))
	found := false
	for _, e := range listed.Entries {
		if e.Id == entryID {
			found = true
		}
	}
	if !found {
		t.Fatal("unofficial entry missing from the filtered listing")
	}

	// Deciding again conflicts.
	resp = h.postJSON(t, "/api/v1/review/queue/"+entryID+"/decide", map[string]any{"action": "skip"})
	if resp.StatusCode != 409 {
		t.Fatalf("double decide status = %d, want 409", resp.StatusCode)
	}

	// A non-admin sees no admin entries.
	resp = h.postJSON(t, "/api/v1/users", map[string]any{"username": "plain", "password": "long-enough-pw"})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	plainToken := loginAs(t, h.ts, "plain", "long-enough-pw").Token
	otherList := decode[ReviewEntryPage](t, get(t, h.ts, "/api/v1/review/queue", plainToken))
	if len(otherList.Entries) != 0 {
		t.Fatalf("non-admin sees %d entries, want 0", len(otherList.Entries))
	}
}

// fakeAcquireSource is a canned acquisition provider: one playlist URL
// enumerating fixture-backed entries, and direct fetch for any URL it
// carries bytes for.
type fakeAcquireSource struct {
	playlistURL string
	entries     []struct{ title, url string }
	files       map[string]string
}

func (f *fakeAcquireSource) SourceType() model.SourceType { return model.SourceYouTube }

func (f *fakeAcquireSource) Resolve(_ context.Context, req source.Request) (*source.Resolved, error) {
	if req.URL != f.playlistURL {
		return nil, errors.New("not a playlist")
	}
	return &source.Resolved{IdentityKey: "youtube:test", SourceType: model.SourceYouTube, Title: "Test Playlist"}, nil
}

func (f *fakeAcquireSource) Enumerate(_ context.Context, req source.Request) (*source.Enumeration, error) {
	if req.URL != f.playlistURL {
		return nil, errors.New("not a playlist")
	}
	feed := &model.Feed{Title: "Test Playlist"}
	for _, e := range f.entries {
		feed.Episodes = append(feed.Episodes, model.FeedEpisode{Title: e.title, EnclosureURL: e.url})
	}
	return &source.Enumeration{Feed: feed, IdentityKey: "youtube:test"}, nil
}

func (f *fakeAcquireSource) Fetch(_ context.Context, req source.FetchRequest, w io.Writer) (*source.FetchResult, error) {
	path, ok := f.files[req.URL]
	if !ok {
		return nil, errors.New("no such video")
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	n, err := w.Write(raw)
	if err != nil {
		return nil, err
	}
	return &source.FetchResult{Bytes: int64(n), ContentType: "audio/mpeg"}, nil
}

func drainTools(t *testing.T, h *harness) {
	t.Helper()
	deadline := time.Now().Add(30 * time.Second)
	for h.svc.DrainToolTasks(context.Background()) {
		if time.Now().After(deadline) {
			t.Fatal("tool worker did not drain")
		}
	}
}

// TestAcquireFromURL covers the acquisition flow end to end: a
// playlist acquisition by a non-admin user with upload rights, the
// files staging and flowing through review, the as-is import, and the
// acquiring user's item-scoped editing rights afterward; then a
// single-video URL through the non-playlist fallback.
func TestAcquireFromURL(t *testing.T) {
	t.Parallel()
	media := t.TempDir()
	src := &fakeAcquireSource{
		playlistURL: "https://tube.example/playlist?list=PLtest",
		files:       map[string]string{},
	}
	paths, err := fixtures.Generate(media,
		fixtures.Spec{Name: "cut-one", Codec: fixtures.CodecMP3, Duration: 3 * time.Second,
			Tags: map[string]string{"TITLE": "Basement Cut One", "ARTIST": "DJ Harness", "ALBUM": "Basement Tapes Vol 1"}},
		fixtures.Spec{Name: "cut-two", Codec: fixtures.CodecMP3, Duration: 4 * time.Second,
			Tags: map[string]string{"TITLE": "Basement Cut Two", "ARTIST": "DJ Harness", "ALBUM": "Basement Tapes Vol 1"}},
		fixtures.Spec{Name: "lone-rip", Codec: fixtures.CodecMP3, Duration: 5 * time.Second,
			Tags: map[string]string{"TITLE": "Warehouse Set (Unreleased)", "ARTIST": "DJ Harness"}},
	)
	if err != nil {
		t.Fatal(err)
	}
	src.entries = []struct{ title, url string }{
		{"Basement Cut One", "https://tube.example/watch?v=one"},
		{"Basement Cut Two", "https://tube.example/watch?v=two"},
	}
	src.files["https://tube.example/watch?v=one"] = paths[0]
	src.files["https://tube.example/watch?v=two"] = paths[1]
	src.files["https://tube.example/watch?v=lone"] = paths[2]

	h := newHarnessWith(t, func(cfg *service.Config) {
		cfg.SourceProviders = append(cfg.SourceProviders, src)
		for i := range cfg.Roots {
			cfg.Roots[i].Managed = true
		}
		// The canned source URLs never resolve in DNS; skip the
		// private-address guard the way LAN-feed installs do.
		cfg.AllowPrivateFeedHosts = true
	})

	// A non-admin user with upload rights runs the acquisition.
	resp := h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "digger", "password": "long-enough-pw", "uploadEnabled": true,
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create user status = %d", resp.StatusCode)
	}
	digger := loginAs(t, h.ts, "digger", "long-enough-pw").Token

	post := func(token, path string, body any) *http.Response {
		raw, _ := json.Marshal(body)
		req, _ := http.NewRequest("POST", h.ts.URL+path, bytes.NewReader(raw))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+token)
		r, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		return r
	}

	resp = post(digger, "/api/v1/acquisitions", map[string]any{
		"url": src.playlistURL, "mediaType": "music",
	})
	if resp.StatusCode != 202 {
		t.Fatalf("acquisition status = %d", resp.StatusCode)
	}
	task := decode[ToolTask](t, resp)
	drainTools(t, h)
	drainMatches(t, h)

	got := decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+task.Id, digger))
	if got.State != "done" || got.ResultPids == nil || len(*got.ResultPids) != 1 {
		t.Fatalf("acquire task = %+v", got)
	}
	entryID := (*got.ResultPids)[0]

	// The entry belongs to the digger, who decides it without an admin.
	entry := decode[ReviewEntryDetail](t, get(t, h.ts, "/api/v1/review/queue/"+entryID, digger))
	if entry.TrackCount != 2 || entry.Origin != "acquisition" {
		t.Fatalf("acquire entry = %+v", entry)
	}
	resp = post(digger, "/api/v1/review/queue/"+entryID+"/decide", map[string]any{"action": "as-is"})
	if resp.StatusCode != 200 {
		t.Fatalf("as-is status = %d", resp.StatusCode)
	}
	h.rescanAndWait(t)
	var trackPid string
	for _, it := range h.items(t, "?limit=200").Items {
		if it.Title == "Basement Cut One" {
			trackPid = it.Pid
		}
	}
	if trackPid == "" {
		t.Fatal("acquired track did not enter the library")
	}

	// The acquiring user edits the item; another non-admin cannot.
	patch := func(token, path string, body any) *http.Response {
		raw, _ := json.Marshal(body)
		req, _ := http.NewRequest("PATCH", h.ts.URL+path, bytes.NewReader(raw))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+token)
		r, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		return r
	}
	resp = patch(digger, "/api/v1/items/"+trackPid+"/metadata", map[string]any{
		"fields": map[string]string{"title": "Basement Cut One (Extended)"},
	})
	if resp.StatusCode != 200 {
		t.Fatalf("owner edit status = %d", resp.StatusCode)
	}
	putReq := func(token, path string, body any) *http.Response {
		raw, _ := json.Marshal(body)
		req, _ := http.NewRequest("PUT", h.ts.URL+path, bytes.NewReader(raw))
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Authorization", "Bearer "+token)
		r, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		return r
	}
	resp = putReq(digger, "/api/v1/items/"+trackPid+"/release-status", map[string]any{"unofficial": true})
	if resp.StatusCode != 200 {
		t.Fatalf("owner mark-unofficial status = %d", resp.StatusCode)
	}

	resp = h.postJSON(t, "/api/v1/users", map[string]any{
		"username": "bystander", "password": "long-enough-pw",
	})
	if resp.StatusCode != 201 {
		t.Fatalf("create bystander status = %d", resp.StatusCode)
	}
	bystander := loginAs(t, h.ts, "bystander", "long-enough-pw").Token
	resp = patch(bystander, "/api/v1/items/"+trackPid+"/metadata", map[string]any{
		"fields": map[string]string{"title": "Hijacked"},
	})
	if resp.StatusCode != 403 {
		t.Fatalf("bystander edit status = %d, want 403", resp.StatusCode)
	}

	// The read answers all three the same way, so mayCurate is the only
	// thing on it that tells them apart - and it has to agree with the
	// three edits just made, or a client draws a form whose Save is
	// refused.
	mayCurate := func(who, token string) bool {
		meta := decode[ItemMetadata](t, get(t, h.ts, "/api/v1/items/"+trackPid+"/metadata", token))
		if meta.MayCurate == nil {
			t.Fatalf("%s: metadata read carried no mayCurate", who)
		}
		return *meta.MayCurate
	}
	if !mayCurate("admin", h.token) {
		t.Fatal("mayCurate = false for the administrator")
	}
	if !mayCurate("acquirer", digger) {
		t.Fatal("mayCurate = false for the acquirer whose edit landed")
	}
	if mayCurate("bystander", bystander) {
		t.Fatal("mayCurate = true for the bystander the edit refused")
	}

	// The permissions read is the same answer without the cost of the
	// full editor document, for surfaces that only decide on a door.
	perm := func(token string) bool {
		return decode[ItemPermissions](t, get(t, h.ts, "/api/v1/items/"+trackPid+"/permissions", token)).MayCurate
	}
	if !perm(h.token) || !perm(digger) || perm(bystander) {
		t.Fatal("the permissions read disagrees with the metadata read's mayCurate")
	}

	// A single video URL takes the non-playlist fallback.
	resp = post(digger, "/api/v1/acquisitions", map[string]any{
		"url": "https://tube.example/watch?v=lone", "mediaType": "music",
	})
	if resp.StatusCode != 202 {
		t.Fatalf("single acquisition status = %d", resp.StatusCode)
	}
	single := decode[ToolTask](t, resp)
	drainTools(t, h)
	drainMatches(t, h)
	got = decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+single.Id, digger))
	if got.State != "done" || got.ResultPids == nil || len(*got.ResultPids) != 1 {
		t.Fatalf("single acquire task = %+v", got)
	}
	lone := decode[ReviewEntryDetail](t, get(t, h.ts, "/api/v1/review/queue/"+(*got.ResultPids)[0], digger))
	if lone.TrackCount != 1 || lone.Tracks[0].Title != "Warehouse Set (Unreleased)" {
		t.Fatalf("single acquire entry = %+v", lone)
	}

	// Without any provider the endpoint answers the typed 501.
	bare := newHarnessDirect(t)
	resp = bare.postJSON(t, "/api/v1/acquisitions", map[string]any{
		"url": "https://tube.example/watch?v=x", "mediaType": "music",
	})
	if resp.StatusCode != 501 {
		t.Fatalf("no-provider status = %d, want 501", resp.StatusCode)
	}

	// A provider but no managed root answers 400 before spending a
	// download, naming the fix.
	noManaged := newHarnessWith(t, func(cfg *service.Config) {
		cfg.SourceProviders = append(cfg.SourceProviders, src)
		cfg.AllowPrivateFeedHosts = true
		// Roots stay in-place: no managed destination for music.
	})
	nmToken := noManaged.token
	nmBody, _ := json.Marshal(map[string]any{
		"url": "https://tube.example/watch?v=lone", "mediaType": "music",
	})
	nmReq, _ := http.NewRequest("POST", noManaged.ts.URL+"/api/v1/acquisitions", bytes.NewReader(nmBody))
	nmReq.Header.Set("Content-Type", "application/json")
	nmReq.Header.Set("Authorization", "Bearer "+nmToken)
	nmResp, err := http.DefaultClient.Do(nmReq)
	if err != nil {
		t.Fatal(err)
	}
	if nmResp.StatusCode != 400 {
		t.Fatalf("no-managed-root status = %d, want 400", nmResp.StatusCode)
	}
	var nmErr Error
	if err := json.NewDecoder(nmResp.Body).Decode(&nmErr); err != nil ||
		!strings.Contains(nmErr.Message, "managed") {
		t.Fatalf("no-managed-root error = %+v (%v)", nmErr, err)
	}
}

package service

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/enrich"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"
	waxlabel "github.com/colespringer/waxlabel"
	"github.com/colespringer/waxlabel/tag"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/providers"
)

const (
	approvedRelease = "6a1f4c2e-8b3d-4e5f-9a0b-1c2d3e4f5a6b"
	approvedGroup   = "7b2e5d3f-9c4e-4f60-8b1c-2d3e4f5a6b7c"
	approvedTrack   = "8c3f6e40-ad5f-4071-9c2d-3e4f5a6b7c8d"
	rematchRelease  = "9d4a7f51-be60-4182-ad3e-4f5a6b7c8d9e"
	rematchGroup    = "ae5b8062-cf71-4293-be4f-5a6b7c8d9eaf"
	fakeArchive     = "https://archive.test"
)

// fakeReleaseCovers answers the covers it holds, each call after delay
// unless the caller's deadline comes first, and counts what it was asked
// and how long the asking took. A cover it lacks is the archive's miss,
// or fail when set: the archive not answering.
type fakeReleaseCovers struct {
	front, group map[string][]byte
	delay        time.Duration
	fail         error

	mu    sync.Mutex
	asked []string
	spent time.Duration
}

func (f *fakeReleaseCovers) wait(ctx context.Context, what string) error {
	start := time.Now()
	defer func() {
		f.mu.Lock()
		f.asked = append(f.asked, what)
		f.spent += time.Since(start)
		f.mu.Unlock()
	}()
	if f.delay == 0 {
		return ctx.Err()
	}
	timer := time.NewTimer(f.delay)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return ctx.Err()
	case <-timer.C:
		return nil
	}
}

func (f *fakeReleaseCovers) FrontCover(ctx context.Context, mbid string) ([]byte, string, error) {
	if err := f.wait(ctx, "release/"+mbid); err != nil {
		return nil, "", err
	}
	if b, ok := f.front[mbid]; ok {
		return b, "image/png", nil
	}
	return nil, "", f.miss()
}

func (f *fakeReleaseCovers) GroupFrontCover(ctx context.Context, mbid string) ([]byte, string, error) {
	if err := f.wait(ctx, "release-group/"+mbid); err != nil {
		return nil, "", err
	}
	if b, ok := f.group[mbid]; ok {
		return b, "image/png", nil
	}
	return nil, "", f.miss()
}

func (f *fakeReleaseCovers) miss() error {
	if f.fail != nil {
		return f.fail
	}
	return providers.ErrNoCover
}

func (f *fakeReleaseCovers) FrontCoverURL(mbid string) string {
	return fakeArchive + "/release/" + mbid + "/front-500"
}

func (f *fakeReleaseCovers) GroupFrontCoverURL(mbid string) string {
	return fakeArchive + "/release-group/" + mbid + "/front-500"
}

func (f *fakeReleaseCovers) spentAsking() (time.Duration, []string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.spent, append([]string(nil), f.asked...)
}

// coverProvider is an injected cover provider answering every release.
type coverProvider struct{ data []byte }

func (coverProvider) Name() string                    { return "deezer" }
func (coverProvider) Capabilities() enrich.Capability { return enrich.CapCover }
func (p coverProvider) Enrich(_ context.Context, req enrich.Request) (*enrich.Candidate, error) {
	if req.Type != enrich.TargetRelease {
		return nil, nil
	}
	return &enrich.Candidate{Cover: &model.ArtImage{
		Data: p.data, Format: "png", Attribution: model.Attribution{SourceURL: "https://cdn.deezer.test/cover/1000x1000.png"},
	}}, nil
}

type approvalFixture struct {
	ctx    context.Context
	svc    *Library
	uc     *UserCtx
	it     *model.ItemView
	path   string
	root   string
	covers *fakeReleaseCovers
}

type approvalSetup struct {
	origin    model.SourceType // recorded as a download when not manual
	picture   []byte           // the file's front picture; none when nil
	covers    *fakeReleaseCovers
	providers []enrich.Provider
}

// openApprovalFixture is one scanned track under a server with a youtube
// source provider and the given release covers.
func openApprovalFixture(t *testing.T, s approvalSetup) approvalFixture {
	t.Helper()
	var root, path string
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.SourceProviders = []source.Provider{registeredSource{typ: model.SourceYouTube}}
		if s.covers != nil {
			c.ReleaseCovers = s.covers
		}
		c.EnrichmentProviders = s.providers
		root = c.Roots[0].Path
		paths, err := fixtures.Generate(root, fixtures.Spec{
			Name: "approved", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Approved Cut", "ARTIST": "Test Ensemble", "ALBUM": "Loose Album"},
		})
		if err != nil {
			t.Fatal(err)
		}
		path = paths[0]
		if s.picture != nil {
			replacePicture(t, path, s.picture)
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	_, pid := fixtureTrackPID(t, ctx, svc, uc, "Approved Cut")
	if s.origin != "" {
		if err := svc.lib.SetAcquisition(ctx, pid, model.AcquisitionInput{
			SourceType: s.origin, SourceURL: "https://www.youtube.test/watch?v=abc123",
		}, waxbin.AcquisitionEditOptions{Lock: model.LockOff}); err != nil {
			t.Fatal(err)
		}
		if s.origin != model.SourceManual {
			recordDownload(t, ctx, svc, pid, s.origin)
		}
	}
	it, err := svc.lib.Get(ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	return approvalFixture{ctx: ctx, svc: svc, uc: uc, it: it, path: path, root: root, covers: s.covers}
}

func approvedCandidate() reviewCandidateDoc {
	return reviewCandidateDoc{
		MBID: approvedRelease, ReleaseGroupMBID: approvedGroup,
		Title: "The Release", Artist: "The Release Artist", TrackCount: 1, SimilarityPct: 97,
		Pairings: []reviewPairingDoc{{TrackIndex: 0, Position: 1, Title: "Approved Cut", RecordingMBID: approvedTrack}},
	}
}

// pendingMatch opens a pending rematch entry over items, offering cand.
func pendingMatch(t *testing.T, ctx context.Context, svc *Library, cand reviewCandidateDoc, items ...*model.ItemView) wdb.ReviewEntry {
	t.Helper()
	payload := reviewPayload{Candidates: []reviewCandidateDoc{cand}}
	for _, it := range items {
		payload.Tracks = append(payload.Tracks, reviewTrackDoc{PID: string(it.PID), Path: string(it.Path), Title: it.Title})
	}
	raw, err := json.Marshal(payload)
	if err != nil {
		t.Fatal(err)
	}
	e := wdb.ReviewEntry{
		ID: newReviewID(), Kind: reviewKindMatch, Status: reviewPending, MediaType: "music",
		Origin: reviewOriginRematch, Title: cand.Title, TrackCount: len(items),
		BestMBID: cand.MBID, Payload: string(raw), CreatedAtNS: time.Now().UnixNano(),
	}
	if err := svc.db.InsertReviewEntry(ctx, e); err != nil {
		t.Fatal(err)
	}
	return e
}

func (f approvalFixture) approve(t *testing.T) (string, []string) {
	t.Helper()
	return f.approveAs(t, approvedCandidate())
}

func (f approvalFixture) approveAs(t *testing.T, cand reviewCandidateDoc) (string, []string) {
	t.Helper()
	e := pendingMatch(t, f.ctx, f.svc, cand, f.it)
	_, warnings, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e.ID, "approve", "", "", false)
	if err != nil {
		t.Fatalf("approve: %v", err)
	}
	return e.ID, warnings
}

func (f approvalFixture) front(t *testing.T) *model.ArtProvenance {
	t.Helper()
	prov, err := f.svc.lib.ArtProvenance(f.ctx, model.EntityRef{Type: model.ArtTrack, PID: f.it.PID}, model.ArtRoleFront)
	if err != nil {
		return nil
	}
	return prov
}

func (f approvalFixture) locked(t *testing.T) bool {
	t.Helper()
	locked, err := f.svc.lib.ArtLocked(f.ctx, model.ArtTrack, f.it.PID, model.ArtRoleFront)
	if err != nil {
		t.Fatal(err)
	}
	return locked
}

// filePicture is the front picture the file itself carries.
func filePicture(t *testing.T, path string) []byte {
	t.Helper()
	doc, err := waxlabel.ParseFile(context.Background(), path)
	if err != nil {
		t.Fatal(err)
	}
	for _, p := range doc.Pictures() {
		if p.Type == waxlabel.PicFrontCover {
			return p.Data
		}
	}
	return nil
}

func hasWarning(warnings []string, part string) bool {
	for _, w := range warnings {
		if strings.Contains(w, part) {
			return true
		}
	}
	return false
}

// An approval replaces a download's thumbnail with the release's front,
// attributed to the archive and keyed on the release, locked, and
// written into the file; the album records the release and its group.
func TestApprovalReplacesADownloadsThumbnailWithTheReleaseCover(t *testing.T) {
	t.Parallel()
	release := thumbnailPNG(t, 30)
	f := openApprovalFixture(t, approvalSetup{
		origin: model.SourceYouTube, picture: thumbnailPNG(t, 200),
		covers: &fakeReleaseCovers{front: map[string][]byte{approvedRelease: release}},
	})
	if got := rankOf(f.ctx, f.svc, f.it.PID); got != artRankDownload {
		t.Fatalf("the thumbnail ranks %d before the approval, want %d", got, artRankDownload)
	}
	_, warnings := f.approve(t)
	if hasWarning(warnings, "cover") {
		t.Errorf("warnings = %v, want none about the cover", warnings)
	}
	prov := f.front(t)
	if prov == nil || prov.Source != model.SourceEnrichment || prov.Provider != enrich.ProviderCoverArt ||
		prov.SourceURL != fakeArchive+"/release/"+approvedRelease+"/front-500" {
		t.Fatalf("front = %+v, want the archive's release front", prov)
	}
	if !f.locked(t) {
		t.Error("the approval's cover is not locked")
	}
	if got := artRank(prov, false, ""); got != artRankRelease {
		t.Errorf("the approval's cover ranks %d unlocked, want %d", got, artRankRelease)
	}
	if !bytes.Equal(filePicture(t, f.path), release) {
		t.Error("the file's picture is not the release's front")
	}
	it, err := f.svc.lib.Get(f.ctx, f.it.PID)
	if err != nil {
		t.Fatal(err)
	}
	if it.AlbumMBID != approvedRelease || it.ReleaseGroupMBID != approvedGroup {
		t.Errorf("album ids = %q / %q, want the release and its group", it.AlbumMBID, it.ReleaseGroupMBID)
	}
}

// With no release front the group's is taken, then a cover provider's.
func TestApprovalFallsBackToTheGroupThenAProvider(t *testing.T) {
	t.Parallel()
	t.Run("group", func(t *testing.T) {
		t.Parallel()
		f := openApprovalFixture(t, approvalSetup{
			origin: model.SourceYouTube, picture: thumbnailPNG(t, 200),
			covers: &fakeReleaseCovers{group: map[string][]byte{approvedGroup: thumbnailPNG(t, 70)}},
		})
		f.approve(t)
		prov := f.front(t)
		if prov == nil || prov.Provider != enrich.ProviderCoverArt ||
			prov.SourceURL != fakeArchive+"/release-group/"+approvedGroup+"/front-500" {
			t.Fatalf("front = %+v, want the archive's group front", prov)
		}
		if !f.locked(t) {
			t.Error("the group front is not locked")
		}
	})
	t.Run("provider", func(t *testing.T) {
		t.Parallel()
		f := openApprovalFixture(t, approvalSetup{
			origin: model.SourceYouTube, picture: thumbnailPNG(t, 200),
			covers:    &fakeReleaseCovers{},
			providers: []enrich.Provider{coverProvider{data: thumbnailPNG(t, 90)}},
		})
		f.approve(t)
		if prov := f.front(t); prov == nil || prov.Source != model.SourceEnrichment || prov.Provider != "deezer" {
			t.Fatalf("front = %+v, want the provider's", prov)
		}
	})
}

// A person's cover, a locked cover, and an upload's own art all stay.
func TestApprovalKeepsCoversItMayNotReplace(t *testing.T) {
	t.Parallel()
	covers := func() *fakeReleaseCovers {
		return &fakeReleaseCovers{front: map[string][]byte{approvedRelease: thumbnailPNG(t, 30)}}
	}
	for _, tc := range []struct {
		name  string
		setup approvalSetup
		prep  func(t *testing.T, f approvalFixture)
	}{
		{"a person's cover", approvalSetup{origin: model.SourceYouTube, picture: thumbnailPNG(t, 200)},
			func(t *testing.T, f approvalFixture) {
				if err := f.svc.lib.SetItemArt(f.ctx, f.it.PID, model.ArtRoleFront, thumbnailPNG(t, 120),
					waxbin.ArtEditOptions{Source: model.SourceUser, Lock: model.LockOff}); err != nil {
					t.Fatal(err)
				}
			}},
		{"a locked thumbnail", approvalSetup{origin: model.SourceYouTube, picture: thumbnailPNG(t, 200)},
			func(t *testing.T, f approvalFixture) {
				if _, err := f.svc.lib.SetArtLock(f.ctx, model.ArtTrack, f.it.PID, model.ArtRoleFront, true); err != nil {
					t.Fatal(err)
				}
			}},
		{"an upload's embedded art", approvalSetup{origin: model.SourceManual, picture: thumbnailPNG(t, 200)}, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			tc.setup.covers = covers()
			f := openApprovalFixture(t, tc.setup)
			if tc.prep != nil {
				tc.prep(t, f)
			}
			before := f.front(t)
			_, warnings := f.approve(t)
			after := f.front(t)
			if before == nil || after == nil || after.SourceHash != before.SourceHash || after.Source != before.Source {
				t.Fatalf("front %+v became %+v, want it kept", before, after)
			}
			if hasWarning(warnings, "cover") {
				t.Errorf("warnings = %v, want none: the cover was not the approval's to replace", warnings)
			}
			if _, asked := f.covers.spentAsking(); len(asked) != 0 {
				t.Errorf("the archive was asked %v for a cover nobody would take", asked)
			}
		})
	}
}

// A release no source has a cover for leaves the thumbnail, still the
// download's, and says so.
func TestApprovalMissLeavesTheThumbnailAndWarns(t *testing.T) {
	t.Parallel()
	f := openApprovalFixture(t, approvalSetup{
		origin: model.SourceYouTube, picture: thumbnailPNG(t, 200), covers: &fakeReleaseCovers{},
	})
	before := f.front(t)
	_, warnings := f.approve(t)
	if after := f.front(t); after == nil || after.SourceHash != before.SourceHash {
		t.Fatalf("front became %+v, want the thumbnail kept", after)
	}
	if got := rankOf(f.ctx, f.svc, f.it.PID); got != artRankDownload {
		t.Errorf("the kept thumbnail ranks %d, want %d (the download's, open to a later cover)", got, artRankDownload)
	}
	if f.locked(t) {
		t.Error("a missed cover locked the thumbnail")
	}
	if !hasWarning(warnings, "no cover found") {
		t.Errorf("warnings = %v, want the missing cover named", warnings)
	}
}

// Without the archive (matching off) an approval fetches no cover and
// says nothing about one.
func TestApprovalWithoutReleaseCoversLeavesArtAlone(t *testing.T) {
	t.Parallel()
	f := openApprovalFixture(t, approvalSetup{origin: model.SourceYouTube, picture: thumbnailPNG(t, 200)})
	before := f.front(t)
	_, warnings := f.approve(t)
	if after := f.front(t); after == nil || after.SourceHash != before.SourceHash {
		t.Fatalf("front became %+v, want it kept", after)
	}
	if hasWarning(warnings, "cover") {
		t.Errorf("warnings = %v, want none about a cover", warnings)
	}
}

// A revert puts the thumbnail back as it was, unlocked and the
// download's again, in the catalog and the file, forgets the release
// identity, and drops the kept bytes.
func TestRevertRestoresTheThumbnail(t *testing.T) {
	t.Parallel()
	thumb := thumbnailPNG(t, 200)
	f := openApprovalFixture(t, approvalSetup{
		origin: model.SourceYouTube, picture: thumb,
		covers: &fakeReleaseCovers{front: map[string][]byte{approvedRelease: thumbnailPNG(t, 30)}},
	})
	before := f.front(t)
	id, _ := f.approve(t)
	kept := filepath.Join(f.svc.Ingest.reviewCoverDir, id)
	if entries, err := os.ReadDir(kept); err != nil || len(entries) != 1 {
		t.Fatalf("kept fronts for the entry = %v (%v), want one", entries, err)
	}
	if _, err := f.svc.Ingest.RevertReviewEntry(f.ctx, f.uc, id); err != nil {
		t.Fatalf("revert: %v", err)
	}
	after := f.front(t)
	if after == nil || after.SourceHash != before.SourceHash || after.Source != model.SourceTag {
		t.Fatalf("front after the revert = %+v, want the thumbnail as it was (%+v)", after, before)
	}
	if f.locked(t) {
		t.Error("the restored thumbnail is locked")
	}
	if got := rankOf(f.ctx, f.svc, f.it.PID); got != artRankDownload {
		t.Errorf("the restored thumbnail ranks %d, want %d", got, artRankDownload)
	}
	if !bytes.Equal(filePicture(t, f.path), thumb) {
		t.Error("the file's picture is not the thumbnail again")
	}
	it, err := f.svc.lib.Get(f.ctx, f.it.PID)
	if err != nil {
		t.Fatal(err)
	}
	if it.AlbumMBID != "" || it.ReleaseGroupMBID != "" {
		t.Errorf("album ids after the revert = %q / %q, want none", it.AlbumMBID, it.ReleaseGroupMBID)
	}
	if _, err := os.Stat(kept); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the kept fronts outlived the revert: %v", err)
	}
}

// A cover the approval gave an item that had none goes with the revert.
func TestRevertRemovesACoverTheApprovalAdded(t *testing.T) {
	t.Parallel()
	f := openApprovalFixture(t, approvalSetup{
		covers: &fakeReleaseCovers{front: map[string][]byte{approvedRelease: thumbnailPNG(t, 30)}},
	})
	if f.front(t) != nil {
		t.Fatal("the fixture already has a cover")
	}
	id, _ := f.approve(t)
	if prov := f.front(t); prov == nil || prov.Provider != enrich.ProviderCoverArt {
		t.Fatalf("front after the approval = %+v, want the release's", prov)
	}
	if _, err := f.svc.Ingest.RevertReviewEntry(f.ctx, f.uc, id); err != nil {
		t.Fatalf("revert: %v", err)
	}
	if prov := f.front(t); prov != nil {
		t.Errorf("front after the revert = %+v, want none", prov)
	}
	if f.locked(t) {
		t.Error("the emptied slot is locked")
	}
	if filePicture(t, f.path) != nil {
		t.Error("the file still carries the approval's picture")
	}
}

// A matching library applying a match on its own takes the same path.
func TestAutoApplyAppliesTheReleaseCover(t *testing.T) {
	t.Parallel()
	f := openApprovalFixture(t, approvalSetup{
		origin: model.SourceYouTube, picture: thumbnailPNG(t, 200),
		covers: &fakeReleaseCovers{front: map[string][]byte{approvedRelease: thumbnailPNG(t, 30)}},
	})
	e := pendingMatch(t, f.ctx, f.svc, approvedCandidate(), f.it)
	var payload reviewPayload
	if err := json.Unmarshal([]byte(e.Payload), &payload); err != nil {
		t.Fatal(err)
	}
	f.svc.Ingest.autoApplyEntry(f.ctx, &e, &payload, e.BestMBID, false)
	if status, _ := decidedEntry(t, f.ctx, f.svc, e.ID); status != reviewAutoApplied {
		t.Fatalf("entry = %s, want auto-applied", status)
	}
	if prov := f.front(t); prov == nil || prov.Provider != enrich.ProviderCoverArt || !f.locked(t) {
		t.Fatalf("front = %+v, want the release's, locked", prov)
	}
}

// In a read-only library the cover reaches the catalog alone: the file
// keeps its picture, owing the new one, and the approval stands.
func TestApprovalInAReadOnlyLibraryKeepsTheFile(t *testing.T) {
	t.Parallel()
	thumb := thumbnailPNG(t, 200)
	f := openApprovalFixture(t, approvalSetup{
		origin: model.SourceYouTube, picture: thumb,
		covers: &fakeReleaseCovers{front: map[string][]byte{approvedRelease: thumbnailPNG(t, 30)}},
	})
	if err := f.svc.Settings.LibraryReadOnlySet(f.ctx, f.uc, libraryAt(t, f.ctx, f.svc, f.root).PID, true); err != nil {
		t.Fatal(err)
	}
	f.approve(t)
	if prov := f.front(t); prov == nil || prov.Provider != enrich.ProviderCoverArt || !f.locked(t) {
		t.Fatalf("front = %+v, want the release's in the catalog, locked", prov)
	}
	if !bytes.Equal(filePicture(t, f.path), thumb) {
		t.Error("a read-only library's file took the new picture")
	}
}

// A bulk approval's cover fetches share one time bound: the call
// returns inside it, and the entries it did not reach carry the warning
// and keep what they had.
func TestBulkApprovalStaysInsideItsCoverBudget(t *testing.T) {
	t.Parallel()
	const n = 20
	covers := &fakeReleaseCovers{delay: 3 * time.Second}
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.ReleaseCovers = covers
		for i := range n {
			if _, err := fixtures.Generate(c.Roots[0].Path, fixtures.Spec{
				Name: fmt.Sprintf("bulk%02d", i), Codec: fixtures.CodecFLAC, Duration: time.Second,
				Tags: map[string]string{"TITLE": fmt.Sprintf("Bulk Cut %02d", i), "ARTIST": "Bulk Ensemble"},
			}); err != nil {
				t.Fatal(err)
			}
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	var ids []string
	for i := range n {
		_, pid := fixtureTrackPID(t, ctx, svc, uc, fmt.Sprintf("Bulk Cut %02d", i))
		it, err := svc.lib.Get(ctx, pid)
		if err != nil {
			t.Fatal(err)
		}
		cand := approvedCandidate()
		cand.Pairings[0].Title = it.Title
		ids = append(ids, pendingMatch(t, ctx, svc, cand, it).ID)
	}
	start := time.Now()
	out := svc.Ingest.DecideReviewBulk(ctx, uc, ids, "approve")
	elapsed := time.Since(start)
	spent, asked := covers.spentAsking()
	t.Logf("the bulk call took %v, its cover fetches %v", elapsed, spent)
	if spent > bulkCoverBudget+500*time.Millisecond {
		t.Errorf("cover fetches took %v over %d asks, want inside the %v bound", spent, len(asked), bulkCoverBudget)
	}
	// Past the bound is the catalog work of 20 small decisions.
	if elapsed > bulkCoverBudget+bulkCatalogMargin {
		t.Errorf("the bulk call took %v, want inside %v and a small margin", elapsed, bulkCoverBudget)
	}
	unreached := 0
	for _, o := range out {
		if !o.OK {
			t.Fatalf("entry %s: %s %s", o.EntryID, o.Code, o.Error)
		}
		if hasWarning(o.Warnings, "in time") {
			unreached++
		}
	}
	if unreached < n-5 {
		t.Errorf("%d entries carry the out-of-time warning, want the %d the bound could not reach", unreached, n-5)
	}
	if last := out[n-1]; !hasWarning(last.Warnings, "in time") {
		t.Errorf("the last entry's warnings = %v, want the out-of-time warning", last.Warnings)
	}
}

// The approved album keeps its pid through a re-read: catalog-only ids,
// and ids written into the file by hand.
func TestApprovedReleaseIdentitySurvivesAReRead(t *testing.T) {
	t.Parallel()
	f := openApprovalFixture(t, approvalSetup{covers: &fakeReleaseCovers{}})
	f.approve(t)
	approved, err := f.svc.lib.Get(f.ctx, f.it.PID)
	if err != nil {
		t.Fatal(err)
	}
	if approved.AlbumMBID != approvedRelease || approved.AlbumPID == "" {
		t.Fatalf("approved album = %q (%s), want the release recorded", approved.AlbumMBID, approved.AlbumPID)
	}
	reread := func(when string) {
		t.Helper()
		if _, err := f.svc.lib.Scan(f.ctx, waxbin.ScanRequest{Force: true}); err != nil {
			t.Fatal(err)
		}
		// By title: the item itself is the catalog's to key, and a file
		// carrying a recording id is keyed by it.
		_, pid := fixtureTrackPID(t, f.ctx, f.svc, f.uc, "Approved Cut")
		it, err := f.svc.lib.Get(f.ctx, pid)
		if err != nil {
			t.Fatal(err)
		}
		t.Logf("%s: item %s (was %s), album %s (%q), group %s (%q)", when, it.PID, f.it.PID,
			it.AlbumPID, it.AlbumMBID, it.ReleaseGroupPID, it.ReleaseGroupMBID)
		if it.AlbumPID != approved.AlbumPID {
			t.Errorf("%s: album pid %s, want %s kept", when, it.AlbumPID, approved.AlbumPID)
		}
		if it.AlbumMBID != approvedRelease {
			t.Errorf("%s: album id %q, want the release's", when, it.AlbumMBID)
		}
	}
	reread("catalog-only ids, forced re-read")
	doc, err := waxlabel.ParseFile(context.Background(), f.path)
	if err != nil {
		t.Fatal(err)
	}
	ed := doc.Edit().Set(tag.MBReleaseID, approvedRelease).Set(tag.MBReleaseGroupID, approvedGroup)
	plan, err := ed.Prepare()
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := plan.Execute(context.Background(), waxlabel.SaveBack()); err != nil {
		t.Fatal(err)
	}
	reread("ids in the file, re-read")
}

// Kept fronts outlive no entry that could restore them: an open sweeps
// those of entries that are no longer applied.
func TestKeptFrontsOfSettledEntriesAreSwept(t *testing.T) {
	t.Parallel()
	f := openApprovalFixture(t, approvalSetup{
		origin: model.SourceYouTube, picture: thumbnailPNG(t, 200),
		covers: &fakeReleaseCovers{front: map[string][]byte{approvedRelease: thumbnailPNG(t, 30)}},
	})
	id, _ := f.approve(t)
	orphan := filepath.Join(f.svc.Ingest.reviewCoverDir, "rv-gone")
	if err := os.MkdirAll(orphan, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(orphan, "x"), []byte("old"), 0o644); err != nil {
		t.Fatal(err)
	}
	f.svc.Ingest.sweepReviewCovers(f.ctx)
	if _, err := os.Stat(orphan); !errors.Is(err, os.ErrNotExist) {
		t.Errorf("the orphan's kept front survived the sweep: %v", err)
	}
	if _, err := os.Stat(filepath.Join(f.svc.Ingest.reviewCoverDir, id)); err != nil {
		t.Errorf("an applied entry's kept front was swept: %v", err)
	}
}

// bulkCatalogMargin is the time a test's bulk call may take past the
// cover bound: the catalog work of its decisions.
const bulkCatalogMargin = 4 * time.Second

const priorRelease = "1f2e3d4c-5b6a-4789-8a7b-6c5d4e3f2a1b"

// approvalTrack is one file of a multi-track fixture; other places it in
// a second library.
type approvalTrack struct {
	title, album string
	other        bool
}

type tracksFixture struct {
	ctx   context.Context
	svc   *Library
	uc    *UserCtx
	items []*model.ItemView
	paths []string
	other string
}

// openApprovalTracks scans tracks, in order, under the given release
// covers.
func openApprovalTracks(t *testing.T, covers *fakeReleaseCovers, tracks ...approvalTrack) tracksFixture {
	t.Helper()
	var f tracksFixture
	f.ctx, f.svc, f.uc = openEnrichFixture(t, func(c *Config) {
		if covers != nil {
			c.ReleaseCovers = covers
		}
		f.other = t.TempDir()
		c.Roots = append(c.Roots, Root{Name: "other", Path: f.other})
		for i, tr := range tracks {
			dir := c.Roots[0].Path
			if tr.other {
				dir = f.other
			}
			paths, err := fixtures.Generate(dir, fixtures.Spec{
				Name: fmt.Sprintf("cut%02d", i), Codec: fixtures.CodecFLAC, Duration: time.Second,
				Tags: map[string]string{"TITLE": tr.title, "ARTIST": "Test Ensemble", "ALBUM": tr.album},
			})
			if err != nil {
				t.Fatal(err)
			}
			f.paths = append(f.paths, paths[0])
		}
	})
	if _, err := f.svc.lib.Scan(f.ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	for _, tr := range tracks {
		_, pid := fixtureTrackPID(t, f.ctx, f.svc, f.uc, tr.title)
		it, err := f.svc.lib.Get(f.ctx, pid)
		if err != nil {
			t.Fatal(err)
		}
		f.items = append(f.items, it)
	}
	return f
}

func (f tracksFixture) front(t *testing.T, i int) *model.ArtProvenance {
	t.Helper()
	prov, err := f.svc.lib.ArtProvenance(f.ctx, model.EntityRef{Type: model.ArtTrack, PID: f.items[i].PID}, model.ArtRoleFront)
	if err != nil {
		return nil
	}
	return prov
}

func (f tracksFixture) item(t *testing.T, i int) *model.ItemView {
	t.Helper()
	it, err := f.svc.lib.Get(f.ctx, f.items[i].PID)
	if err != nil {
		t.Fatal(err)
	}
	return it
}

// candidateOver is a release whose tracks pair with titles in order.
func candidateOver(release, group string, titles ...string) reviewCandidateDoc {
	c := approvedCandidate()
	c.MBID, c.ReleaseGroupMBID, c.TrackCount, c.Pairings = release, group, len(titles), nil
	for i, title := range titles {
		c.Pairings = append(c.Pairings, reviewPairingDoc{TrackIndex: i, Position: i + 1, Title: title})
	}
	return c
}

func mbidCuration(t *testing.T, ctx context.Context, svc *Library, et model.MergeEntity, pid model.PID) *model.EntityCuration {
	t.Helper()
	rows, err := svc.lib.EntityCuration(ctx, et, pid)
	if err != nil {
		t.Fatal(err)
	}
	for i := range rows {
		if rows[i].Field == "mbid" {
			return &rows[i]
		}
	}
	return nil
}

// The bound is on the cover fetches alone: catalog work, however slow,
// spends none of it, so quick covers reach every entry of a bulk call.
func TestBulkApprovalChargesItsBoundOnlyWithCoverFetches(t *testing.T) {
	t.Parallel()
	const n = 4
	// A release each, so no entry's album answers with another's cover.
	covers := &fakeReleaseCovers{front: map[string][]byte{}}
	var tracks []approvalTrack
	var cands []reviewCandidateDoc
	for i := range n {
		title := fmt.Sprintf("Slow Cut %02d", i)
		tracks = append(tracks, approvalTrack{title: title, album: fmt.Sprintf("Slow Album %02d", i)})
		c := candidateOver(fmt.Sprintf("6a1f4c2e-8b3d-4e5f-9a0b-1c2d3e4f5a%02d", i), approvedGroup, title)
		c.Title = fmt.Sprintf("The Release %02d", i)
		covers.front[c.MBID] = thumbnailPNG(t, uint8(30+i))
		cands = append(cands, c)
	}
	f := openApprovalTracks(t, covers, tracks...)
	// Each decision's catalog work takes a third of the whole bound.
	f.svc.Ingest.editFieldsHook = func(ctx context.Context, edits []model.ItemFieldEdit, opts waxbin.EditOptions) (*waxbin.BatchEditResult, error) {
		time.Sleep(bulkCoverBudget / 3)
		return f.svc.lib.EditItemsFields(ctx, edits, opts)
	}
	var ids []string
	for i, it := range f.items {
		ids = append(ids, pendingMatch(t, f.ctx, f.svc, cands[i], it).ID)
	}
	out := f.svc.Ingest.DecideReviewBulk(f.ctx, f.uc, ids, "approve")
	for i, o := range out {
		if !o.OK {
			t.Fatalf("entry %d: %s %s", i, o.Code, o.Error)
		}
		if hasWarning(o.Warnings, "cover") {
			t.Errorf("entry %d warnings = %v, want its cover fetched", i, o.Warnings)
		}
		if prov := f.front(t, i); prov == nil || prov.Level != model.ArtTrack || prov.Provider != enrich.ProviderCoverArt {
			t.Errorf("entry %d front = %+v, want the release's own", i, prov)
		}
	}
}

// A rematch approving another release takes over what the first approval
// recorded: the album's release ids, and the cover the first approval
// wrote and locked. A cover a person chose since is kept. A revert of the
// rematch puts the first approval's back as it stood.
func TestARematchApprovalTakesTheNewRelease(t *testing.T) {
	t.Parallel()
	first, second := thumbnailPNG(t, 30), thumbnailPNG(t, 60)
	setup := func(t *testing.T) approvalFixture {
		return openApprovalFixture(t, approvalSetup{
			origin: model.SourceYouTube, picture: thumbnailPNG(t, 200),
			covers: &fakeReleaseCovers{front: map[string][]byte{approvedRelease: first, rematchRelease: second}},
		})
	}
	rematch := approvedCandidate()
	rematch.MBID, rematch.ReleaseGroupMBID = rematchRelease, rematchGroup
	t.Run("the new release", func(t *testing.T) {
		t.Parallel()
		f := setup(t)
		f.approve(t)
		firstFront := f.front(t)
		id, warnings := f.approveAs(t, rematch)
		if len(warnings) != 0 {
			t.Errorf("warnings = %v, want none", warnings)
		}
		it, err := f.svc.lib.Get(f.ctx, f.it.PID)
		if err != nil {
			t.Fatal(err)
		}
		if it.AlbumMBID != rematchRelease || it.ReleaseGroupMBID != rematchGroup {
			t.Errorf("album ids = %q / %q, want the rematched release and its group", it.AlbumMBID, it.ReleaseGroupMBID)
		}
		if prov := f.front(t); prov == nil || prov.SourceURL != fakeArchive+"/release/"+rematchRelease+"/front-500" {
			t.Fatalf("front = %+v, want the rematched release's", prov)
		}
		if !f.locked(t) {
			t.Error("the rematched release's cover is not locked")
		}
		if !bytes.Equal(filePicture(t, f.path), second) {
			t.Error("the file's picture is not the rematched release's")
		}
		if _, err := f.svc.Ingest.RevertReviewEntry(f.ctx, f.uc, id); err != nil {
			t.Fatalf("revert: %v", err)
		}
		if prov := f.front(t); prov == nil || prov.SourceHash != firstFront.SourceHash || !f.locked(t) {
			t.Errorf("front after the revert = %+v (locked %v), want the first approval's, locked", prov, f.locked(t))
		}
		if it, err = f.svc.lib.Get(f.ctx, f.it.PID); err != nil {
			t.Fatal(err)
		}
		if it.AlbumMBID != approvedRelease {
			t.Errorf("album id after the revert = %q, want the first approval's", it.AlbumMBID)
		}
		// The restored cover is the first approval's again: a later
		// approval may still replace it.
		f.approveAs(t, rematch)
		if prov := f.front(t); prov == nil || prov.SourceURL != fakeArchive+"/release/"+rematchRelease+"/front-500" {
			t.Errorf("front after approving again = %+v, want the rematched release's", prov)
		}
	})
	t.Run("a person's cover in between", func(t *testing.T) {
		t.Parallel()
		f := setup(t)
		f.approve(t)
		// The person picks another cover and pins it.
		if err := f.svc.lib.SetItemArt(f.ctx, f.it.PID, model.ArtRoleFront, thumbnailPNG(t, 120), waxbin.ArtEditOptions{
			Source: model.SourceEnrichment, Provider: "deezer", Lock: model.LockOn, Force: true,
		}); err != nil {
			t.Fatal(err)
		}
		before := f.front(t)
		_, warnings := f.approveAs(t, rematch)
		if after := f.front(t); after == nil || after.SourceHash != before.SourceHash {
			t.Fatalf("front %+v became %+v, want the person's kept", before, after)
		}
		if hasWarning(warnings, "cover") {
			t.Errorf("warnings = %v, want none about the cover", warnings)
		}
		it, err := f.svc.lib.Get(f.ctx, f.it.PID)
		if err != nil {
			t.Fatal(err)
		}
		if it.AlbumMBID != rematchRelease {
			t.Errorf("album id = %q, want the rematched release", it.AlbumMBID)
		}
	})
}

// An item keeping a provider's cover lost nothing when the release has
// none: only an item left with a thumbnail or nothing is warned about.
func TestApprovalWarnsOnlyWhereNoBetterCoverStands(t *testing.T) {
	t.Parallel()
	f := openApprovalFixture(t, approvalSetup{covers: &fakeReleaseCovers{}})
	if err := f.svc.lib.SetItemArt(f.ctx, f.it.PID, model.ArtRoleFront, thumbnailPNG(t, 90), waxbin.ArtEditOptions{
		Source: model.SourceEnrichment, Provider: "deezer", SourceURL: "https://cdn.deezer.test/cover/1.png", Lock: model.LockOff,
	}); err != nil {
		t.Fatal(err)
	}
	if got := rankOf(f.ctx, f.svc, f.it.PID); got != artRankGroup {
		t.Fatalf("the provider's cover ranks %d, want %d", got, artRankGroup)
	}
	_, warnings := f.approve(t)
	if hasWarning(warnings, "cover") {
		t.Errorf("warnings = %v, want none: the item keeps a provider's cover", warnings)
	}
	if _, asked := f.covers.spentAsking(); len(asked) != 1 {
		t.Errorf("the archive was asked %v, want the release front alone", asked)
	}
}

// An archive that does not answer is not a release without a cover.
func TestApprovalSaysTheArchiveDidNotAnswer(t *testing.T) {
	t.Parallel()
	f := openApprovalFixture(t, approvalSetup{
		origin: model.SourceYouTube, picture: thumbnailPNG(t, 200),
		covers: &fakeReleaseCovers{fail: errors.New("archive: 503 Service Unavailable")},
	})
	_, warnings := f.approve(t)
	if !hasWarning(warnings, "the cover could not be fetched") || hasWarning(warnings, "no cover found") {
		t.Errorf("warnings = %v, want the cover named as not fetched", warnings)
	}
}

// A revert gives the album back the release id it had, attributed as it
// was; and leaves the album's ids alone once other items share it.
func TestRevertRestoresTheAlbumsIdsAsTheyWere(t *testing.T) {
	t.Parallel()
	t.Run("as attributed", func(t *testing.T) {
		t.Parallel()
		f := openApprovalFixture(t, approvalSetup{covers: &fakeReleaseCovers{}})
		if _, err := f.svc.lib.EditEntity(f.ctx, model.MergeAlbum, f.it.AlbumPID, map[string]string{"mbid": priorRelease},
			waxbin.EntityEditOptions{Source: model.SourceEnrichment, Provider: enrich.ProviderMusicBrainz, Lock: model.LockOff}); err != nil {
			t.Fatal(err)
		}
		id, _ := f.approve(t)
		approved, err := f.svc.lib.Get(f.ctx, f.it.PID)
		if err != nil {
			t.Fatal(err)
		}
		if approved.AlbumMBID != approvedRelease {
			t.Fatalf("approved album id = %q, want the release", approved.AlbumMBID)
		}
		if _, err := f.svc.Ingest.RevertReviewEntry(f.ctx, f.uc, id); err != nil {
			t.Fatalf("revert: %v", err)
		}
		row := mbidCuration(t, f.ctx, f.svc, model.MergeAlbum, approved.AlbumPID)
		if row == nil || row.Value != priorRelease || row.Source != model.SourceEnrichment ||
			row.Provider != enrich.ProviderMusicBrainz || row.Locked {
			t.Errorf("album id after the revert = %+v, want %s from musicbrainz, unlocked", row, priorRelease)
		}
	})
	t.Run("shared since", func(t *testing.T) {
		t.Parallel()
		f := openApprovalTracks(t, &fakeReleaseCovers{},
			approvalTrack{title: "First Cut", album: "First Album"}, approvalTrack{title: "Second Cut", album: "Second Album"})
		e1 := pendingMatch(t, f.ctx, f.svc, candidateOver(approvedRelease, approvedGroup, "First Cut"), f.items[0])
		if _, _, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e1.ID, "approve", "", "", false); err != nil {
			t.Fatal(err)
		}
		e2 := pendingMatch(t, f.ctx, f.svc, candidateOver(approvedRelease, approvedGroup, "Second Cut"), f.items[1])
		if _, _, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e2.ID, "approve", "", "", false); err != nil {
			t.Fatal(err)
		}
		a, b := f.item(t, 0), f.item(t, 1)
		if a.AlbumPID != b.AlbumPID || b.AlbumMBID != approvedRelease {
			t.Fatalf("approved albums = %s / %s (%q), want one album recording the release", a.AlbumPID, b.AlbumPID, b.AlbumMBID)
		}
		if _, err := f.svc.Ingest.RevertReviewEntry(f.ctx, f.uc, e1.ID); err != nil {
			t.Fatalf("revert: %v", err)
		}
		if b = f.item(t, 1); b.AlbumMBID != approvedRelease || b.ReleaseGroupMBID != approvedGroup {
			t.Errorf("the second entry's album ids = %q / %q after the first's revert, want the release kept", b.AlbumMBID, b.ReleaseGroupMBID)
		}
	})
}

// A release another album already holds is not recorded on this one, and
// the decision says so once, naming the album.
func TestApprovalNamesAReleaseAnotherAlbumHolds(t *testing.T) {
	t.Parallel()
	f := openApprovalTracks(t, &fakeReleaseCovers{},
		approvalTrack{title: "Held Cut", album: "Held Album"}, approvalTrack{title: "New Cut", album: "New Album"},
		approvalTrack{title: "Newer Cut", album: "Newer Album", other: true})
	if _, err := f.svc.lib.EditEntity(f.ctx, model.MergeAlbum, f.items[0].AlbumPID, map[string]string{"mbid": approvedRelease},
		waxbin.EntityEditOptions{Lock: model.LockOn}); err != nil {
		t.Fatal(err)
	}
	e := pendingMatch(t, f.ctx, f.svc, candidateOver(approvedRelease, approvedGroup, "New Cut", "Newer Cut"), f.items[1], f.items[2])
	_, warnings, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e.ID, "approve", "", "", false)
	if err != nil {
		t.Fatal(err)
	}
	var held []string
	for _, w := range warnings {
		if strings.Contains(w, "another album") {
			held = append(held, w)
		}
	}
	if len(held) != 1 || !strings.HasPrefix(held[0], "The Release: ") {
		t.Errorf("warnings = %v, want the release another album holds named once, by the album", warnings)
	}
	for i := 1; i < 3; i++ {
		if got := f.item(t, i).AlbumMBID; got != "" {
			t.Errorf("item %d's album id = %q, want none", i, got)
		}
	}
}

// A person who pins an approval's cover makes it theirs: a later
// approval keeps it.
func TestAPersonsPinKeepsAnApprovalsCover(t *testing.T) {
	t.Parallel()
	f := openApprovalFixture(t, approvalSetup{
		origin: model.SourceYouTube, picture: thumbnailPNG(t, 200),
		covers: &fakeReleaseCovers{front: map[string][]byte{approvedRelease: thumbnailPNG(t, 30), rematchRelease: thumbnailPNG(t, 60)}},
	})
	f.approve(t)
	before := f.front(t)
	item := apiPID(PrefixTrack, f.it.PID)
	for _, lock := range []bool{false, true} {
		if _, err := f.svc.Editor.SetItemLocks(f.ctx, f.uc, item, []string{"art"}, lock); err != nil {
			t.Fatal(err)
		}
	}
	rematch := approvedCandidate()
	rematch.MBID, rematch.ReleaseGroupMBID = rematchRelease, rematchGroup
	_, warnings := f.approveAs(t, rematch)
	if after := f.front(t); after == nil || after.SourceHash != before.SourceHash || !f.locked(t) {
		t.Fatalf("front %+v became %+v, want the pinned cover kept", before, after)
	}
	if hasWarning(warnings, "cover") {
		t.Errorf("warnings = %v, want none about the cover", warnings)
	}
}

// In a unit one of whose files sits in a read-only library, that file
// keeps its picture and is named; the other takes the release's cover.
func TestApprovalNamesTheReadOnlyFileItsCoverMissed(t *testing.T) {
	t.Parallel()
	release := thumbnailPNG(t, 30)
	f := openApprovalTracks(t, &fakeReleaseCovers{front: map[string][]byte{approvedRelease: release}},
		approvalTrack{title: "Open Cut", album: "Split Album"}, approvalTrack{title: "Shut Cut", album: "Split Album", other: true})
	if err := f.svc.Settings.LibraryReadOnlySet(f.ctx, f.uc, libraryAt(t, f.ctx, f.svc, f.other).PID, true); err != nil {
		t.Fatal(err)
	}
	e := pendingMatch(t, f.ctx, f.svc, candidateOver(approvedRelease, approvedGroup, "Open Cut", "Shut Cut"), f.items...)
	_, warnings, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e.ID, "approve", "", "", false)
	if err != nil {
		t.Fatal(err)
	}
	open, shut := filepath.Base(f.paths[0]), filepath.Base(f.paths[1])
	if !hasWarning(warnings, shut+": cover not written") {
		t.Errorf("warnings = %v, want %s named as not taking the cover", warnings, shut)
	}
	if hasWarning(warnings, open+": cover") {
		t.Errorf("warnings = %v, want nothing about %s's cover", warnings, open)
	}
	if !bytes.Equal(filePicture(t, f.paths[0]), release) {
		t.Errorf("%s's picture is not the release's", open)
	}
	if filePicture(t, f.paths[1]) != nil {
		t.Errorf("%s took a picture in a read-only library", shut)
	}
	for i := range f.items {
		if prov := f.front(t, i); prov == nil || prov.Provider != enrich.ProviderCoverArt {
			t.Errorf("item %d front = %+v, want the release's in the catalog", i, prov)
		}
	}
}

// A front the approval cannot read is not taken for none: the item keeps
// it, unreplaced, so a revert never deletes it.
func TestApprovalKeepsAFrontItCannotRead(t *testing.T) {
	t.Parallel()
	thumb := thumbnailPNG(t, 200)
	f := openApprovalFixture(t, approvalSetup{
		origin: model.SourceYouTube, picture: thumb,
		covers: &fakeReleaseCovers{front: map[string][]byte{approvedRelease: thumbnailPNG(t, 30)}},
	})
	f.svc.Ingest.resolveArtHook = func(context.Context, model.EntityRef, model.ArtRole, int) (*model.ArtBlob, error) {
		return nil, errors.New("the art store is unreadable")
	}
	before := f.front(t)
	_, warnings := f.approve(t)
	if after := f.front(t); after == nil || after.SourceHash != before.SourceHash {
		t.Errorf("front became %+v, want the thumbnail kept", after)
	}
	if !bytes.Equal(filePicture(t, f.path), thumb) {
		t.Error("the file's picture was replaced")
	}
	if !hasWarning(warnings, "could not be kept for a revert") {
		t.Errorf("warnings = %v, want the unkept cover named", warnings)
	}
}

// A front the approval cannot keep for a revert is not replaced.
func TestApprovalKeepsAFrontItCannotKeepForARevert(t *testing.T) {
	t.Parallel()
	thumb := thumbnailPNG(t, 200)
	f := openApprovalFixture(t, approvalSetup{
		origin: model.SourceYouTube, picture: thumb,
		covers: &fakeReleaseCovers{front: map[string][]byte{approvedRelease: thumbnailPNG(t, 30)}},
	})
	// A file where the kept fronts' directory belongs.
	blocked := filepath.Join(t.TempDir(), "covers")
	if err := os.WriteFile(blocked, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	f.svc.Ingest.reviewCoverDir = blocked
	before := f.front(t)
	_, warnings := f.approve(t)
	if after := f.front(t); after == nil || after.SourceHash != before.SourceHash {
		t.Errorf("front became %+v, want the thumbnail kept", after)
	}
	if !bytes.Equal(filePicture(t, f.path), thumb) {
		t.Error("the file's picture was replaced")
	}
	if !hasWarning(warnings, "could not be kept for a revert") {
		t.Errorf("warnings = %v, want the unkept cover named", warnings)
	}
}

// An approval records its release only on an album its items hold alone:
// a second edition approved into the album the first's track shares
// leaves the first's ids standing.
func TestApprovalRecordsTheReleaseOnlyOnAnAlbumItHoldsAlone(t *testing.T) {
	t.Parallel()
	f := openApprovalTracks(t, &fakeReleaseCovers{},
		approvalTrack{title: "First Cut", album: "First Edition"}, approvalTrack{title: "Second Cut", album: "Second Edition"})
	e1 := pendingMatch(t, f.ctx, f.svc, candidateOver(approvedRelease, approvedGroup, "First Cut"), f.items[0])
	if _, _, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e1.ID, "approve", "", "", false); err != nil {
		t.Fatal(err)
	}
	if a := f.item(t, 0); a.AlbumMBID != approvedRelease || a.ReleaseGroupMBID != approvedGroup {
		t.Fatalf("the first album's ids = %q / %q, want the release it holds alone recorded", a.AlbumMBID, a.ReleaseGroupMBID)
	}
	e2 := pendingMatch(t, f.ctx, f.svc, candidateOver(rematchRelease, rematchGroup, "Second Cut"), f.items[1])
	if _, _, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e2.ID, "approve", "", "", false); err != nil {
		t.Fatal(err)
	}
	a, b := f.item(t, 0), f.item(t, 1)
	if a.AlbumPID != b.AlbumPID {
		t.Fatalf("albums = %s / %s, want the two editions in one album", a.AlbumPID, b.AlbumPID)
	}
	if b.AlbumMBID != approvedRelease || b.ReleaseGroupMBID != approvedGroup {
		t.Errorf("the shared album's ids = %q / %q, want the first approval's kept", b.AlbumMBID, b.ReleaseGroupMBID)
	}
}

// A revert leaves an album's id alone once a person has set another since.
func TestRevertKeepsAnAlbumIdAPersonSetSince(t *testing.T) {
	t.Parallel()
	f := openApprovalFixture(t, approvalSetup{covers: &fakeReleaseCovers{}})
	id, _ := f.approve(t)
	approved, err := f.svc.lib.Get(f.ctx, f.it.PID)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.lib.EditEntity(f.ctx, model.MergeAlbum, approved.AlbumPID, map[string]string{"mbid": priorRelease},
		waxbin.EntityEditOptions{Source: model.SourceUser, Lock: model.LockOn, Force: true}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.svc.Ingest.RevertReviewEntry(f.ctx, f.uc, id); err != nil {
		t.Fatalf("revert: %v", err)
	}
	row := mbidCuration(t, f.ctx, f.svc, model.MergeAlbum, approved.AlbumPID)
	if row == nil || row.Value != priorRelease || row.Source != model.SourceUser || !row.Locked {
		t.Errorf("album id after the revert = %+v, want the person's %s, locked", row, priorRelease)
	}
}

// An apply whose last write failed leaves what it replaced on the entry:
// its retry, a restart in between, still reverts to what stood before the
// first attempt, fields, album id and cover alike.
func TestARetryAfterAFailedApplyRevertsToTheFirstBefore(t *testing.T) {
	t.Parallel()
	thumb := thumbnailPNG(t, 200)
	f := openApprovalFixture(t, approvalSetup{
		origin: model.SourceYouTube, picture: thumb,
		covers: &fakeReleaseCovers{front: map[string][]byte{approvedRelease: thumbnailPNG(t, 30)}},
	})
	if _, err := f.svc.lib.EditEntity(f.ctx, model.MergeAlbum, f.it.AlbumPID, map[string]string{"mbid": priorRelease},
		waxbin.EntityEditOptions{Source: model.SourceEnrichment, Provider: enrich.ProviderMusicBrainz, Lock: model.LockOff}); err != nil {
		t.Fatal(err)
	}
	beforeFront := f.front(t)
	e := pendingMatch(t, f.ctx, f.svc, approvedCandidate(), f.it)
	var fail atomic.Bool
	fail.Store(true)
	f.svc.Ingest.appliedWriteHook = func() error {
		if fail.Load() {
			return errors.New("the database is full")
		}
		return nil
	}
	if _, _, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e.ID, "approve", "", "", false); err == nil {
		t.Fatal("the approval succeeded, want its last write to fail")
	}
	// A restart in between sweeps the kept fronts no revert can reach.
	f.svc.Ingest.sweepReviewCovers(f.ctx)
	if kept, err := os.ReadDir(filepath.Join(f.svc.Ingest.reviewCoverDir, e.ID)); err != nil || len(kept) != 1 {
		t.Fatalf("kept fronts after the restart = %v (%v), want the thumbnail kept", kept, err)
	}
	fail.Store(false)
	if _, _, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e.ID, "approve", "", "", false); err != nil {
		t.Fatalf("retry: %v", err)
	}
	if _, err := f.svc.Ingest.RevertReviewEntry(f.ctx, f.uc, e.ID); err != nil {
		t.Fatalf("revert: %v", err)
	}
	it, err := f.svc.lib.Get(f.ctx, f.it.PID)
	if err != nil {
		t.Fatal(err)
	}
	if it.Album != f.it.Album || it.Artist != f.it.Artist || it.AlbumArtist != f.it.AlbumArtist || it.MBID != f.it.MBID {
		t.Errorf("fields after the revert = %q / %q / %q / %q, want %q / %q / %q / %q", it.Album, it.Artist, it.AlbumArtist, it.MBID,
			f.it.Album, f.it.Artist, f.it.AlbumArtist, f.it.MBID)
	}
	row := mbidCuration(t, f.ctx, f.svc, model.MergeAlbum, it.AlbumPID)
	if row == nil || row.Value != priorRelease || row.Source != model.SourceEnrichment || row.Locked {
		t.Errorf("album id after the revert = %+v, want %s from musicbrainz, unlocked", row, priorRelease)
	}
	if after := f.front(t); after == nil || after.SourceHash != beforeFront.SourceHash || after.Source != model.SourceTag {
		t.Errorf("front after the revert = %+v, want the thumbnail as it was (%+v)", after, beforeFront)
	}
	if !bytes.Equal(filePicture(t, f.path), thumb) {
		t.Error("the file's picture is not the thumbnail again")
	}
}

// An entry whose apply failed part way, then decided as it is, first
// takes back what that attempt wrote: fields, album id and cover read as
// before it.
func TestAnAsIsDecisionUndoesAFailedApply(t *testing.T) {
	t.Parallel()
	thumb := thumbnailPNG(t, 200)
	f := openApprovalFixture(t, approvalSetup{
		origin: model.SourceYouTube, picture: thumb,
		covers: &fakeReleaseCovers{front: map[string][]byte{approvedRelease: thumbnailPNG(t, 30)}},
	})
	if _, err := f.svc.lib.EditEntity(f.ctx, model.MergeAlbum, f.it.AlbumPID, map[string]string{"mbid": priorRelease},
		waxbin.EntityEditOptions{Source: model.SourceEnrichment, Provider: enrich.ProviderMusicBrainz, Lock: model.LockOff}); err != nil {
		t.Fatal(err)
	}
	beforeFront := f.front(t)
	e := pendingMatch(t, f.ctx, f.svc, approvedCandidate(), f.it)
	f.svc.Ingest.appliedWriteHook = func() error { return errors.New("the database is full") }
	if _, _, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e.ID, "approve", "", "", false); err == nil {
		t.Fatal("the approval succeeded, want its last write to fail")
	}
	if _, _, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e.ID, "as-is", "", "", false); err != nil {
		t.Fatalf("as-is: %v", err)
	}
	it, err := f.svc.lib.Get(f.ctx, f.it.PID)
	if err != nil {
		t.Fatal(err)
	}
	if it.Album != f.it.Album || it.Artist != f.it.Artist || it.AlbumArtist != f.it.AlbumArtist || it.MBID != f.it.MBID {
		t.Errorf("fields after as-is = %q / %q / %q / %q, want %q / %q / %q / %q", it.Album, it.Artist, it.AlbumArtist, it.MBID,
			f.it.Album, f.it.Artist, f.it.AlbumArtist, f.it.MBID)
	}
	row := mbidCuration(t, f.ctx, f.svc, model.MergeAlbum, it.AlbumPID)
	if row == nil || row.Value != priorRelease || row.Source != model.SourceEnrichment || row.Locked {
		t.Errorf("album id after as-is = %+v, want %s from musicbrainz, unlocked", row, priorRelease)
	}
	if after := f.front(t); after == nil || after.SourceHash != beforeFront.SourceHash || after.Source != model.SourceTag {
		t.Errorf("front after as-is = %+v, want the thumbnail as it was (%+v)", after, beforeFront)
	}
	if !bytes.Equal(filePicture(t, f.path), thumb) {
		t.Error("the file's picture is not the thumbnail again")
	}
	if status, _ := decidedEntry(t, f.ctx, f.svc, e.ID); status != reviewAsIs {
		t.Errorf("status = %s, want %s", status, reviewAsIs)
	}
}

// A person's edit since the failed attempt stands through the undo.
func TestASkipAfterAFailedApplyKeepsAPersonsEdit(t *testing.T) {
	t.Parallel()
	f := openApprovalFixture(t, approvalSetup{covers: &fakeReleaseCovers{}})
	e := pendingMatch(t, f.ctx, f.svc, approvedCandidate(), f.it)
	f.svc.Ingest.appliedWriteHook = func() error { return errors.New("the database is full") }
	if _, _, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e.ID, "approve", "", "", false); err == nil {
		t.Fatal("the approval succeeded, want its last write to fail")
	}
	if _, err := f.svc.lib.EditItemsFields(f.ctx, []model.ItemFieldEdit{{ItemPID: f.it.PID, Fields: map[string]string{"title": "A Person's Title"}}},
		waxbin.EditOptions{Source: model.SourceUser, Lock: model.LockOn, Force: true}); err != nil {
		t.Fatal(err)
	}
	if _, _, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e.ID, "skip", "", "", false); err != nil {
		t.Fatalf("skip: %v", err)
	}
	it, err := f.svc.lib.Get(f.ctx, f.it.PID)
	if err != nil {
		t.Fatal(err)
	}
	if it.Title != "A Person's Title" {
		t.Errorf("title after skip = %q, want the person's", it.Title)
	}
	if it.Album != f.it.Album || it.Artist != f.it.Artist {
		t.Errorf("fields after skip = %q / %q, want %q / %q", it.Album, it.Artist, f.it.Album, f.it.Artist)
	}
}

// A value the catalog stores trimmed still reads as the failed attempt's
// own: its retry keeps the before-value, and the revert puts it back.
func TestARetryKeepsTheBeforeOfAValueTheCatalogTrims(t *testing.T) {
	t.Parallel()
	f := openApprovalFixture(t, approvalSetup{covers: &fakeReleaseCovers{}})
	cand := approvedCandidate()
	cand.Title = "  The Release  "
	e := pendingMatch(t, f.ctx, f.svc, cand, f.it)
	var fail atomic.Bool
	fail.Store(true)
	f.svc.Ingest.appliedWriteHook = func() error {
		if fail.Load() {
			return errors.New("the database is full")
		}
		return nil
	}
	if _, _, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e.ID, "approve", "", "", false); err == nil {
		t.Fatal("the approval succeeded, want its last write to fail")
	}
	fail.Store(false)
	if _, _, err := f.svc.Ingest.DecideReviewEntry(f.ctx, f.uc, e.ID, "approve", "", "", false); err != nil {
		t.Fatalf("retry: %v", err)
	}
	if _, err := f.svc.Ingest.RevertReviewEntry(f.ctx, f.uc, e.ID); err != nil {
		t.Fatalf("revert: %v", err)
	}
	it, err := f.svc.lib.Get(f.ctx, f.it.PID)
	if err != nil {
		t.Fatal(err)
	}
	if it.Album != f.it.Album {
		t.Errorf("album after the revert = %q, want %q", it.Album, f.it.Album)
	}
}

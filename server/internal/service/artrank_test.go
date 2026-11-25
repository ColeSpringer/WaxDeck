package service

import (
	"bytes"
	"context"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"
	waxlabel "github.com/colespringer/waxlabel"

	"github.com/colespringer/waxdeck/fixtures"
)

func TestArtRankOrdersTheSources(t *testing.T) {
	t.Parallel()
	prov := func(src model.ProvenanceSource, provider, url string) *model.ArtProvenance {
		return &model.ArtProvenance{Level: model.ArtTrack, Attribution: model.Attribution{
			Source: src, Provider: provider, SourceURL: url,
		}}
	}
	const caa = "https://coverartarchive.org"
	for _, tc := range []struct {
		name       string
		prov       *model.ArtProvenance
		locked     bool
		downloaded string
		want       int
	}{
		{"a user's cover", prov(model.SourceUser, "", ""), false, "", artRankHeld},
		{"a locked download thumbnail", prov(model.SourceTag, "", ""), true, "youtube", artRankHeld},
		{"a lock with nothing behind it", nil, true, "", artRankHeld},
		{"the archive's release front", prov(model.SourceEnrichment, "coverartarchive", caa+"/release/0f6c1b5e-3c5a-4a7e-9e4f-1d2b3c4d5e6f/front-500"), false, "", artRankRelease},
		{"the archive's release front, full size", prov(model.SourceEnrichment, "coverartarchive", caa+"/release/0f6c1b5e-3c5a-4a7e-9e4f-1d2b3c4d5e6f/front"), false, "", artRankRelease},
		{"the archive's group front", prov(model.SourceEnrichment, "coverartarchive", caa+"/release-group/0f6c1b5e-3c5a-4a7e-9e4f-1d2b3c4d5e6f/front-1200"), false, "", artRankGroup},
		{"a release path from another provider", prov(model.SourceEnrichment, "deezer", "https://api.deezer.test/release/1/front"), false, "", artRankGroup},
		{"a provider keyed by name", prov(model.SourceEnrichment, "deezer", "https://e-cdns-images.dzcdn.test/images/cover/abc/1000x1000.jpg"), false, "", artRankGroup},
		{"a file's own art", prov(model.SourceTag, "", ""), false, "", artRankFile},
		{"a sidecar beside a download", prov(model.SourceSidecar, "", ""), false, "youtube", artRankFile},
		{"a download's thumbnail", prov(model.SourceTag, "", ""), false, "youtube", artRankDownload},
		{"a generated mosaic", prov(model.SourceGenerated, "", ""), false, "", artRankGenerated},
		{"no art at all", nil, false, "", artRankNone},
	} {
		if got := artRank(tc.prov, tc.locked, tc.downloaded); got != tc.want {
			t.Errorf("%s: rank %d, want %d", tc.name, got, tc.want)
		}
	}
	if !artVacant(artRankDownload) || !artVacant(artRankNone) {
		t.Error("a download's thumbnail and no art must both read as vacant")
	}
	for _, r := range []int{artRankHeld, artRankRelease, artRankGroup, artRankFile, artRankGenerated} {
		if artVacant(r) {
			t.Errorf("rank %d reads as vacant", r)
		}
	}
}

// registeredSource is a registered acquisition provider of one type;
// nothing here fetches through it.
type registeredSource struct {
	source.Provider
	typ model.SourceType
}

func (s registeredSource) SourceType() model.SourceType { return s.typ }

func thumbnailPNG(t *testing.T, shade uint8) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 32, 32))
	for y := range 32 {
		for x := range 32 {
			img.Set(x, y, color.RGBA{shade, 40, uint8(x * 8), 255})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// openThumbnailFixture is one scanned track whose file carries a front
// picture, under a server with a youtube source provider registered.
// origin, when set, is recorded as the item's acquisition origin.
func openThumbnailFixture(t *testing.T, origin model.SourceType) (context.Context, *Library, *UserCtx, string, *model.ItemView) {
	t.Helper()
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.SourceProviders = []source.Provider{registeredSource{typ: model.SourceYouTube}}
		paths, err := fixtures.Generate(c.Roots[0].Path, fixtures.Spec{
			Name: "thumbed", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
			Tags: map[string]string{"TITLE": "Thumbnail Cut", "ARTIST": "Test Ensemble", "ALBUM": "Thumbnail Album"},
		})
		if err != nil {
			t.Fatal(err)
		}
		doc, err := waxlabel.ParseFile(context.Background(), paths[0])
		if err != nil {
			t.Fatal(err)
		}
		ed := doc.Edit()
		ed.AddPicture(waxlabel.Picture{Type: waxlabel.PicFrontCover, MIME: "image/png", Data: thumbnailPNG(t, 200)})
		plan, err := ed.Prepare()
		if err != nil {
			t.Fatal(err)
		}
		if _, _, err := plan.Execute(context.Background(), waxlabel.SaveBack()); err != nil {
			t.Fatal(err)
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	apiPID, pid := fixtureTrackPID(t, ctx, svc, uc, "Thumbnail Cut")
	if origin != "" {
		if err := svc.lib.SetAcquisition(ctx, pid, model.AcquisitionInput{
			SourceType: origin, SourceURL: "https://www.youtube.test/watch?v=abc123&t=4", SourceID: "abc123",
		}, waxbin.AcquisitionEditOptions{Lock: model.LockOff}); err != nil {
			t.Fatal(err)
		}
		// An upload names no source, so its import records nothing.
		if origin != model.SourceManual {
			recordDownload(t, ctx, svc, pid, origin)
		}
	}
	it, err := svc.lib.Get(ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	return ctx, svc, uc, apiPID, it
}

// recordDownload records what landing a download as a new item records:
// the picture it arrived with, under the source it came through.
func recordDownload(t *testing.T, ctx context.Context, svc *Library, pid model.PID, from model.SourceType) {
	t.Helper()
	svc.Ingest.recordAcquiredArt(ctx, pid, from)
}

// A download's thumbnail is a vacancy any better cover may fill through
// the cover want. The catalog's own pass never writes a track's cover, so
// to it the thumbnail stays present, as any front is.
func TestADownloadsThumbnailIsVacant(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _, it := openThumbnailFixture(t, model.SourceYouTube)
	if got, _ := svc.Enrichment.coverGuard(ctx, it, map[string]bool{}); got != "" {
		t.Errorf("coverGuard = %q, want the thumbnail open to a better cover", got)
	}
	if !svc.Enrichment.artifactPresent(ctx, it, enrichWantCover) {
		t.Error("artifactPresent = false for a download's thumbnail, want any front present to the catalog pass")
	}
	// A person's pin holds it whatever it is.
	if got, _ := svc.Enrichment.coverGuard(ctx, it, map[string]bool{"art": true}); got != "cover: locked" {
		t.Errorf("locked: coverGuard = %q, want cover: locked", got)
	}
	ref := model.EntityRef{Type: model.ArtTrack, PID: it.PID}
	if got := svc.Ingest.frontArtRank(ctx, ref, true); got != artRankHeld {
		t.Errorf("a locked thumbnail ranks %d, want %d", got, artRankHeld)
	}
	if got := svc.Ingest.frontArtRank(ctx, ref, false); got != artRankDownload {
		t.Errorf("the thumbnail ranks %d, want %d", got, artRankDownload)
	}
}

// An upload's embedded art is the file's own: the import records a
// manual origin, which is no registered source's.
func TestAnUploadsEmbeddedArtIsNotVacant(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _, it := openThumbnailFixture(t, model.SourceManual)
	if got, _ := svc.Enrichment.coverGuard(ctx, it, map[string]bool{}); got != "cover: already present" {
		t.Errorf("coverGuard = %q, want cover: already present", got)
	}
	if !svc.Enrichment.artifactPresent(ctx, it, enrichWantCover) {
		t.Error("artifactPresent = false for an upload's own art")
	}
}

func TestAUserCoverOnADownloadIsNotVacant(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _, it := openThumbnailFixture(t, model.SourceYouTube)
	if err := svc.lib.SetItemArt(ctx, it.PID, model.ArtRoleFront, thumbnailPNG(t, 60), waxbin.ArtEditOptions{
		Source: model.SourceUser, Lock: model.LockUnchanged,
	}); err != nil {
		t.Fatal(err)
	}
	if got, _ := svc.Enrichment.coverGuard(ctx, it, map[string]bool{}); got != "cover: already present" {
		t.Errorf("coverGuard = %q, want cover: already present", got)
	}
	if !svc.Enrichment.artifactPresent(ctx, it, enrichWantCover) {
		t.Error("artifactPresent = false for a user's cover")
	}
}

// Every read that answers a cover's source names a download's thumbnail
// as the source's, with no address; the catalog still holds it as the
// file's.
func TestADownloadsThumbnailReadsAsTheSources(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, apiPID, it := openThumbnailFixture(t, model.SourceYouTube)
	want := ArtSourceDTO{Source: "acquisition", Provider: "youtube"}
	same := func(what string, got ArtSourceDTO) {
		t.Helper()
		if got.Source != want.Source || got.Provider != want.Provider || got.SourceURL != want.SourceURL {
			t.Errorf("%s = %s/%s/%s, want %s/%s/%s", what, got.Source, got.Provider, got.SourceURL,
				want.Source, want.Provider, want.SourceURL)
		}
	}
	d, err := svc.Reads.Item(ctx, uc, apiPID)
	if err != nil {
		t.Fatal(err)
	}
	same("item detail", d.ArtSource)
	blob, err := svc.Reads.Art(ctx, uc, apiPID, string(model.ArtRoleFront), 0)
	if err != nil {
		t.Fatal(err)
	}
	same("the art read", blob.Source)
	roles, err := svc.Reads.ItemArtRoles(ctx, uc, apiPID)
	if err != nil {
		t.Fatal(err)
	}
	same("the roles read", roles.ArtSource)
	if len(roles.Roles) != 1 || roles.Roles[0].Source != "acquisition" || roles.Roles[0].Provider != "youtube" {
		t.Errorf("roles = %+v, want the front as acquisition/youtube", roles.Roles)
	}
	prov, err := svc.lib.ArtProvenance(ctx, model.EntityRef{Type: model.ArtTrack, PID: it.PID}, model.ArtRoleFront)
	if err != nil || prov.Source != model.SourceTag {
		t.Errorf("the catalog's attribution = %+v (%v), want it left as tag", prov, err)
	}

	// The album borrows the thumbnail from its member: the picture's hash
	// is the one the member arrived with.
	album, err := svc.Reads.Album(ctx, uc, d.AlbumPID)
	if err != nil {
		t.Fatal(err)
	}
	if !album.ArtSource.Derived {
		t.Errorf("album artSource = %+v, want it derived", album.ArtSource)
	}
	same("the album detail", album.ArtSource)
	albumBlob, err := svc.Reads.Art(ctx, uc, d.AlbumPID, string(model.ArtRoleFront), 0)
	if err != nil {
		t.Fatal(err)
	}
	same("the album's art read", albumBlob.Source)
}

// A borrowed picture is the download's only while its hash is the one a
// member arrived with: once the member's file carries another, the album
// reads it as the file's.
func TestABorrowedCoverIsTheDownloadsOnlyByItsHash(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, apiPID, it := openThumbnailFixture(t, model.SourceYouTube)
	replacePicture(t, string(it.Path), thumbnailPNG(t, 10))
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{Force: true}); err != nil {
		t.Fatal(err)
	}
	d, err := svc.Reads.Item(ctx, uc, apiPID)
	if err != nil {
		t.Fatal(err)
	}
	album, err := svc.Reads.Album(ctx, uc, d.AlbumPID)
	if err != nil {
		t.Fatal(err)
	}
	if album.ArtSource.Source != "tag" || !album.ArtSource.Derived {
		t.Errorf("album artSource = %+v, want the file's own, derived", album.ArtSource)
	}
}

// What a download arrived with is a recorded fact: with no acquisition
// provider configured now, its thumbnail still ranks and reads as the
// source's.
func TestAThumbnailIsKnownWithItsProviderSwitchedOff(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, apiPID, it := openThumbnailFixture(t, model.SourceYouTube)
	svc.Ingest.sourceProviders = nil
	if got := rankOf(ctx, svc, it.PID); got != artRankDownload {
		t.Errorf("the thumbnail ranks %d, want %d", got, artRankDownload)
	}
	d, err := svc.Reads.Item(ctx, uc, apiPID)
	if err != nil {
		t.Fatal(err)
	}
	if d.ArtSource.Source != artSourceAcquisition || d.ArtSource.Provider != "youtube" {
		t.Errorf("item detail artSource = %+v, want acquisition/youtube", d.ArtSource)
	}
}

func TestAnUploadsEmbeddedArtReadsAsTheFiles(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, apiPID, _ := openThumbnailFixture(t, model.SourceManual)
	d, err := svc.Reads.Item(ctx, uc, apiPID)
	if err != nil {
		t.Fatal(err)
	}
	if d.ArtSource.Source != "tag" || d.ArtSource.Provider != "" || d.ArtSource.SourceURL != "" {
		t.Errorf("item detail artSource = %+v, want the file's own", d.ArtSource)
	}
}

// rankOf is the rank an item's front holds unlocked.
func rankOf(ctx context.Context, svc *Library, pid model.PID) int {
	return svc.Ingest.frontArtRank(ctx, model.EntityRef{Type: model.ArtTrack, PID: pid}, false)
}

// replacePicture swaps a file's front picture the way another tool would.
func replacePicture(t *testing.T, path string, data []byte) {
	t.Helper()
	doc, err := waxlabel.ParseFile(context.Background(), path)
	if err != nil {
		t.Fatal(err)
	}
	ed := doc.Edit()
	ed.ClearPictures()
	ed.AddPicture(waxlabel.Picture{Type: waxlabel.PicFrontCover, MIME: "image/png", Data: data})
	plan, err := ed.Prepare()
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := plan.Execute(context.Background(), waxlabel.SaveBack()); err != nil {
		t.Fatal(err)
	}
}

// The thumbnail is the picture the download arrived with, known by its
// bytes. A person's cover written into the file reads back as the file's
// once a rescan re-reads it, and stays theirs: the file's own art, not
// the source's, and not a vacancy.
func TestAPersonsCoverWrittenIntoADownloadStaysTheFiles(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, apiPID, it := openThumbnailFixture(t, model.SourceYouTube)
	if err := svc.lib.SetItemArt(ctx, it.PID, model.ArtRoleFront, thumbnailPNG(t, 60), waxbin.ArtEditOptions{
		Source: model.SourceUser, Lock: model.LockOff, WriteBack: true,
	}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{Force: true}); err != nil {
		t.Fatal(err)
	}
	if got := rankOf(ctx, svc, it.PID); got == artRankDownload || artVacant(got) {
		t.Errorf("the person's cover after a rescan ranks %d, want it held (rank %d or better)", got, artRankFile)
	}
	d, err := svc.Reads.Item(ctx, uc, apiPID)
	if err != nil {
		t.Fatal(err)
	}
	if d.ArtSource.Source == artSourceAcquisition {
		t.Errorf("item detail names the person's cover the source's: %+v", d.ArtSource)
	}
	if got, _ := svc.Enrichment.coverGuard(ctx, it, map[string]bool{}); got != "cover: already present" {
		t.Errorf("coverGuard = %q, want cover: already present", got)
	}
}

// A download whose picture was replaced in another tool carries the
// file's own art.
func TestADownloadRetaggedElsewhereCarriesTheFilesArt(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, apiPID, it := openThumbnailFixture(t, model.SourceYouTube)
	replacePicture(t, string(it.Path), thumbnailPNG(t, 10))
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{Force: true}); err != nil {
		t.Fatal(err)
	}
	if got := rankOf(ctx, svc, it.PID); got != artRankFile {
		t.Errorf("a retagged download's front ranks %d, want the file's own (%d)", got, artRankFile)
	}
	d, err := svc.Reads.Item(ctx, uc, apiPID)
	if err != nil {
		t.Fatal(err)
	}
	if d.ArtSource.Source != "tag" {
		t.Errorf("item detail artSource = %+v, want the file's own", d.ArtSource)
	}
}

// An origin alone does not make a thumbnail: an item nothing recorded a
// download picture for carries the file's own art.
func TestAnOriginAloneIsNotAThumbnail(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _, it := openThumbnailFixture(t, "")
	if err := svc.lib.SetAcquisition(ctx, it.PID, model.AcquisitionInput{
		SourceType: model.SourceYouTube, SourceURL: "https://www.youtube.test/watch?v=abc123",
	}, waxbin.AcquisitionEditOptions{Lock: model.LockOff}); err != nil {
		t.Fatal(err)
	}
	if got := rankOf(ctx, svc, it.PID); got != artRankFile {
		t.Errorf("an unrecorded front on a youtube-origin item ranks %d, want %d", got, artRankFile)
	}
}

// The cover want's fill over a download's thumbnail goes into the file
// too, as an approval's does, so a forced re-read keeps it.
func TestACoverWantFillOverAThumbnailReachesTheFile(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _, it := openThumbnailFixture(t, model.SourceYouTube)
	cover := thumbnailPNG(t, 60)
	applied, skipped := svc.Enrichment.commitCover(ctx, it, EnrichCoverProposalDTO{
		Provider: "deezer", Format: "png", SourceURL: "https://cdn.deezer.test/cover.png", Data: cover,
	}, map[string]bool{}, nil)
	if applied != "cover: deezer" || skipped != "" {
		t.Fatalf("commit = %q / %q, want the cover applied and nothing skipped", applied, skipped)
	}
	if !bytes.Equal(filePicture(t, string(it.Path)), cover) {
		t.Error("the file still carries the thumbnail")
	}
	want, err := svc.lib.ArtProvenance(ctx, model.EntityRef{Type: model.ArtTrack, PID: it.PID}, model.ArtRoleFront)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{Force: true}); err != nil {
		t.Fatal(err)
	}
	got, err := svc.lib.ArtProvenance(ctx, model.EntityRef{Type: model.ArtTrack, PID: it.PID}, model.ArtRoleFront)
	if err != nil {
		t.Fatal(err)
	}
	if got.SourceHash != want.SourceHash {
		t.Errorf("front after a forced rescan = %+v, want the filled cover kept", got)
	}
	if rank := rankOf(ctx, svc, it.PID); artVacant(rank) {
		t.Errorf("the filled cover ranks %d after a forced rescan, want it no vacancy", rank)
	}
}

// Where the library cannot be written the fill stays in the catalog and
// the result says the file was not written.
func TestACoverWantFillOverAThumbnailSaysWhenTheFileIsNotWritten(t *testing.T) {
	t.Parallel()
	ctx, svc, _, _, it := openThumbnailFixture(t, model.SourceYouTube)
	if _, err := svc.lib.SetLibraryReadOnly(ctx, it.LibraryPID, true); err != nil {
		t.Fatal(err)
	}
	svc.Roots.refreshLibraryState(ctx)
	thumb := filePicture(t, string(it.Path))
	applied, skipped := svc.Enrichment.commitCover(ctx, it, EnrichCoverProposalDTO{
		Provider: "deezer", Format: "png", Data: thumbnailPNG(t, 60),
	}, map[string]bool{}, nil)
	if applied != "cover: deezer" {
		t.Errorf("applied = %q, want the cover applied in the catalog", applied)
	}
	if !strings.HasPrefix(skipped, "cover: not written to the file: ") {
		t.Errorf("skipped = %q, want the unwritten file named", skipped)
	}
	if !bytes.Equal(filePicture(t, string(it.Path)), thumb) {
		t.Error("a read-only library's file was written")
	}
}

// Why a file was not written is named only to a reader who may read of
// that file, as an approval's warnings are.
func TestACoverWantsUnwrittenFileIsNamedOnlyToWhoMayReadOfIt(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name   string
		reader *UserCtx
		named  bool
	}{
		{"anyone", nil, true},
		{"an administrator", &UserCtx{ID: "us-admin", Admin: true, AllLibraries: true}, true},
		{"a reader not granted the library", &UserCtx{ID: "us-other", Libraries: map[string]bool{}}, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, _, _, it := openThumbnailFixture(t, model.SourceYouTube)
			dir := filepath.Dir(string(it.Path))
			if err := os.Chmod(dir, 0o555); err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = os.Chmod(dir, 0o755) })
			applied, skipped := svc.Enrichment.commitCover(ctx, it, EnrichCoverProposalDTO{
				Provider: "deezer", Format: "png", Data: thumbnailPNG(t, 60),
			}, map[string]bool{}, tc.reader)
			if applied != "cover: deezer" {
				t.Errorf("applied = %q, want the cover applied in the catalog", applied)
			}
			if named := strings.HasPrefix(skipped, "cover: not written to the file: "); named != tc.named {
				t.Errorf("skipped = %q, want the unwritten file named: %v", skipped, tc.named)
			}
		})
	}
}

// A track with no picture of its own shows its album's front, borrowed
// from a member download's thumbnail: it reads as the source's, ranks as
// a vacancy to the cover want, and an approval replaces it.
func TestATrackShowingABorrowedThumbnailIsTheDownloads(t *testing.T) {
	t.Parallel()
	covers := &fakeReleaseCovers{front: map[string][]byte{approvedRelease: thumbnailPNG(t, 30)}}
	ctx, svc, uc := openEnrichFixture(t, func(c *Config) {
		c.SourceProviders = []source.Provider{registeredSource{typ: model.SourceYouTube}}
		c.ReleaseCovers = covers
		for _, title := range []string{"Thumbnail Cut", "Bare Cut"} {
			paths, err := fixtures.Generate(c.Roots[0].Path, fixtures.Spec{
				Name: strings.ToLower(strings.ReplaceAll(title, " ", "-")), Codec: fixtures.CodecFLAC, Duration: time.Second,
				Tags: map[string]string{"TITLE": title, "ARTIST": "Test Ensemble", "ALBUM": "Shared Album"},
			})
			if err != nil {
				t.Fatal(err)
			}
			if title == "Thumbnail Cut" {
				replacePicture(t, paths[0], thumbnailPNG(t, 200))
			}
		}
	})
	if _, err := svc.lib.Scan(ctx, waxbin.ScanRequest{}); err != nil {
		t.Fatal(err)
	}
	_, thumbed := fixtureTrackPID(t, ctx, svc, uc, "Thumbnail Cut")
	if err := svc.lib.SetAcquisition(ctx, thumbed, model.AcquisitionInput{
		SourceType: model.SourceYouTube, SourceURL: "https://www.youtube.test/watch?v=abc123",
	}, waxbin.AcquisitionEditOptions{Lock: model.LockOff}); err != nil {
		t.Fatal(err)
	}
	recordDownload(t, ctx, svc, thumbed, model.SourceYouTube)
	apiPID, bare := fixtureTrackPID(t, ctx, svc, uc, "Bare Cut")
	if err := svc.lib.SetAcquisition(ctx, bare, model.AcquisitionInput{SourceType: model.SourceManual},
		waxbin.AcquisitionEditOptions{Lock: model.LockOff}); err != nil {
		t.Fatal(err)
	}
	it, err := svc.lib.Get(ctx, bare)
	if err != nil {
		t.Fatal(err)
	}

	d, err := svc.Reads.Item(ctx, uc, apiPID)
	if err != nil {
		t.Fatal(err)
	}
	if d.ArtSource.Source != artSourceAcquisition || d.ArtSource.Provider != "youtube" || !d.ArtSource.Derived {
		t.Errorf("item detail artSource = %+v, want acquisition/youtube, derived", d.ArtSource)
	}
	if got, _ := svc.Enrichment.coverGuard(ctx, it, map[string]bool{}); got != "" {
		t.Errorf("coverGuard = %q, want the borrowed thumbnail open to a better cover", got)
	}

	cand := approvedCandidate()
	cand.Pairings[0].Title = "Bare Cut"
	e := pendingMatch(t, ctx, svc, cand, it)
	if _, _, err := svc.Ingest.DecideReviewEntry(ctx, uc, e.ID, "approve", "", "", false); err != nil {
		t.Fatalf("approve: %v", err)
	}
	prov, err := svc.lib.ArtProvenance(ctx, model.EntityRef{Type: model.ArtTrack, PID: bare}, model.ArtRoleFront)
	if err != nil || prov.Level != model.ArtTrack || prov.SourceURL != fakeArchive+"/release/"+approvedRelease+"/front-500" {
		t.Errorf("front after the approval = %+v (%v), want the release's own", prov, err)
	}
}

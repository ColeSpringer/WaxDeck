package service

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"

	"github.com/colespringer/waxdeck/fixtures"
)

// grantedUploader makes an uploader granted the library named lib alone.
func grantedUploader(t *testing.T, ctx context.Context, svc *Library, name, lib string) *UserCtx {
	t.Helper()
	var pid string
	for _, r := range svc.libraryRoots() {
		if r.Name == lib {
			pid = r.PID
		}
	}
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: name, Password: "correct-horse", AccessMode: "granted",
		LibraryPIDs: []string{apiPID(PrefixLibrary, model.PID(pid))}, UploadEnabled: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return uc
}

// tomePart is a part of the book "Shared Tome" by Ann Author, its audio
// as long as d so no two parts are the same audio.
func tomePart(t *testing.T, dir, name, title, track string, d time.Duration) string {
	t.Helper()
	paths, err := fixtures.Generate(dir, fixtures.Spec{
		Name: name, Codec: fixtures.CodecFLAC, Duration: d,
		Tags: map[string]string{"TITLE": title, "ARTIST": "Ann Author", "ALBUMARTIST": "Ann Author",
			"ALBUM": "Shared Tome", "TRACKNUMBER": track},
	})
	if err != nil {
		t.Fatal(err)
	}
	return paths[0]
}

// convertedBy turns an uploader's one upload into a book and answers the
// item it was, once the change has ended.
func convertedBy(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, up UploadDTO) (string, Job) {
	t.Helper()
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil || row.ItemPID == "" {
		t.Fatalf("upload = %+v, %v; want it imported", row, err)
	}
	it, err := svc.lib.Get(ctx, model.PID(row.ItemPID))
	if err != nil {
		t.Fatal(err)
	}
	started, err := svc.SetItemsKind(ctx, uc, []string{itemAPIPID(it)}, "audiobook", false)
	if err != nil {
		t.Fatal(err)
	}
	_, jobPID, _ := parseAPIPID(started.PID)
	waitForJob(t, ctx, svc, jobPID)
	return itemAPIPID(it), started
}

// A kind change whose file names a book someone else brought in folds
// into that book, as an upload of it as a book would have joined it: the
// book, its pid and who may edit it stand, and the starter's item, gone
// into it, grants them nothing.
func TestAKindChangeMeetingSomeonesBookJoinsIt(t *testing.T) {
	ctx, svc, admin := managedUploadFixture(t)
	v, u := grantedUploader(t, ctx, svc, "vee", "lib"), grantedUploader(t, ctx, svc, "you", "lib")
	book := uploadPathAs(t, ctx, svc, v, tomePart(t, t.TempDir(), "vone", "Part One", "1", 2*time.Second), "audiobook", false, "")
	brow, err := svc.db.UploadByID(ctx, book.ID)
	if err != nil {
		t.Fatal(err)
	}
	bookPID := "bk-" + brow.ItemPID
	track, started := convertedBy(t, ctx, svc, u,
		uploadPathAs(t, ctx, svc, u, tomePart(t, t.TempDir(), "utwo", "Part Two", "2", 3*time.Second), "music", false, ""))
	job, err := svc.JobStatusFor(ctx, admin, started.PID)
	if err != nil || job.SetKind == nil {
		t.Fatalf("job = %+v, %v", job, err)
	}
	if len(job.SetKind.Converted) != 0 || job.SetKind.Absorbed[track] != bookPID {
		t.Fatalf("tally = %+v, want %s folded into %s", job.SetKind, track, bookPID)
	}
	for _, c := range []struct {
		who  *UserCtx
		want bool
	}{{v, true}, {u, false}} {
		if may, err := svc.MayCurateItem(ctx, c.who, bookPID); err != nil || may != c.want {
			t.Errorf("%s may edit the book = %v, %v; want %v", c.who.ID, may, err, c.want)
		}
	}
}

// A starter's item folded into a book in a library they are not granted
// stays in their report, its own pid and nothing of the book's: an empty
// report would say nothing changed.
func TestAKindChangeIntoAnUnseenBookTellsItsStarter(t *testing.T) {
	books := t.TempDir()
	ctx, svc, admin := managedUploadFixture(t, Root{Name: "books", Path: books, Media: "audiobook"})
	tomePart(t, books, "aone", "Part One", "1", 2*time.Second)
	scan, err := svc.lib.StartScan(ctx, waxbin.ScanRequest{})
	if err != nil {
		t.Fatal(err)
	}
	waitForJob(t, ctx, svc, scan)
	u := grantedUploader(t, ctx, svc, "you", "lib")
	track, started := convertedBy(t, ctx, svc, u,
		uploadPathAs(t, ctx, svc, u, tomePart(t, t.TempDir(), "utwo", "Part Two", "2", 3*time.Second), "music", false, ""))
	whole, err := svc.JobStatusFor(ctx, admin, started.PID)
	if err != nil || whole.SetKind == nil || whole.SetKind.Absorbed[track] == "" {
		t.Fatalf("administrator's tally = %+v, %v; want %s folded into the book in %s", whole.SetKind, err, track, filepath.Base(books))
	}
	job, err := svc.JobStatusFor(ctx, u, started.PID)
	if err != nil || job.SetKind == nil {
		t.Fatalf("starter's read = %+v, %v", job, err)
	}
	if to, ok := job.SetKind.Absorbed[track]; !ok || to != "" || len(job.SetKind.Absorbed) != 1 {
		t.Fatalf("starter's tally = %+v, want %s folded into an item withheld", job.SetKind, track)
	}
}

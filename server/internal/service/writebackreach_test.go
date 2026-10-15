package service

import (
	"context"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
)

// copyReach is an item an uploader brought into the managed library,
// with a copy of its audio in another library the uploader is not
// granted.
type copyReach struct {
	ctx           context.Context
	svc           *Library
	admin, bob    *UserCtx
	item          *model.ItemView
	primary, copy model.ItemFileRef
	other         Root
}

func newCopyReach(t *testing.T) copyReach {
	t.Helper()
	otherDir := t.TempDir()
	ctx, svc, admin := managedUploadFixture(t, Root{Name: "other", Path: otherDir})
	var lib, other Root
	for _, r := range svc.libraryRoots() {
		switch r.Name {
		case "lib":
			lib = r
		case "other":
			other = r
		}
	}
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "bob", Password: "correct-horse", AccessMode: "granted",
		LibraryPIDs: []string{apiPID(PrefixLibrary, model.PID(lib.PID))}, UploadEnabled: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	bob, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	path := flacTagged(t, "reach", map[string]string{"TITLE": "Reach", "ARTIST": "Reach Band", "ALBUM": "Reach Album"})
	up := uploadPathAsking(t, ctx, svc, bob, path, false, "")
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil || row.ItemPID == "" {
		t.Fatalf("bob's upload = %+v, %v; want it imported", row, err)
	}
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(otherDir, "reach.flac"), raw, 0o644); err != nil {
		t.Fatal(err)
	}
	scanPID, err := svc.lib.StartScan(ctx, waxbin.ScanRequest{LibraryPID: model.PID(other.PID)})
	if err != nil {
		t.Fatal(err)
	}
	waitForJob(t, ctx, svc, scanPID)
	it, err := svc.lib.Get(ctx, model.PID(row.ItemPID))
	if err != nil {
		t.Fatal(err)
	}
	refs, err := svc.lib.ItemFiles(ctx, it.PID)
	if err != nil {
		t.Fatal(err)
	}
	c := copyReach{ctx: ctx, svc: svc, admin: admin, bob: bob, item: it, other: other}
	for _, ref := range refs {
		if string(ref.LibraryPID) == other.PID {
			c.copy = ref
		} else {
			c.primary = ref
		}
	}
	if c.copy.FilePID == "" || c.primary.FilePID == "" {
		t.Fatalf("item files = %+v, want the upload and its copy in the other library", refs)
	}
	return c
}

// A write-back's failures reach a reader who is not an administrator
// only for files in libraries they are granted, each by its name and in
// plain words; an administrator reads them whole. Narrowing twice
// changes nothing.
func TestAWriteBackFailureReachesOnlyWhoMayReadItsFile(t *testing.T) {
	c := newCopyReach(t)
	primary, copy := string(c.primary.Path), string(c.copy.Path)
	fs := []WriteBackFailureDTO{
		{FilePID: string(c.primary.FilePID), Path: primary,
			Reason: "meta.Writer.Apply: writing tags to " + primary + ": permission denied"},
		{FilePID: string(c.copy.FilePID), Path: copy, Reason: "writing tags to " + copy + ": read-only file system"},
		{Reason: "no backing file path is known"},
	}
	if got := c.svc.WriteBackFailuresFor(c.ctx, c.admin, fs); !slices.Equal(got, fs) {
		t.Fatalf("administrator reads %+v, want the failures whole", got)
	}
	got := c.svc.WriteBackFailuresFor(c.ctx, c.bob, fs)
	if len(got) != 2 || got[0].FilePID != string(c.primary.FilePID) || got[1].FilePID != "" {
		t.Fatalf("bob reads %+v, want his own file's failure and the one naming no file", got)
	}
	if got[0].Path != filepath.Base(primary) || strings.Contains(got[0].Reason, filepath.Dir(primary)) || strings.Contains(got[0].Reason, "meta.") {
		t.Fatalf("bob reads %+v, want the file's name and plain words", got[0])
	}
	if again := c.svc.WriteBackFailuresFor(c.ctx, c.bob, got); !slices.Equal(again, got) {
		t.Fatalf("narrowed twice = %+v, want %+v", again, got)
	}
}

// A kind change's report, read by an uploader whose item has a copy in a
// library they are not granted, says nothing of that copy: not the
// write-back it refused, nor its file.
func TestAKindChangesReportKeepsAnUngrantedCopyOutOfItsStartersSight(t *testing.T) {
	c := newCopyReach(t)
	if err := c.svc.LibraryReadOnlySet(c.ctx, c.admin, apiPID(PrefixLibrary, model.PID(c.other.PID)), true); err != nil {
		t.Fatal(err)
	}
	started, err := c.svc.SetItemsKind(c.ctx, c.bob, []string{itemAPIPID(c.item)}, "audiobook", true)
	if err != nil {
		t.Fatal(err)
	}
	_, jobPID, _ := parseAPIPID(started.PID)
	waitForJob(t, c.ctx, c.svc, jobPID)
	admin, err := c.svc.JobStatusFor(c.ctx, c.admin, started.PID)
	if err != nil || admin.SetKind == nil {
		t.Fatalf("administrator's read = %+v, %v", admin, err)
	}
	if !slices.ContainsFunc(admin.SetKind.WriteBackFailures, func(f WriteBackFailureDTO) bool { return f.FilePID == string(c.copy.FilePID) }) {
		t.Fatalf("the copy's write was not refused: %+v", admin.SetKind.WriteBackFailures)
	}
	bob, err := c.svc.JobStatusFor(c.ctx, c.bob, started.PID)
	if err != nil || bob.SetKind == nil {
		t.Fatalf("bob's read = %+v, %v", bob, err)
	}
	for _, f := range bob.SetKind.WriteBackFailures {
		if f.FilePID == string(c.copy.FilePID) || strings.Contains(f.Reason, c.other.Path) {
			t.Fatalf("bob reads the ungranted copy's failure: %+v", f)
		}
	}
}

// A decision's write-back warnings, like an edit's failures, name only
// the files the deciding reader may see.
func TestADecisionsWarningsNameOnlyFilesItsReaderSees(t *testing.T) {
	c := newCopyReach(t)
	res := &waxbin.BatchEditResult{WriteBackErrors: map[model.PID]*waxbin.WriteBackError{
		c.item.PID: {Failures: []waxbin.WriteBackFailure{
			{FilePID: c.primary.FilePID, Path: string(c.primary.Path), Reason: "permission denied"},
			{FilePID: c.copy.FilePID, Path: string(c.copy.Path), Reason: "on-disk tag write-back is unavailable in a read-only library"},
		}},
	}}
	if got := c.svc.writeBackWarnings(c.ctx, c.admin, res, nil); len(got) != 2 {
		t.Fatalf("administrator's warnings = %q, want both files", got)
	}
	got := c.svc.writeBackWarnings(c.ctx, c.bob, res, nil)
	if len(got) != 1 || !strings.HasPrefix(got[0], filepath.Base(string(c.primary.Path))+":") {
		t.Fatalf("bob's warnings = %q, want his own file's alone", got)
	}
}

// The editor's per-file write-back issues, read by someone not granted
// the library a copy sits in, leave that copy out, as its file list does.
func TestTheEditorsFileIssuesLeaveOutAnUngrantedCopy(t *testing.T) {
	c := newCopyReach(t)
	if err := c.svc.LibraryReadOnlySet(c.ctx, c.admin, apiPID(PrefixLibrary, model.PID(c.other.PID)), true); err != nil {
		t.Fatal(err)
	}
	if _, err := c.svc.EditItemMetadata(c.ctx, c.admin, itemAPIPID(c.item), map[string]string{"title": "Reach Again"},
		MetadataEditParams{WriteBack: true}); err != nil {
		t.Fatal(err)
	}
	names := func(uc *UserCtx) []string {
		t.Helper()
		doc, err := c.svc.ItemMetadataFor(c.ctx, uc, itemAPIPID(c.item))
		if err != nil {
			t.Fatal(err)
		}
		var out []string
		for _, issue := range doc.WriteBackIssues {
			out = append(out, issue.FilePID)
		}
		return out
	}
	if !slices.Contains(names(c.admin), string(c.copy.FilePID)) {
		t.Fatalf("administrator's issues = %v, want the refused copy among them", names(c.admin))
	}
	if got := names(c.bob); slices.Contains(got, string(c.copy.FilePID)) {
		t.Fatalf("bob's issues = %v, want the ungranted copy left out", got)
	}
}

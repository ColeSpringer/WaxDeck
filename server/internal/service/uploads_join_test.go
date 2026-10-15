package service

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// scriptedFeed answers the change feed from a fixed log, a page of at
// most two rows at a time, as the catalog pages its own.
func scriptedFeed(log []model.Change, fail error) func(context.Context, int64) ([]model.Change, error) {
	return func(_ context.Context, since int64) ([]model.Change, error) {
		if fail != nil {
			return nil, fail
		}
		var page []model.Change
		for _, c := range log {
			if c.Seq > since && len(page) < 2 {
				page = append(page, c)
			}
		}
		return page, nil
	}
}

// The follower collects every item created past its start across pages,
// grows as the feed does, and gives up on a feed it cannot read or a
// catalog replaced under it.
func TestFollowingTheFeedFindsTheItemsAnImportMade(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	log := []model.Change{
		{Seq: 11, EntityType: "item", EntityPID: "made-1", Op: model.OpCreate},
		{Seq: 12, EntityType: "item", EntityPID: "held", Op: model.OpUpdate},
		{Seq: 13, EntityType: "album", EntityPID: "an-album", Op: model.OpCreate},
		{Seq: 14, EntityType: "item", EntityPID: "made-2", Op: model.OpCreate},
	}
	f := &createdFeed{read: scriptedFeed(log, nil), seq: 10, created: map[model.PID]bool{}}
	if !f.made(ctx, "made-1") || !f.made(ctx, "made-2") || f.made(ctx, "held") || f.made(ctx, "an-album") {
		t.Fatalf("created = %v, want the two items created after the start", f.created)
	}
	log = append(log, model.Change{Seq: 15, EntityType: "item", EntityPID: "made-3", Op: model.OpCreate})
	f.read = scriptedFeed(log, nil)
	if !f.made(ctx, "made-3") {
		t.Fatal("an item created after the first read was missed")
	}

	replaced := &createdFeed{read: scriptedFeed(append(log, model.Change{Seq: 16, EntityType: model.ChangeCatalog}), nil),
		seq: 10, created: map[model.PID]bool{}}
	if replaced.made(ctx, "made-1") || !replaced.broken {
		t.Fatal("a catalog replaced under the import still answered")
	}
	unreadable := &createdFeed{read: scriptedFeed(nil, errors.New("closed")), seq: 10, created: map[model.PID]bool{}}
	if unreadable.made(ctx, "made-1") || !unreadable.broken {
		t.Fatal("an unreadable feed answered")
	}
}

// The follower restarts at the catalog's tail before each file it
// applies: an item someone else made while an earlier file of the entry
// was applied is not this file's making.
func TestTheFeedRestartsBeforeEachFile(t *testing.T) {
	t.Parallel()
	ctx := context.Background()
	log := []model.Change{
		{Seq: 11, EntityType: "item", EntityPID: "made-by-another", Op: model.OpCreate},
		{Seq: 12, EntityType: "item", EntityPID: "made-by-this-file", Op: model.OpCreate},
	}
	tail := int64(11)
	f := &createdFeed{read: scriptedFeed(log, nil), created: map[model.PID]bool{},
		tail: func(context.Context) (int64, error) { return tail, nil }}
	f.restart(ctx)
	if f.made(ctx, "made-by-another") || !f.made(ctx, "made-by-this-file") {
		t.Fatalf("created = %v, want only what came after the restart", f.created)
	}
	failing := &createdFeed{read: scriptedFeed(log, nil), created: map[model.PID]bool{},
		tail: func(context.Context) (int64, error) { return 0, errors.New("closed") }}
	failing.restart(ctx)
	if failing.made(ctx, "made-by-this-file") || !failing.broken {
		t.Fatal("a feed whose tail could not be read still answered")
	}
}

// A file that joined an item settles imported with no item recorded, so
// its uploader holds no right over that item, while its staging goes
// and a sync download's map row still learns the item.
func TestAJoinedFileSettlesWithoutAGrant(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "uploader", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	holder := fixtureItemPIDs(t, ctx, svc, admin)[0]
	_, bare, _ := parseAPIPID(holder)
	entry := wdb.ReviewEntry{ID: "re-joined", Kind: reviewKindImport, Status: reviewPending,
		MediaType: "music", Origin: reviewOriginUpload, UploadedBy: acct.User.ID, CreatedAtNS: time.Now().UnixNano()}
	if err := svc.db.InsertReviewEntry(ctx, entry); err != nil {
		t.Fatal(err)
	}
	staged := filepath.Join(svc.stagingDir, "up-joined", "copy.flac")
	if err := os.MkdirAll(filepath.Dir(staged), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(staged, []byte("audio"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := svc.db.InsertUpload(ctx, wdb.Upload{ID: "up-joined", UserID: acct.User.ID, FileName: "copy.flac",
		State: uploadStaged, StagingPath: staged, ReviewEntryID: entry.ID, DuplicatePID: string(bare),
		DuplicateKind: "content", CreatedAtNS: time.Now().UnixNano()}); err != nil {
		t.Fatal(err)
	}

	svc.settleImportedUploads(ctx, &entry, map[string]importedFile{staged: {pid: string(bare), joined: true}})

	row, err := svc.db.UploadByID(ctx, "up-joined")
	if err != nil {
		t.Fatal(err)
	}
	if row.State != uploadImported || row.ItemPID != "" || row.DuplicatePID != string(bare) {
		t.Fatalf("settled row = %+v, want imported, no item, its warning kept", row)
	}
	if owns, err := svc.db.UploadOwnsItem(ctx, acct.User.ID, string(bare)); err != nil || owns {
		t.Fatalf("uploader owns the item it joined = %v (%v)", owns, err)
	}
	if _, err := os.Stat(filepath.Dir(staged)); !os.IsNotExist(err) {
		t.Fatalf("staging left behind (%v)", err)
	}
}

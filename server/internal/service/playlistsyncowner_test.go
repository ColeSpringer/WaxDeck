package service

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/colespringer/waxbin/source"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

// listingSource can list a playlist in full, which is all the sync
// sweeper asks of a provider before it reads the due bindings.
type listingSource struct{ onceSource }

func (listingSource) PlaylistSnapshot(context.Context, string, syncsource.SnapshotOptions) (*syncsource.PlaylistSnapshot, error) {
	return nil, errors.New("not used")
}

// syncOwner opens an account, pending or not, and a playlist of its own
// bound to a source whose interval has run out.
func syncOwner(t *testing.T, ctx context.Context, svc *Library, name string, pending bool) (userID, apiPlaylistPID string) {
	t.Helper()
	acct, uc := memberAs(t, ctx, svc, AccountCreate{Username: name, Pending: pending})
	apiPlaylistPID = playlistAs(t, ctx, svc, uc, name+"'s tapes", "private", nil)
	_, bare, _ := parseAPIPID(apiPlaylistPID)
	now := time.Now().UnixNano()
	if err := svc.db.PutPlaylistSource(ctx, wdb.PlaylistSourceRow{
		PlaylistPID: string(bare), Source: "youtube", Live: true,
		URL: "https://tube.example/playlist?list=" + name, IdentityKey: "youtube:" + name,
		SourceID: name, Title: "Road Tapes", Mode: "append", IntervalHours: 1,
		CreatedAtNS: now, UpdatedAtNS: now,
	}); err != nil {
		t.Fatal(err)
	}
	return acct.User.ID, apiPlaylistPID
}

// The sweep queues a due binding's sync under the playlist's owner, and
// queues nothing for an owner who cannot sign in: the same question every
// other path that acts for an account asks, pending accounts included.
func TestTheSyncSweepQueuesOnlyForAnOwnerWhoCanSignIn(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixtureWith(t, catalogFixtureOptions{sources: []source.Provider{listingSource{}}})
	live, livePlaylist := syncOwner(t, ctx, svc, "live", false)
	disabled, disabledPlaylist := syncOwner(t, ctx, svc, "disabled", false)
	_, pendingPlaylist := syncOwner(t, ctx, svc, "pending", true)
	off := true
	if _, err := svc.Identity.UpdateAccount(ctx, disabled, AccountUpdate{Disabled: &off}); err != nil {
		t.Fatal(err)
	}

	svc.Playlists.SyncDuePlaylistSources(ctx)

	task, err := svc.db.ActiveToolTask(ctx, taskTypePlaylistSync, livePlaylist)
	if err != nil {
		t.Fatalf("the live owner's sync = %v, want it queued", err)
	}
	if task.UserID != live {
		t.Errorf("the sync runs for %q, want its owner %q", task.UserID, live)
	}
	for who, playlist := range map[string]string{"disabled": disabledPlaylist, "pending": pendingPlaylist} {
		if _, err := svc.db.ActiveToolTask(ctx, taskTypePlaylistSync, playlist); !errors.Is(err, wdb.ErrNotFound) {
			t.Errorf("a %s owner's sync = %v, want none queued", who, err)
		}
	}
}

// A sync whose owner is gone or disabled has nobody to run for, which no
// retry changes.
func TestAPlaylistSyncWithoutItsOwnerFailsForGood(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	disabled, _ := playlistMember(t, ctx, svc, "disabled")
	off := true
	if _, err := svc.Identity.UpdateAccount(ctx, disabled.User.ID, AccountUpdate{Disabled: &off}); err != nil {
		t.Fatal(err)
	}
	for who, id := range map[string]string{"disabled": disabled.User.ID, "deleted": "us-nobody"} {
		_, err := svc.Playlists.runPlaylistSync(ctx, &wdb.ToolTask{UserID: id}, toolTaskParams{})
		if !permanentToolErr(err) {
			t.Errorf("a sync for a %s owner = %v, want a failure no retry is owed", who, err)
		}
	}
}

// A failed read of the owner says nothing about the account. A run cut
// off there, as by the server stopping, is left to run again rather than
// failed for good under a reason that is not true.
func TestAPlaylistSyncRunsAgainAfterAFailedOwnerRead(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	stopping, stop := context.WithCancel(ctx)
	stop()
	_, err := svc.Playlists.runPlaylistSync(stopping, &wdb.ToolTask{UserID: admin.ID}, toolTaskParams{})
	if err == nil {
		t.Fatal("a sync whose owner could not be read finished clean")
	}
	if permanentToolErr(err) {
		t.Fatalf("a failed read of the owner = %v, which fails the task for good", err)
	}
}

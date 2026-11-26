package service

import (
	"context"
	"errors"
	"net"
	"os"
	"strings"
	"syscall"
	"testing"
	"time"

	"github.com/colespringer/waxbin/source"
	catalogerr "github.com/colespringer/waxbin/waxerr"
	waxtap "github.com/colespringer/waxtap/v3"

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

// refusingLister lists no playlist: every snapshot fails with err.
type refusingLister struct {
	onceSource
	err error
}

func (s refusingLister) PlaylistSnapshot(context.Context, string, syncsource.SnapshotOptions) (*syncsource.PlaylistSnapshot, error) {
	return nil, s.err
}

// Binding a playlist to a link the source refuses says why, and binds
// nothing; its dry run says the same. A failure the classifier cannot name
// is no refusal of the link: it answers as any other failure does.
func TestBindingALinkTheSourceRefusesSaysWhy(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name   string
		err    error
		kind   ErrorKind
		reason string
	}{
		{"private", catalogerr.Wrap(catalogerr.CodeIO, "snapshot", &waxtap.PlaylistUnavailableError{Reason: "This playlist is private."}), KindRefused, "playlist-unavailable"},
		{"empty", waxtap.ErrPlaylistEmpty, KindRefused, "playlist-empty"},
		{"throttled", &waxtap.RateLimitError{StatusCode: 429}, KindRefused, "rate-limited"},
		{"connection dropped", &net.OpError{Op: "read", Net: "tcp", Err: os.NewSyscallError("read", syscall.ECONNRESET)}, KindRefused, "unreachable"},
		{"stub", &syncsource.Refusal{Reason: "playlist-unavailable"}, KindRefused, "playlist-unavailable"},
		{"unnamed", errors.New("the bridge said something new"), KindInternal, ""},
		{"unnamed catalog refusal", catalogerr.Wrap(catalogerr.CodeInvalid, "snapshot", errors.New("bad page")), KindInvalid, ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, _ := newCatalogFixtureWith(t, catalogFixtureOptions{sources: []source.Provider{refusingLister{err: tc.err}}})
			svc.lookupHost = func(context.Context, string) ([]net.IPAddr, error) {
				return []net.IPAddr{{IP: net.ParseIP("203.0.113.7")}}, nil
			}
			_, uc := playlistMember(t, ctx, svc, "binder")
			pid := playlistAs(t, ctx, svc, uc, "Bound", "private", nil)
			in := PlaylistSourceUpdateDTO{URL: "https://tube.example/playlist?list=PLprivate", Mode: "append", IntervalHours: 24, NamesSource: true}
			_, bindErr := svc.Playlists.SetPlaylistSource(ctx, uc, pid, in)
			_, previewErr := svc.Playlists.PreviewPlaylistSync(ctx, uc, pid, &in)
			for what, err := range map[string]error{"bind": bindErr, "preview": previewErr} {
				if KindOf(err) != tc.kind {
					t.Errorf("%s = %v (%s), want %s", what, err, KindOf(err), tc.kind)
				}
				if got := RefusalParams(err)["reason"]; got != tc.reason {
					t.Errorf("%s reason = %q, want %q", what, got, tc.reason)
				}
			}
			_, bare, _ := parseAPIPID(pid)
			if _, err := svc.db.PlaylistSourceFor(ctx, string(bare)); !errors.Is(err, wdb.ErrNotFound) {
				t.Errorf("a refused bind stored a binding: %v", err)
			}
		})
	}
}

// A link to a single video is no playlist to sync: the bind and its dry
// run say so in words of their own, before the source is asked, and bind
// nothing.
func TestBindingAVideoLinkSaysItNeedsAList(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixtureWith(t, catalogFixtureOptions{sources: []source.Provider{refusingLister{err: errors.New("asked")}}})
	svc.lookupHost = func(context.Context, string) ([]net.IPAddr, error) {
		return []net.IPAddr{{IP: net.ParseIP("203.0.113.7")}}, nil
	}
	_, uc := playlistMember(t, ctx, svc, "binder")
	pid := playlistAs(t, ctx, svc, uc, "Bound", "private", nil)
	in := PlaylistSourceUpdateDTO{URL: "https://tube.example/watch?v=one", Mode: "append", IntervalHours: 24, NamesSource: true}
	_, bindErr := svc.Playlists.SetPlaylistSource(ctx, uc, pid, in)
	_, previewErr := svc.Playlists.PreviewPlaylistSync(ctx, uc, pid, &in)
	for what, err := range map[string]error{"bind": bindErr, "preview": previewErr} {
		if KindOf(err) != KindInvalid || !strings.Contains(err.Error(), "single video") {
			t.Errorf("%s = %v (%s), want invalid-request naming the single video", what, err, KindOf(err))
		}
	}
	_, bare, _ := parseAPIPID(pid)
	if _, err := svc.db.PlaylistSourceFor(ctx, string(bare)); !errors.Is(err, wdb.ErrNotFound) {
		t.Errorf("a video link bound: %v", err)
	}
}

// uncheckableLister lists any playlist but cannot say whether it reads a
// link, for a reason it does not name.
type uncheckableLister struct{ onceSource }

func (uncheckableLister) LinkShape(string, bool) (string, error) {
	return "", errors.New("the link checker broke")
}

func (uncheckableLister) PlaylistSnapshot(context.Context, string, syncsource.SnapshotOptions) (*syncsource.PlaylistSnapshot, error) {
	return &syncsource.PlaylistSnapshot{ID: "PLunchecked", IdentityKey: "youtube:PLunchecked", Title: "Unchecked"}, nil
}

// A bind whose check of the link alone fails for a reason the classifier
// cannot name binds nothing, and says so as any other failure does.
func TestBindingALinkNoSourceCouldCheckBindsNothing(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixtureWith(t, catalogFixtureOptions{sources: []source.Provider{uncheckableLister{}}})
	svc.lookupHost = func(context.Context, string) ([]net.IPAddr, error) {
		return []net.IPAddr{{IP: net.ParseIP("203.0.113.7")}}, nil
	}
	_, uc := playlistMember(t, ctx, svc, "binder")
	pid := playlistAs(t, ctx, svc, uc, "Bound", "private", nil)
	in := PlaylistSourceUpdateDTO{URL: "https://tube.example/playlist?list=PLunchecked", Mode: "append", IntervalHours: 24, NamesSource: true}
	_, bindErr := svc.Playlists.SetPlaylistSource(ctx, uc, pid, in)
	_, previewErr := svc.Playlists.PreviewPlaylistSync(ctx, uc, pid, &in)
	for what, err := range map[string]error{"bind": bindErr, "preview": previewErr} {
		if KindOf(err) != KindInternal {
			t.Errorf("%s = %v (%s), want internal", what, err, KindOf(err))
		}
	}
	_, bare, _ := parseAPIPID(pid)
	if _, err := svc.db.PlaylistSourceFor(ctx, string(bare)); !errors.Is(err, wdb.ErrNotFound) {
		t.Errorf("an unchecked link bound: %v", err)
	}
}

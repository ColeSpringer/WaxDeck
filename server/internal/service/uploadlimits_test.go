package service

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"strconv"
	"strings"
	"testing"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// The three ceilings a session meets before a byte moves: the caller's
// quota (covered by the API suite), the per-session maximum, and the
// room left on the staging volume.
//
// The volume is the one nothing else can reach - a test cannot fill a
// disk - so [Library.stagingFree] is a field, and these hand it the
// answers a full one would give.

// uploadFixture is a Library with no library roots at all: nothing here
// scans or imports, it only opens sessions and is refused.
func uploadFixture(t *testing.T) (context.Context, *Library, *UserCtx) {
	t.Helper()
	return uploadFixtureFormats(t, nil)
}

// uploadFixtureFormats is uploadFixture under an operator's own format
// set, for the tests about the gate that set configures.
func uploadFixtureFormats(t *testing.T, formats []string) (context.Context, *Library, *UserCtx) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))

	dataDir := t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{DataDir: dataDir, UploadFormats: formats, Logger: log}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "uploader", Password: "correct-horse", Roles: []string{"admin"},
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return ctx, svc, uc
}

// open declares a session of size bytes.
func openSession(ctx context.Context, svc *Library, uc *UserCtx, name string, size int64) (UploadDTO, error) {
	return svc.CreateUpload(ctx, uc, UploadCreateParams{
		FileName: name, SizeBytes: size, MediaType: "music",
	})
}

// openSessionErr is openSession for the cases that are about the
// refusal rather than the session.
func openSessionErr(ctx context.Context, svc *Library, uc *UserCtx, name string, size int64) error {
	_, err := openSession(ctx, svc, uc, name, size)
	return err
}

func TestCreateUploadRefusesPastTheSessionCeiling(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := uploadFixture(t)
	// Room enough that only the ceiling can be what refuses.
	svc.stagingFree = func(string) (int64, bool) { return 1 << 62, true }

	err := openSessionErr(ctx, svc, uc, "huge.flac", MaxUploadSize+1)
	if KindOf(err) != KindInvalid {
		t.Fatalf("a session over the ceiling errored %v (kind %q), want invalid-request", err, KindOf(err))
	}
	// And it says which limit. Nothing the caller or the operator can
	// free moves this one, so a client that renders the code alone
	// sends somebody to clear space that will never help.
	if !strings.Contains(err.Error(), strconv.Itoa(MaxUploadSize)) {
		t.Fatalf("the refusal does not name the ceiling: %v", err)
	}
	// The ceiling is checked before the quota, and that order is what
	// keeps the quota arithmetic honest rather than a happy accident:
	// `used + size` is int64, so a declaration near its top would wrap
	// negative and read as under any limit. Pinned by the order, since
	// a session that big never reaches the addition.
	uc.UploadQuotaBytes = 1 << 20
	if e := openSessionErr(ctx, svc, uc, "overflow.flac", 1<<62); KindOf(e) != KindInvalid {
		t.Fatalf("a session claiming 2^62 bytes errored %v (kind %q), want invalid-request", e, KindOf(e))
	}
	uc.UploadQuotaBytes = 0
	if _, err := openSession(ctx, svc, uc, "ordinary.flac", 4096); err != nil {
		t.Fatalf("an ordinary session was refused: %v", err)
	}
}

func TestCreateUploadRefusesWhenStagingHasNoRoom(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := uploadFixture(t)
	const free = stagingReserve + 8<<20
	svc.stagingFree = func(string) (int64, bool) { return free, true }

	// Fits with the reserve left over.
	first, err := openSession(ctx, svc, uc, "fits.flac", 4<<20)
	if err != nil {
		t.Fatalf("a session that fits was refused: %v", err)
	}

	// The second one fits the *free space* just as well - nothing has
	// been written yet - and must still be refused, because the first
	// session has already been promised that room. This is the whole
	// point of counting what is outstanding: without it a hundred
	// sessions that each fit are each accepted.
	_, err = openSession(ctx, svc, uc, "does-not.flac", 5<<20)
	if KindOf(err) != KindStorageFull {
		t.Fatalf("the second session errored %v (kind %q), want storage-full", err, KindOf(err))
	}

	// Deciding the first frees its promise again.
	if err := svc.DeleteUpload(ctx, uc, first.ID); err != nil {
		t.Fatalf("discarding the first session: %v", err)
	}
	if _, err := openSession(ctx, svc, uc, "now-it-does.flac", 5<<20); err != nil {
		t.Fatalf("after the first was discarded, the second was still refused: %v", err)
	}
}

func TestCreateUploadSkipsTheRoomCheckWhenNobodyCanAnswer(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := uploadFixture(t)
	// A platform with no probe, or a staging directory that went away
	// under the server. Refusing every upload on a number nobody could
	// read is worse than the hole this closes.
	svc.stagingFree = func(string) (int64, bool) { return 0, false }

	if _, err := openSession(ctx, svc, uc, "unknowable.flac", 1<<30); err != nil {
		t.Fatalf("a session was refused on an answer the platform never gave: %v", err)
	}
}

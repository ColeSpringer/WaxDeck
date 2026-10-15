package service

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
	"github.com/colespringer/waxdeck/server/internal/testfpcalc"
	"github.com/colespringer/waxlabel/waxerr"
)

// receivedUpload opens a session and sends it a real FLAC whole, so
// all that is left is the complete.
func receivedUpload(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) UploadDTO {
	t.Helper()
	return receivedUploadAsking(t, ctx, svc, uc, false)
}

// receivedUploadAsking is receivedUpload for a session that asks, or
// does not, to be identified.
func receivedUploadAsking(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, identify bool) UploadDTO {
	t.Helper()
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "kept", Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Kept", "ARTIST": "Night Transit"},
	})
	if err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(paths[0])
	if err != nil {
		t.Fatal(err)
	}
	up, err := svc.CreateUpload(ctx, uc, UploadCreateParams{
		FileName: "kept.flac", SizeBytes: int64(len(data)), MediaType: "music", Identify: &identify,
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.AppendUploadData(ctx, uc, up.ID, 0, bytes.NewReader(data)); err != nil {
		t.Fatal(err)
	}
	return up
}

// A complete that went away after promoting the file (a crash, or a
// request the client gave up on mid-import) left the row receiving
// with only the final copy. The retry carries on from it rather than
// calling the bytes unreadable and deleting them.
func TestARetriedCompleteCarriesOnFromThePromotedFile(t *testing.T) {
	ctx, svc, uc := uploadFixture(t)
	up := receivedUpload(t, ctx, svc, uc)
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil {
		t.Fatal(err)
	}
	final := svc.uploadFinalPath(row)
	if err := os.Rename(svc.uploadPartPath(row), final); err != nil {
		t.Fatal(err)
	}
	got, err := svc.CompleteUpload(ctx, uc, up.ID)
	if err != nil {
		t.Fatalf("retried complete: %v", err)
	}
	if got.State != uploadStaged && got.State != uploadImported {
		t.Fatalf("retried complete answered state %q, want it settled", got.State)
	}
	if _, err := svc.db.UploadByID(ctx, up.ID); err != nil {
		t.Fatalf("the session is gone after the retry: %v", err)
	}
	if got.State == uploadStaged {
		if _, err := os.Stat(final); err != nil {
			t.Fatalf("the staged file is gone after the retry: %v", err)
		}
	}
}

// Once every byte is in, a further write changes nothing on disk: after a
// complete that promoted the file and went away, a stray part would be
// taken for the upload and the good file thrown out with it.
func TestAWriteToAFullSessionLeavesItsFilesAlone(t *testing.T) {
	ctx, svc, uc := uploadFixture(t)
	up := receivedUpload(t, ctx, svc, uc)
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(svc.uploadPartPath(row), svc.uploadFinalPath(row)); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.AppendUploadData(ctx, uc, up.ID, row.SizeBytes, bytes.NewReader(nil)); err != nil {
		t.Fatalf("an empty write at the end = %v, want it answered as is", err)
	}
	if _, err := svc.AppendUploadData(ctx, uc, up.ID, row.SizeBytes, bytes.NewReader([]byte{1})); KindOf(err) != KindInvalid {
		t.Fatalf("a byte past the end = %v, want it refused", err)
	}
	if _, err := os.Stat(svc.uploadPartPath(row)); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("a part file is back: %v", err)
	}
	got, err := svc.CompleteUpload(ctx, uc, up.ID)
	if err != nil || (got.State != uploadStaged && got.State != uploadImported) {
		t.Fatalf("the complete after = %+v, %v; want it settled from the promoted file", got, err)
	}
}

// A dead session whose staged bytes could not be removed keeps its row,
// expired, so the janitor removes them later: without the row nothing
// would ever find them.
func TestADeadSessionsBytesThatWouldNotGoAreLeftToTheJanitor(t *testing.T) {
	if os.Geteuid() == 0 {
		t.Skip("root removes what a folder's mode forbids")
	}
	ctx, svc, uc := uploadFixture(t)
	data := []byte("bytes that a declared checksum does not describe")
	up, err := svc.CreateUpload(ctx, uc, UploadCreateParams{
		FileName: "dead.flac", SizeBytes: int64(len(data)), MediaType: "music",
		SHA256: strings.Repeat("0", 64),
	})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := svc.AppendUploadData(ctx, uc, up.ID, 0, bytes.NewReader(data)); err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(svc.stagingDir, up.ID)
	if err := os.Chmod(dir, 0o500); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(dir, 0o700) })
	if _, err := svc.CompleteUpload(ctx, uc, up.ID); !errors.Is(err, ErrChecksumMismatch) {
		t.Fatalf("complete = %v, want the checksum refused", err)
	}
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil {
		t.Fatalf("the row went with its bytes still there: %v", err)
	}
	if row.ExpiresAtNS > time.Now().UnixNano() {
		t.Fatalf("row expires at %d, want it expired for the janitor", row.ExpiresAtNS)
	}
	if err := os.Chmod(dir, 0o700); err != nil {
		t.Fatal(err)
	}
	svc.DrainExpiredUploads(ctx)
	if _, err := os.Stat(dir); !errors.Is(err, fs.ErrNotExist) {
		t.Fatalf("the janitor left the bytes: %v", err)
	}
}

// Two completes of one session never run at once: the second hears the
// first is still at it, and nothing of the session is touched.
func TestAnOverlappingCompleteIsToldToWait(t *testing.T) {
	ctx, svc, uc := uploadFixture(t)
	up := receivedUpload(t, ctx, svc, uc)
	svc.completing.Store(up.ID, struct{}{})
	if _, err := svc.CompleteUpload(ctx, uc, up.ID); KindOf(err) != KindConflict {
		t.Fatalf("overlapping complete = %v, want a conflict", err)
	}
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil {
		t.Fatalf("the session is gone: %v", err)
	}
	if _, err := os.Stat(svc.uploadPartPath(row)); err != nil {
		t.Fatalf("the received bytes are gone: %v", err)
	}
}

// A session a complete is still working on is not discarded under it:
// the complete would go on to open a review entry for bytes already gone.
func TestASessionStillCompletingIsNotDiscarded(t *testing.T) {
	ctx, svc, uc := uploadFixture(t)
	up := receivedUpload(t, ctx, svc, uc)
	svc.completing.Store(up.ID, struct{}{})
	if err := svc.DeleteUpload(ctx, uc, up.ID); KindOf(err) != KindConflict {
		t.Fatalf("discard during a complete = %v, want a conflict", err)
	}
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil {
		t.Fatalf("the session is gone: %v", err)
	}
	if _, err := os.Stat(svc.uploadPartPath(row)); err != nil {
		t.Fatalf("the received bytes are gone: %v", err)
	}
}

// A discard reads the session as a complete that finished just before
// it left it: one that imported stays, with what it grants its
// uploader, and one that opened an entry takes the entry with it.
func TestADiscardReadsWhatAJustFinishedCompleteLeft(t *testing.T) {
	for _, identify := range []bool{false, true} {
		t.Run(fmt.Sprintf("identify %v", identify), func(t *testing.T) {
			ctx, svc, uc := managedUploadFixture(t)
			up := receivedUploadAsking(t, ctx, svc, uc, identify)
			var entryID string
			svc.discardReadHook = func() {
				svc.discardReadHook = nil
				done, err := svc.CompleteUpload(ctx, uc, up.ID)
				if err != nil {
					t.Error(err)
				}
				entryID = done.ReviewEntryID
			}
			err := svc.DeleteUpload(ctx, uc, up.ID)
			row, rerr := svc.db.UploadByID(ctx, up.ID)
			if !identify {
				if KindOf(err) != KindConflict || rerr != nil || row.ItemPID == "" {
					t.Fatalf("discard of a session that imported = %v; row %+v, %v; want a conflict and the session kept", err, row, rerr)
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if e, err := svc.db.ReviewEntryByID(ctx, entryID); err != nil || e.Status == reviewPending {
				t.Fatalf("the session's entry after the discard = %+v, %v; want it gone with the session", e, err)
			}
		})
	}
}

// The janitor reads an expired session as it is when it claims it, so
// an entry a complete opened since its listing is one it waits on while
// a decision holds it.
func TestTheJanitorLeavesAnEntryADecisionHolds(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	up := receivedUploadAsking(t, ctx, svc, uc, true)
	listed, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil {
		t.Fatal(err)
	}
	done, err := svc.CompleteUpload(ctx, uc, up.ID)
	if err != nil {
		t.Fatal(err)
	}
	release, ok := svc.claimEntry(done.ReviewEntryID)
	if !ok {
		t.Fatal("the entry is already claimed")
	}
	defer release()
	if svc.drainExpiredUpload(ctx, listed) {
		t.Fatal("the janitor reclaimed a session whose entry a decision holds")
	}
	e, err := svc.db.ReviewEntryByID(ctx, done.ReviewEntryID)
	if err != nil || e.Status != reviewPending {
		t.Fatalf("entry = %+v, %v; want it still pending", e, err)
	}
	stagedStill(t, ctx, svc, up.ID)
}

// Only bytes that do not read as audio end a session; a request that
// went away or a disk that did not answer says nothing about them.
func TestOnlyUnreadableBytesEndASession(t *testing.T) {
	live := context.Background()
	gone, cancel := context.WithCancel(live)
	cancel()
	for _, c := range []struct {
		name string
		ctx  context.Context
		err  error
		dead bool
	}{
		{"not audio", live, fmt.Errorf("%w: could not identify", waxerr.ErrUnsupportedFormat), true},
		{"damaged", live, fmt.Errorf("%w: bad frame", waxerr.ErrInvalidData), true},
		{"request gone", gone, context.Canceled, false},
		{"request gone mid-parse", gone, fmt.Errorf("%w: bad frame", waxerr.ErrInvalidData), false},
		{"file missing", live, &fs.PathError{Op: "open", Path: filepath.Join("x", "a.part"), Err: fs.ErrNotExist}, false},
		{"disk error", live, &fs.PathError{Op: "read", Path: "a.part", Err: errors.New("input/output error")}, false},
	} {
		if got := unreadableUpload(c.ctx, c.err); got != c.dead {
			t.Errorf("%s: unreadableUpload = %v, want %v", c.name, got, c.dead)
		}
	}
}

// A complete reads a file's two fingerprint forms side by side rather
// than one after the other: each is fpcalc decoding up to two minutes of
// audio inside the request.
func TestACompleteReadsBothFingerprintFormsAtOnce(t *testing.T) {
	ctx, svc, uc := uploadFixture(t)
	bin, calls := testfpcalc.WriteOverlapping(t, testfpcalc.Compressed(2, 30))
	svc.fpcalcPath = bin
	up := receivedUpload(t, ctx, svc, uc)
	if _, err := svc.CompleteUpload(ctx, uc, up.ID); err != nil {
		t.Fatal(err)
	}
	log, err := os.ReadFile(calls)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(log), "-raw") || !testfpcalc.Overlapped(string(log)) {
		t.Fatalf("fpcalc runs:\n%s\nwant the raw and compressed forms read at once", log)
	}
}

// A complete whose fpcalc never finishes gives up on the fingerprint
// after a while, rather than holding the session, and every retry of
// it, for good.
func TestAHungFpcalcDoesNotHoldACompleteForever(t *testing.T) {
	ctx, svc, uc := uploadFixture(t)
	svc.fpcalcPath = testfpcalc.WriteHanging(t)
	svc.fpcalcTimeout = 200 * time.Millisecond
	up := receivedUpload(t, ctx, svc, uc)
	start := time.Now()
	if _, err := svc.CompleteUpload(ctx, uc, up.ID); err != nil {
		t.Fatal(err)
	}
	if took := time.Since(start); took > 20*time.Second {
		t.Fatalf("the complete waited %v on a hung fpcalc", took)
	}
}

// Work detached from the client that asked for it outlives the client,
// and still ends with the server.
func TestUntilShutdownOutlivesTheCallerButNotTheServer(t *testing.T) {
	server, stop := context.WithCancel(context.Background())
	defer stop()
	l := &Library{procCtx: server}
	caller, hangUp := context.WithCancel(context.Background())
	ctx, cancel := l.untilShutdown(caller)
	defer cancel()
	hangUp()
	if ctx.Err() != nil {
		t.Fatal("the work ended with its caller")
	}
	stop()
	select {
	case <-ctx.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the work outlived the server")
	}
}

// A one-file entry is planned once: the check that keeps a unit from
// landing in part hands the import the plan it made, rather than the
// import hashing the whole file's audio a second time.
func TestAOneFileImportPlansItsFileOnce(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	plans := 0
	svc.planHook = func(ctx context.Context, f waxbin.AcquiredFile, kind model.Kind, meta waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
		// The import's plans move the file; the completion's duplicate
		// check copies, and is not the import's.
		if !meta.Copy {
			plans++
		}
		return svc.lib.ImportAcquired(ctx, f, kind, meta)
	}
	up := receivedUpload(t, ctx, svc, uc)
	got, err := svc.CompleteUpload(ctx, uc, up.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.State != uploadImported {
		t.Fatalf("upload state = %q, want it imported", got.State)
	}
	if plans != 1 {
		t.Fatalf("the import planned its one file %d times, want once", plans)
	}
}

// managedUploadFixture is uploadFixture with a managed library, where a
// decided upload's files go, and any other roots named.
func managedUploadFixture(t *testing.T, others ...Root) (context.Context, *Library, *UserCtx) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	dataDir := t.TempDir()
	store, err := wdb.Open(ctx, filepath.Join(dataDir, "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	roots := append([]Root{{Name: "lib", Path: t.TempDir(), Managed: true}}, others...)
	svc, err := Open(ctx, Config{DataDir: dataDir, Roots: roots, Logger: log}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "admin", Password: "correct-horse", Roles: []string{"admin"}})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return ctx, svc, uc
}

// pendingUploadEntry completes an upload that asks to be identified, so
// its review entry waits for a decision, and answers the entry's id.
func pendingUploadEntry(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) (UploadDTO, string) {
	t.Helper()
	up := receivedUploadAsking(t, ctx, svc, uc, true)
	if _, err := svc.CompleteUpload(ctx, uc, up.ID); err != nil {
		t.Fatal(err)
	}
	row, err := svc.db.UploadByID(ctx, up.ID)
	if err != nil {
		t.Fatal(err)
	}
	if row.ReviewEntryID == "" {
		t.Fatal("the completed upload opened no review entry")
	}
	return up, row.ReviewEntryID
}

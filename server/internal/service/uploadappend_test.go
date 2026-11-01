package service

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// meetReader holds its first Read until the other reader sharing its meeting
// has reached its own, or a short wait passes. Unserialized appends both get
// past the offset check before either writes; serialized ones never meet,
// and the wait is what lets the first go on.
type meetReader struct {
	r       *bytes.Reader
	meeting *meeting
	once    sync.Once
}

type meeting struct {
	arrived atomic.Int32
	met     chan struct{}
}

func newMeeting() *meeting { return &meeting{met: make(chan struct{})} }

func (m *meetReader) Read(p []byte) (int, error) {
	m.once.Do(func() {
		if m.meeting.arrived.Add(1) == 2 {
			close(m.meeting.met)
		}
		select {
		case <-m.meeting.met:
		case <-time.After(300 * time.Millisecond):
		}
	})
	return m.r.Read(p)
}

// hookReader runs hook before its first byte, while the append reading it
// holds its turn.
type hookReader struct {
	r    *bytes.Reader
	hook func()
	once sync.Once
}

func (h *hookReader) Read(p []byte) (int, error) {
	h.once.Do(h.hook)
	return h.r.Read(p)
}

func TestConcurrentAppendsAtOneOffsetLeaveExactlyOneWinner(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := uploadFixture(t)
	const size = 64
	sess, err := openSession(ctx, svc, uc, "race.flac", size)
	if err != nil {
		t.Fatal(err)
	}

	chunks := [2][]byte{bytes.Repeat([]byte{'a'}, size/2), bytes.Repeat([]byte{'b'}, size/2)}
	meet := newMeeting()
	var wg sync.WaitGroup
	errs := make([]error, len(chunks))
	for i := range chunks {
		wg.Add(1)
		go func() {
			defer wg.Done()
			body := &meetReader{r: bytes.NewReader(chunks[i]), meeting: meet}
			_, errs[i] = svc.AppendUploadData(ctx, uc, sess.ID, 0, body)
		}()
	}
	wg.Wait()

	winner := -1
	for i, err := range errs {
		switch {
		case err == nil && winner == -1:
			winner = i
		case err == nil:
			t.Fatalf("both appends at offset 0 succeeded")
		case KindOf(err) != KindConflict:
			t.Fatalf("append %d errored %v (kind %q), want conflict", i, err, KindOf(err))
		}
	}
	if winner == -1 {
		t.Fatalf("neither append succeeded: %v", errs)
	}

	got, err := svc.GetUpload(ctx, uc, sess.ID)
	if err != nil {
		t.Fatal(err)
	}
	if got.ReceivedBytes != int64(len(chunks[winner])) {
		t.Fatalf("received %d bytes, want %d", got.ReceivedBytes, len(chunks[winner]))
	}
	row, err := svc.db.UploadByID(ctx, sess.ID)
	if err != nil {
		t.Fatal(err)
	}
	part, err := os.ReadFile(svc.uploadPartPath(row))
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(part, chunks[winner]) {
		t.Fatalf("part file holds %q, want the winner's %q", part, chunks[winner])
	}
}

// The advance's compare-and-set is the backstop for a writer the session
// lock does not cover.
func TestAppendLosingTheAdvanceAnswersConflict(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := uploadFixture(t)
	sess, err := openSession(ctx, svc, uc, "backstop.flac", 64)
	if err != nil {
		t.Fatal(err)
	}

	body := &hookReader{r: bytes.NewReader(bytes.Repeat([]byte{'a'}, 16)), hook: func() {
		if moved, err := svc.db.AdvanceUploadReceived(ctx, sess.ID, 0, 5, time.Now().UnixNano()); err != nil || !moved {
			t.Errorf("moving the count underneath the append = (%v, %v)", moved, err)
		}
	}}
	_, err = svc.AppendUploadData(ctx, uc, sess.ID, 0, body)
	if KindOf(err) != KindConflict {
		t.Fatalf("append errored %v (kind %q), want conflict", err, KindOf(err))
	}
	if want := "offset 0 does not match the 5 bytes received; resume there"; err.Error() != want {
		t.Fatalf("conflict says %q, want %q", err.Error(), want)
	}
}

// failingReader hands over its bytes, then fails as a dropped connection
// does.
type failingReader struct{ r *bytes.Reader }

func (f *failingReader) Read(p []byte) (int, error) {
	if f.r.Len() == 0 {
		return 0, errors.New("connection reset")
	}
	return f.r.Read(p)
}

// A session's idleness is the server's own: none while a chunk's bytes are
// arriving, otherwise the time since the last one arrived, kept or not.
func TestASessionsIdlenessIsTheServers(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := uploadFixture(t)
	sess, err := openSession(ctx, svc, uc, "pace.flac", 64)
	if err != nil {
		t.Fatal(err)
	}
	if sess.Idle < 0 || sess.Idle > time.Minute {
		t.Fatalf("a new session idle for %v, want next to none", sess.Idle)
	}
	read := func() time.Duration {
		t.Helper()
		got, err := svc.GetUpload(ctx, uc, sess.ID)
		if err != nil {
			t.Fatal(err)
		}
		return got.Idle
	}
	// Quiet for ten minutes, as far as the row says.
	quiet := func() {
		t.Helper()
		row, err := svc.db.UploadByID(ctx, sess.ID)
		if err != nil {
			t.Fatal(err)
		}
		if moved, err := svc.db.AdvanceUploadReceived(ctx, sess.ID, row.ReceivedBytes, row.ReceivedBytes,
			time.Now().Add(-10*time.Minute).UnixNano()); err != nil || !moved {
			t.Fatalf("backdating = (%v, %v)", moved, err)
		}
	}
	quiet()
	if idle := read(); idle < 10*time.Minute {
		t.Fatalf("idle %v, want the ten minutes since the last bytes", idle)
	}

	// While a chunk's body is arriving the session is not idle, however
	// long ago bytes were last kept.
	reached, release := make(chan struct{}), make(chan struct{})
	body := &hookReader{r: bytes.NewReader(bytes.Repeat([]byte{'a'}, 16)), hook: func() {
		close(reached)
		<-release
	}}
	done := make(chan error, 1)
	go func() {
		_, err := svc.AppendUploadData(ctx, uc, sess.ID, 0, body)
		done <- err
	}()
	<-reached
	if idle := read(); idle != 0 {
		t.Errorf("idle %v while a chunk arrives, want none", idle)
	}
	close(release)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	if idle := read(); idle > time.Minute {
		t.Fatalf("idle %v after a chunk was kept, want next to none", idle)
	}

	// Bytes that arrive on a chunk that then fails still count.
	quiet()
	if _, err := svc.AppendUploadData(ctx, uc, sess.ID, 16, &failingReader{r: bytes.NewReader([]byte("bbbb"))}); err == nil {
		t.Fatal("a chunk whose connection dropped was accepted")
	}
	if idle := read(); idle > time.Minute {
		t.Fatalf("idle %v after bytes arrived on a failed chunk, want next to none", idle)
	}
	if got, err := svc.GetUpload(ctx, uc, sess.ID); err != nil || got.ReceivedBytes != 16 {
		t.Fatalf("received %d (%v), want the 16 kept before", got.ReceivedBytes, err)
	}

	// A chunk refused before its body is read leaves the idleness alone.
	quiet()
	if _, err := svc.AppendUploadData(ctx, uc, sess.ID, 0, bytes.NewReader([]byte{'c'})); KindOf(err) != KindConflict {
		t.Fatalf("a chunk at a stale offset = %v, want conflict", err)
	}
	if idle := read(); idle < 10*time.Minute {
		t.Fatalf("idle %v after a refused chunk, want the ten minutes", idle)
	}
}

// A session reads as taking bytes from the first of a chunk's body until
// the chunk is counted on its row, whatever becomes of it: between the last
// byte and the stamp the row still holds the stamp from before, and a read
// there would call a slow chunk's session idle.
func TestASessionStaysLiveUntilItsChunkIsCounted(t *testing.T) {
	t.Parallel()
	cases := []struct {
		name string
		body func() io.Reader
		// counted is whether bytes arrived, so the stamp moves to now.
		counted bool
	}{
		{"kept", func() io.Reader { return bytes.NewReader(bytes.Repeat([]byte{'a'}, 16)) }, true},
		{"failed after bytes", func() io.Reader { return &failingReader{r: bytes.NewReader([]byte("bbbb"))} }, true},
		{"failed before any", func() io.Reader { return &failingReader{r: bytes.NewReader(nil)} }, false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc := uploadFixture(t)
			sess, err := openSession(ctx, svc, uc, "slow.flac", 64)
			if err != nil {
				t.Fatal(err)
			}
			// The last bytes were ten minutes ago.
			if moved, err := svc.db.AdvanceUploadReceived(ctx, sess.ID, 0, 0,
				time.Now().Add(-10*time.Minute).UnixNano()); err != nil || !moved {
				t.Fatalf("backdating = (%v, %v)", moved, err)
			}
			idle := func() time.Duration {
				t.Helper()
				got, err := svc.GetUpload(ctx, uc, sess.ID)
				if err != nil {
					t.Fatal(err)
				}
				return got.Idle
			}

			// Parked once the body is read and before it is counted.
			reached, release := make(chan struct{}), make(chan struct{})
			svc.bodyReadHook = func() {
				close(reached)
				<-release
			}
			began := time.Now()
			done := make(chan struct{})
			go func() {
				defer close(done)
				_, _ = svc.AppendUploadData(ctx, uc, sess.ID, 0, tc.body())
			}()
			select {
			case <-reached:
			case <-time.After(10 * time.Second):
				t.Fatal("the append never read its body")
			}
			if got := idle(); tc.counted && got > time.Since(began) {
				t.Errorf("idle %v between a chunk's last byte and its stamp, want no more than the %v since it began",
					got, time.Since(began))
			}
			close(release)
			<-done

			// Counted, or not, it is settled: the session is live no longer.
			if svc.appendLocks.live(sess.ID) {
				t.Error("the session still reads as taking bytes after the append ended")
			}
			got := idle()
			if tc.counted && got > time.Minute {
				t.Errorf("idle %v after bytes arrived, want next to none", got)
			}
			if !tc.counted && got < 10*time.Minute {
				t.Errorf("idle %v after a chunk with no bytes, want the ten minutes", got)
			}
		})
	}
}

func TestAppendToASessionDiscardedMidChunkAnswersConflict(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := uploadFixture(t)
	sess, err := openSession(ctx, svc, uc, "gone.flac", 64)
	if err != nil {
		t.Fatal(err)
	}

	body := &hookReader{r: bytes.NewReader(bytes.Repeat([]byte{'a'}, 16)), hook: func() {
		row, err := svc.db.UploadByID(ctx, sess.ID)
		if err != nil {
			t.Error(err)
			return
		}
		row.State = uploadDiscarded
		if err := svc.db.UpdateUpload(ctx, row); err != nil {
			t.Error(err)
		}
	}}
	_, err = svc.AppendUploadData(ctx, uc, sess.ID, 0, body)
	if KindOf(err) != KindConflict || !strings.Contains(err.Error(), "no longer receiving") {
		t.Fatalf("append errored %v (kind %q), want the no-longer-receiving conflict", err, KindOf(err))
	}
}

func TestSessionLockWaiterLeavesWithItsContext(t *testing.T) {
	t.Parallel()
	var locks sessionLocks
	// Bounded, so a lock that wrongly holds fails the test instead of hanging it.
	bg, stopBg := context.WithTimeout(context.Background(), 5*time.Second)
	defer stopBg()
	release, err := locks.acquire(bg, "up-1")
	if err != nil {
		t.Fatal(err)
	}

	// Another session is not held up by it.
	other, err := locks.acquire(bg, "up-2")
	if err != nil {
		t.Fatal(err)
	}
	other()

	ctx, cancel := context.WithCancel(bg)
	waiter := newWaitingCtx(ctx)
	got := make(chan error, 1)
	go func() {
		_, err := locks.acquire(waiter, "up-1")
		got <- err
	}()
	// Cancelled only once the waiter is queued and waiting on its context,
	// so a lock that reads the context on the way in and not while it
	// waits fails here.
	waitQueued(t, bg, &locks, "up-1", 2)
	select {
	case <-waiter.waiting:
	case <-bg.Done():
		t.Fatal("the waiter never waited on its context")
	}
	cancel()
	select {
	case err := <-got:
		if !errors.Is(err, context.Canceled) {
			t.Fatalf("a waiter whose context ended got %v, want context.Canceled", err)
		}
	case <-bg.Done():
		t.Fatal("a waiter whose context ended stayed queued")
	}

	// The holder still holds: a fresh waiter cannot get in until release.
	tight, stop := context.WithTimeout(bg, 20*time.Millisecond)
	defer stop()
	go func() {
		_, err := locks.acquire(tight, "up-1")
		got <- err
	}()
	select {
	case err := <-got:
		if !errors.Is(err, context.DeadlineExceeded) {
			t.Fatalf("a second holder got in while the first held: %v", err)
		}
	case <-bg.Done():
		t.Fatal("a waiter whose deadline passed stayed queued")
	}

	release()
	again, err := locks.acquire(bg, "up-1")
	if err != nil {
		t.Fatal(err)
	}
	again()
	if n := len(locks.entries); n != 0 {
		t.Fatalf("%d lock entries left behind", n)
	}
}

// waitQueued waits until id's lock is referenced by want holders and
// waiters together.
func waitQueued(t *testing.T, ctx context.Context, locks *sessionLocks, id string, want int) {
	t.Helper()
	for {
		locks.mu.Lock()
		refs := 0
		if e := locks.entries[id]; e != nil {
			refs = e.refs
		}
		locks.mu.Unlock()
		if refs == want {
			return
		}
		select {
		case <-ctx.Done():
			t.Fatalf("%s has %d references, want %d", id, refs, want)
		case <-time.After(time.Millisecond):
		}
	}
}

// waitingCtx closes waiting the first time its Done is read, which
// acquire does only as it starts to wait: on entering its select.
type waitingCtx struct {
	context.Context
	once    sync.Once
	waiting chan struct{}
}

func newWaitingCtx(parent context.Context) *waitingCtx {
	return &waitingCtx{Context: parent, waiting: make(chan struct{})}
}

func (c *waitingCtx) Done() <-chan struct{} {
	c.once.Do(func() { close(c.waiting) })
	return c.Context.Done()
}

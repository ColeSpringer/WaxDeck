package supervise

import (
	"context"
	"testing"
	"time"
)

// The shutdown shape that used to panic: teardown is itself supervised,
// so a worker spawned while Wait is already blocked must be counted and
// waited on, not tripped over as sync.WaitGroup's Add-during-Wait.
func TestWaitAcceptsWorkSpawnedMeanwhile(t *testing.T) {
	t.Parallel()
	g := NewGroup(nil)
	ctx := context.Background()
	firstRunning := make(chan struct{})
	release := make(chan struct{})
	releaseSecond := make(chan struct{})
	g.GoOnce(ctx, "first", func(context.Context) error {
		close(firstRunning)
		<-release
		// Spawned with Wait already blocked below. The count moves up
		// before this worker's own exit moves it down, so Wait cannot
		// see zero in between.
		g.GoOnce(ctx, "second", func(context.Context) error {
			<-releaseSecond
			return nil
		})
		return nil
	})
	<-firstRunning
	waited := make(chan struct{})
	go func() {
		g.Wait()
		close(waited)
	}()
	select {
	case <-waited:
		t.Fatal("Wait returned with a worker still running")
	case <-time.After(20 * time.Millisecond):
	}
	close(release)
	select {
	case <-waited:
		t.Fatal("Wait returned while the mid-wait spawn was still running")
	case <-time.After(20 * time.Millisecond):
	}
	close(releaseSecond)
	select {
	case <-waited:
	case <-time.After(5 * time.Second):
		t.Fatal("Wait never returned")
	}
}

// A context already canceled is refused outright, so a request racing
// shutdown cannot spawn work after the group has been waited out.
func TestRefusesACanceledContext(t *testing.T) {
	t.Parallel()
	g := NewGroup(nil)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if g.Go(ctx, "late", func(context.Context) error { return nil }) {
		t.Fatal("Go accepted a canceled context")
	}
	if g.GoOnce(ctx, "late", func(context.Context) error { return nil }) {
		t.Fatal("GoOnce accepted a canceled context")
	}
	g.Wait()
}

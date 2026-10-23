package api

import (
	"context"
	"io"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// A waiting task's reason, retry time and book-in-trash flag reach the
// client; a task that does not wait carries none of them.
func TestAWaitingTasksWaitReachesTheClient(t *testing.T) {
	t.Parallel()
	at := time.Date(2026, 10, 22, 12, 0, 0, 0, time.UTC)
	got := toolTaskJSON(service.ToolTaskDTO{ID: "tk-1", Type: "book-merge", State: "running",
		WaitReason: "read-only", RetryAtNS: at.UnixNano(), BookInTrash: true})
	if got.WaitReason == nil || *got.WaitReason != "read-only" || got.RetryAt == nil || !got.RetryAt.Equal(at) ||
		got.BookInTrash == nil || !*got.BookInTrash {
		t.Fatalf("task = %+v, want the wait and the trash said", got)
	}
	plain := toolTaskJSON(service.ToolTaskDTO{ID: "tk-2", Type: "book-merge", State: "running"})
	if plain.WaitReason != nil || plain.RetryAt != nil || plain.BookInTrash != nil {
		t.Fatalf("task = %+v, want no wait said", plain)
	}
}

// A parked task is finished: its event stream says done and ends rather
// than waiting on a task that will not move again.
func TestAParkedTasksEventStreamEnds(t *testing.T) {
	t.Parallel()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	stream := &taskEventStream{ctx: ctx, last: service.ToolTaskDTO{ID: "tk-1", Type: "book-merge", State: "parked"}, started: true}
	out, err := io.ReadAll(stream)
	if err != nil || !strings.Contains(string(out), "event: done") {
		t.Fatalf("stream = %q, %v; want a done event and the end", out, err)
	}
}

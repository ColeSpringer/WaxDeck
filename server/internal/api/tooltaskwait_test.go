package api

import (
	"context"
	"io"
	"maps"
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

// Why a failed task failed reaches the client as a code and its params
// beside the server's sentence; a task that has not failed carries none.
func TestAFailedTasksCodeReachesTheClient(t *testing.T) {
	t.Parallel()
	got := toolTaskJSON(service.ToolTaskDTO{ID: "tk-1", Type: "acquire", State: "failed", Error: "The video is no longer available.",
		ErrorCode: "source-refused", ErrorParams: map[string]string{"reason": "video-unavailable"}})
	if got.ErrorCode == nil || *got.ErrorCode != "source-refused" || got.ErrorParams == nil ||
		!maps.Equal(*got.ErrorParams, map[string]string{"reason": "video-unavailable"}) {
		t.Fatalf("task = %+v, want the code and its reason said", got)
	}
	plain := toolTaskJSON(service.ToolTaskDTO{ID: "tk-2", Type: "acquire", State: "done"})
	if plain.ErrorCode != nil || plain.ErrorParams != nil {
		t.Fatalf("task = %+v, want no code said", plain)
	}
}

// A failure the server cannot classify waits in view as "other", saying
// what it was, rather than leaving the task running in silence.
func TestAnUnclassifiedFailureWaitsInView(t *testing.T) {
	t.Parallel()
	const link = "https://tube.example/watch?v=lone"
	src := &fakeAcquireSource{files: map[string]string{}}
	cannedFiles(t, src, map[string]map[string]string{link: {"TITLE": "Lone", "ARTIST": "Someone"}})
	h := acquiringHarness(t, src)
	if _, err := h.store.Writer().ExecContext(context.Background(), `CREATE TRIGGER refuse_upload BEFORE INSERT ON uploads
		BEGIN SELECT RAISE(ABORT, 'the disk hiccuped'); END`); err != nil {
		t.Fatal(err)
	}
	task := decodeStatus[ToolTask](t, h.postJSON(t, "/api/v1/acquisitions", map[string]any{"url": link, "mediaType": "music"}), 202, "acquisition")
	if !h.svc.Tools.DrainSourceToolTasks(context.Background()) {
		t.Fatal("the worker found no task to run")
	}
	got := decode[ToolTask](t, get(t, h.ts, "/api/v1/tools/tasks/"+task.Id, h.token))
	if got.State != "running" || got.WaitReason == nil || *got.WaitReason != "other" || got.RetryAt == nil ||
		got.Error == nil || !strings.Contains(*got.Error, "the disk hiccuped") || got.ErrorCode != nil {
		t.Fatalf("task = %+v, want it waiting as other, saying what failed", got)
	}
}

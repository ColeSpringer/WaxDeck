package api

import (
	"testing"
	"time"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// What a running task is doing reaches the client; a count it does not
// know, and bytes for no download, stay out.
func TestARunningTasksActivityReachesTheClient(t *testing.T) {
	t.Parallel()
	at := time.Date(2026, 11, 25, 12, 0, 0, 0, time.UTC)
	got := toolTaskJSON(service.ToolTaskDTO{ID: "tk-1", Type: "acquire", State: "running", Activity: &service.ToolTaskActivity{
		Phase: "downloading", ItemsDone: 0, ItemsTotal: 37, ItemTitle: "Third", BytesDone: 4_200_000, BytesTotal: 9_800_000, AtNS: at.UnixNano(),
	}})
	a := got.Activity
	if a == nil || a.Phase != "downloading" || !a.At.Equal(at) || a.ItemsDone == nil || *a.ItemsDone != 0 ||
		a.ItemsTotal == nil || *a.ItemsTotal != 37 || a.ItemTitle == nil || *a.ItemTitle != "Third" ||
		a.BytesDone == nil || *a.BytesDone != 4_200_000 || a.BytesTotal == nil || *a.BytesTotal != 9_800_000 {
		t.Fatalf("activity = %+v, want everything the task said", a)
	}
	listing := toolTaskJSON(service.ToolTaskDTO{ID: "tk-2", Type: "acquire", State: "running",
		Activity: &service.ToolTaskActivity{Phase: "listing", AtNS: at.UnixNano()}}).Activity
	if listing == nil || listing.ItemsDone != nil || listing.ItemsTotal != nil || listing.ItemTitle != nil ||
		listing.BytesDone != nil || listing.BytesTotal != nil {
		t.Fatalf("listing activity = %+v, want the phase and its time alone", listing)
	}
	if plain := toolTaskJSON(service.ToolTaskDTO{ID: "tk-3", Type: "acquire", State: "queued"}); plain.Activity != nil {
		t.Fatalf("a queued task reads activity %+v", plain.Activity)
	}
}

// The event stream sends moving activity about once every two seconds,
// and a change of phase or state, or a cancel asked, at once.
func TestTheTaskStreamPacesActivity(t *testing.T) {
	t.Parallel()
	sent := time.Date(2026, 11, 25, 12, 0, 0, 0, time.UTC)
	task := func(state, phase string, bytes int64, pct float64) service.ToolTaskDTO {
		return service.ToolTaskDTO{ID: "tk-1", Type: "acquire", State: state, ProgressPct: pct,
			Activity: &service.ToolTaskActivity{Phase: phase, BytesDone: bytes, AtNS: sent.UnixNano() + bytes}}
	}
	last := task("running", "downloading", 1, 10)
	asked := task("running", "downloading", 1, 10)
	asked.CancelRequested = true
	for _, tc := range []struct {
		name  string
		cur   service.ToolTaskDTO
		after time.Duration
		want  bool
	}{
		{"nothing moved", last, 5 * time.Second, false},
		{"bytes moved a second on", task("running", "downloading", 2, 11), time.Second, false},
		{"bytes moved two seconds on", task("running", "downloading", 2, 11), 2 * time.Second, true},
		{"a new phase", task("running", "processing", 1, 10), 100 * time.Millisecond, true},
		{"done", task("done", "downloading", 1, 10), 100 * time.Millisecond, true},
		{"activity gone", service.ToolTaskDTO{ID: "tk-1", Type: "acquire", State: "running", ProgressPct: 10}, 100 * time.Millisecond, true},
		{"asked to cancel", asked, 100 * time.Millisecond, true},
	} {
		s := &taskEventStream{last: last, sentAt: sent}
		if got := s.worthSending(tc.cur, sent.Add(tc.after)); got != tc.want {
			t.Errorf("%s: worth sending = %v, want %v", tc.name, got, tc.want)
		}
	}
}

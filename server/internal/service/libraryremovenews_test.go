package service

import (
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
)

// A library removal's progress is news as it runs: the console sends
// whoever starts one to follow it in Tasks.
func TestARemovalAnnouncesItsProgress(t *testing.T) {
	t.Parallel()
	now := time.Now()
	j := model.Job{Kind: "remove-root", State: model.JobRunning, Progress: 0.1, TargetType: "library"}
	if !jobNews(nil, j, now, 0) {
		t.Fatal("a running removal's first read is no news")
	}
	seen := &jobSeen{state: model.JobRunning, bucket: progressBucket(0.1), at: now}
	j.Progress = 0.6
	if !jobNews(seen, j, now, 0) {
		t.Fatal("a removal's progress is no news")
	}
}

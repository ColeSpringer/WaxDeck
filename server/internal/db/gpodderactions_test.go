package db

import (
	"fmt"
	"slices"
	"strings"
	"testing"
)

// The action log keeps the account's newest actions within the cap,
// trimming them in one range only once a tenth more have piled up, so an
// upload below the margin deletes nothing.
func TestTheActionCapTrimsPastAMargin(t *testing.T) {
	d, ctx := gpodderFixture(t)
	n := 0
	add := func(count int) {
		t.Helper()
		batch := make([]GpodderAction, 0, count)
		for range count {
			batch = append(batch, GpodderAction{UserID: "us-A", PodcastURL: "https://a.example/feed",
				EpisodeURL: fmt.Sprintf("https://a.example/%d.mp3", n), Action: "download", UploadedSec: int64(100 + n)})
			n++
		}
		if _, err := d.AppendGpodderActions(ctx, batch, 10); err != nil {
			t.Fatal(err)
		}
	}
	kept := func() (int, string) {
		t.Helper()
		rows, err := d.GpodderActionsSince(ctx, "us-A", 0, "", "")
		if err != nil || len(rows) == 0 {
			t.Fatalf("actions = %v (%v)", rows, err)
		}
		return len(rows), rows[0].EpisodeURL
	}
	add(10)
	add(1)
	if got, _ := kept(); got != 11 {
		t.Fatalf("one action past the cap of 10 leaves %d, want all 11: the margin is a tenth", got)
	}
	add(1)
	if got, oldest := kept(); got != 10 || oldest != "https://a.example/2.mp3" {
		t.Fatalf("past the margin the log keeps %d from %s, want the newest 10", got, oldest)
	}
}

// The action cap reads and trims an account's actions by seeking their
// number's index, never by walking the account's log, so an upload costs
// the writer the same at the cap as below it.
func TestTheActionCapSeeksItsIndex(t *testing.T) {
	d, _ := gpodderFixture(t)
	for name, q := range map[string]string{"span": gpodderActionSpan, "trim": gpodderDropActions} {
		plan := queryPlan(t, d.r, q, "us-A", "us-A")
		if !strings.Contains(plan, "gpodder_actions_by_user") || strings.Contains(plan, "SCAN gpodder_actions") {
			t.Errorf("%s plan:\n%s\nwant gpodder_actions_by_user searched, never a scan", name, plan)
		}
	}
	plan := queryPlan(t, d.r, gpodderSameAction, "us-A", "https://a.example/1.mp3", "phone", "play", "", nil)
	if !strings.Contains(plan, "gpodder_actions_by_episode") {
		t.Errorf("same-action plan:\n%s\nwant gpodder_actions_by_episode searched", plan)
	}
}

// An action the log already holds is kept once, its row's id answered for
// the copy, whether it comes again in a later batch or twice in one.
func TestAnActionIsKeptOnce(t *testing.T) {
	d, ctx := gpodderFixture(t)
	position := int64(120)
	play := GpodderAction{UserID: "us-A", PodcastURL: "https://a.example/feed", EpisodeURL: "https://a.example/1.mp3",
		DeviceID: "phone", Action: "play", ActionTS: "2026-01-10T08:00:00", PositionSec: &position, UploadedSec: 100}
	download := GpodderAction{UserID: "us-A", PodcastURL: "https://a.example/feed", EpisodeURL: "https://a.example/1.mp3",
		DeviceID: "phone", Action: "download", UploadedSec: 100}
	first, err := d.AppendGpodderActions(ctx, []GpodderAction{play, download}, 10)
	if err != nil {
		t.Fatal(err)
	}
	again, err := d.AppendGpodderActions(ctx, []GpodderAction{download, play, play}, 10)
	if err != nil {
		t.Fatal(err)
	}
	if !slices.Equal(again, []int64{first[1], first[0], first[0]}) {
		t.Fatalf("ids of the copies = %v, want the first batch's %v", again, first)
	}
	if rows, _ := d.GpodderActionsSince(ctx, "us-A", 0, "", ""); len(rows) != 2 {
		t.Fatalf("log = %+v, want each action once", rows)
	}
}

// A stamp a stored action made is that action's while the log keeps it;
// once the cap lets the action go, the stamp is the server's to tell.
func TestAStampIsItsActionsWhileTheLogKeepsIt(t *testing.T) {
	d, ctx := gpodderFixture(t)
	upload := func(episode string) int64 {
		t.Helper()
		ids, err := d.AppendGpodderActions(ctx, []GpodderAction{{UserID: "us-A", PodcastURL: "https://a.example/feed",
			EpisodeURL: episode, Action: "play", UploadedSec: 100}}, 1)
		if err != nil {
			t.Fatal(err)
		}
		return ids[0]
	}
	if err := d.StampPlayState(ctx, "us-A", "ep-1", 1, upload("https://a.example/1.mp3")); err != nil {
		t.Fatal(err)
	}
	fromGpodder := func() bool {
		t.Helper()
		stamps, err := d.PositionStampsAfter(ctx, "us-A", 0, "", 10)
		if err != nil || len(stamps) != 1 {
			t.Fatalf("stamps = %+v (%v)", stamps, err)
		}
		return stamps[0].FromGpodder
	}
	if !fromGpodder() {
		t.Fatal("a stamp whose action the log keeps is not the action's")
	}
	upload("https://a.example/2.mp3")
	if fromGpodder() {
		t.Fatal("a stamp whose action the cap let go is still the action's")
	}
}

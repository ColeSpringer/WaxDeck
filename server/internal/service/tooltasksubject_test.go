package service

import (
	"context"
	"encoding/json"
	"errors"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin"
	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/source"
	catalogerr "github.com/colespringer/waxbin/waxerr"
	waxtap "github.com/colespringer/waxtap/v3"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/syncsource"
)

// summaryEntries is a task summary's entry titles, nil when it has none.
func summaryEntries(t *testing.T, sum map[string]any) []string {
	t.Helper()
	raw, ok := sum["entries"].([]any)
	if !ok {
		return nil
	}
	out := make([]string, 0, len(raw))
	for _, v := range raw {
		s, _ := v.(string)
		out = append(out, s)
	}
	return out
}

// entryTitles is what the review entries named by a task's results are
// called, in its order.
func entryTitles(t *testing.T, ctx context.Context, svc *Library, row wdb.ToolTask) []string {
	t.Helper()
	var ids []string
	if err := json.Unmarshal([]byte(row.ResultPIDs), &ids); err != nil {
		t.Fatal(err)
	}
	out := make([]string, 0, len(ids))
	for _, id := range ids {
		e, err := svc.db.ReviewEntryByID(ctx, id)
		if err != nil {
			t.Fatal(err)
		}
		out = append(out, e.Title)
	}
	return out
}

// An acquisition is queued saying what it is: the link it was given, how
// the link was taken, and the name the check read, when it read one.
func TestAnAcquisitionSaysWhatItIsFromTheStart(t *testing.T) {
	t.Parallel()
	for _, tc := range []struct {
		name, link  string
		playlist    bool
		src         source.Provider
		title, kind string
	}{
		{"a video the check named", "https://tube.example/watch?v=one", false, &probeSource{}, "One Video", "video"},
		{"a list the check named", "https://tube.example/watch?v=one&list=PLtwo", true, &probeSource{}, "The List", "playlist"},
		{"a channel the check did not name", "https://tube.example/@someone", false, onceSource{}, "", "channel"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc := acquireFixture(t, tc.src)
			task, err := svc.Ingest.StartAcquisition(ctx, uc, tc.link, tc.playlist, "music", "", "", nil, nil)
			if err != nil {
				t.Fatal(err)
			}
			for from, dto := range map[string]ToolTaskDTO{"answer": task, "stored": toolTaskDTO(storedTask(t, ctx, svc, task.ID))} {
				if dto.ItemTitle != tc.title || dto.Summary["url"] != tc.link || dto.Summary["source"] != tc.kind {
					t.Errorf("the %s task is titled %q with summary %v, want %q, url %s and source %s",
						from, dto.ItemTitle, dto.Summary, tc.title, tc.link, tc.kind)
				}
			}
		})
	}
}

// An acquisition the check did not name takes its listing's name, and once
// it has run its summary names the review entries it opened, in order.
func TestAnAcquisitionEndsNamingTheEntriesItOpened(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := acquireFixture(t, &stagingSource{})
	const link = "https://tube.example/playlist?list=PLthree"
	task, err := svc.Ingest.StartAcquisition(ctx, uc, link, false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if task.ItemTitle != "" {
		t.Fatalf("queued titled %q, want no title before the listing", task.ItemTitle)
	}
	drainOnce(t, ctx, svc)
	row := storedTask(t, ctx, svc, task.ID)
	dto := toolTaskDTO(row)
	if dto.State != taskStateDone || dto.ItemTitle != "Three" {
		t.Fatalf("task = %s titled %q (error %q), want it done, titled by its listing", dto.State, dto.ItemTitle, dto.Error)
	}
	got, want := summaryEntries(t, dto.Summary), entryTitles(t, ctx, svc, row)
	if !slices.Equal(got, want) || !slices.Equal(got, []string{"one", "two", "three"}) {
		t.Errorf("summary entries %q, want the entries' titles %q in order", got, want)
	}
	if dto.Summary["truncated"] != false || dto.Summary["url"] != link || dto.Summary["source"] != "playlist" {
		t.Errorf("summary %v, want it untruncated and still saying what it was queued for", dto.Summary)
	}
}

// A listing past the cap is cut there, and the summary says so.
func TestAnAcquisitionCutAtTheCapSaysSo(t *testing.T) {
	t.Parallel()
	src := &stagingSource{}
	ctx, svc, uc := acquireFixture(t, src)
	svc.Ingest.acquireItemCap = 2
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	drainOnce(t, ctx, svc)
	dto := toolTaskDTO(storedTask(t, ctx, svc, task.ID))
	if dto.State != taskStateDone || dto.Summary["truncated"] != true || !slices.Equal(summaryEntries(t, dto.Summary), []string{"one", "two"}) {
		t.Fatalf("task = %s with summary %v (error %q), want it done, truncated, naming the two it fetched", dto.State, dto.Summary, dto.Error)
	}
	if n := src.fetchCounts()["https://tube.example/watch?v=three"]; n != 0 {
		t.Errorf("fetched the item past the cap %d times", n)
	}
}

// A listing the source itself stopped at its cap is cut there too, though
// what it listed is within this server's own cap, and the summary says so.
func TestAnAcquisitionTheSourceCutSaysSo(t *testing.T) {
	t.Parallel()
	src := &stagingSource{cut: true}
	ctx, svc, uc := acquireFixture(t, src)
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	drainOnce(t, ctx, svc)
	dto := toolTaskDTO(storedTask(t, ctx, svc, task.ID))
	if dto.State != taskStateDone || dto.Summary["truncated"] != true || len(summaryEntries(t, dto.Summary)) != 3 {
		t.Fatalf("task = %s with summary %v (error %q), want it done, truncated, naming the three listed", dto.State, dto.Summary, dto.Error)
	}
}

// A canceled acquisition names the entries it opened, as a done one does,
// those the cancel itself opens for an earlier run included, and files no
// failure.
func TestACanceledAcquisitionNamesItsEntries(t *testing.T) {
	t.Parallel()
	t.Run("waiting", func(t *testing.T) {
		t.Parallel()
		src := &stagingSource{}
		src.stall.Store(true)
		ctx, svc, uc := acquireFixture(t, src)
		svc.Ingest.acquireItemBound = 300 * time.Millisecond
		task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		drainOnce(t, ctx, svc)
		dto := cancelTask(t, ctx, svc, uc, task.ID)
		if dto.State != taskStateCanceled || !slices.Equal(summaryEntries(t, dto.Summary), []string{"one", "two"}) {
			t.Fatalf("the cancel answered %s with summary %v, want it canceled naming the two entries", dto.State, dto.Summary)
		}
		if got := summaryEntries(t, toolTaskDTO(storedTask(t, ctx, svc, task.ID)).Summary); !slices.Equal(got, []string{"one", "two"}) {
			t.Errorf("stored entries %q, want the two", got)
		}
		if rows := inboxOf(t, ctx, svc, uc, "tool-task-failed"); len(rows) != 0 {
			t.Errorf("a canceled acquisition filed %+v", rows)
		}
	})
	t.Run("stranded", func(t *testing.T) {
		t.Parallel()
		src := &stagingSource{}
		src.answerThree(func(context.Context) error { panic("the run died") })
		ctx, svc, uc := acquireFixture(t, src)
		task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
		if err != nil {
			t.Fatal(err)
		}
		func() {
			defer func() {
				if recover() == nil {
					t.Fatal("the run did not die")
				}
			}()
			drainOnce(t, ctx, svc)
		}()
		cancelTask(t, ctx, svc, uc, task.ID)
		row := storedTask(t, ctx, svc, task.ID)
		if got := summaryEntries(t, toolTaskDTO(row).Summary); row.State != taskStateCanceled || !slices.Equal(got, entryTitles(t, ctx, svc, row)) || len(got) != 2 {
			t.Fatalf("task = %s naming %q, want it canceled naming the two entries the cancel opened", row.State, got)
		}
	})
}

// syncBinding binds a playlist of uc's, named name, to a source listing
// three videos, due at once.
func syncBinding(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, name string) string {
	t.Helper()
	pid := playlistAs(t, ctx, svc, uc, name, "private", nil)
	_, bare, _ := parseAPIPID(pid)
	now := time.Now().UnixNano()
	if err := svc.db.PutPlaylistSource(ctx, wdb.PlaylistSourceRow{
		PlaylistPID: string(bare), Source: "youtube", Live: true,
		URL: "https://tube.example/playlist?list=PLthree", IdentityKey: "youtube:PLthree",
		SourceID: "PLthree", Title: "Three", Mode: "append", IntervalHours: 1,
		CreatedAtNS: now, UpdatedAtNS: now,
	}); err != nil {
		t.Fatal(err)
	}
	return pid
}

// A playlist sync is titled by its playlist, whether it was asked for or
// the sweep queued it.
func TestAPlaylistSyncIsTitledByItsPlaylist(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := acquireFixture(t, &stallingLister{})
	asked := syncBinding(t, ctx, svc, uc, "Asked For")
	task, err := svc.Playlists.SyncPlaylistSourceNow(ctx, uc, asked)
	if err != nil {
		t.Fatal(err)
	}
	if task.ItemTitle != "Asked For" || storedTask(t, ctx, svc, task.ID).ItemTitle != "Asked For" {
		t.Errorf("the sync asked for is titled %q, want its playlist's name", task.ItemTitle)
	}
	due := syncBinding(t, ctx, svc, uc, "Swept Up")
	svc.Playlists.SyncDuePlaylistSources(ctx)
	row, err := svc.db.ActiveToolTask(ctx, taskTypePlaylistSync, due)
	if err != nil {
		t.Fatalf("the sweep queued no sync: %v", err)
	}
	if row.ItemTitle != "Swept Up" {
		t.Errorf("the swept sync is titled %q, want its playlist's name", row.ItemTitle)
	}
}

// A URL download and a playlist sync that fail tell their starter, naming
// what failed: by its title, or an untitled download by its link.
func TestADownloadOrSyncThatFailsTellsItsStarter(t *testing.T) {
	t.Parallel()
	verdict := catalogerr.Wrap(catalogerr.CodeIO, "fetch", waxtap.ErrVideoUnavailable)
	untitled := &stagingSource{}
	untitled.answerThree(func(context.Context) error { return verdict })
	for _, tc := range []struct {
		name, link, prefix string
		src                source.Provider
	}{
		{"a titled download", "https://tube.example/watch?v=one", "URL download of One Video: ", &probeSource{fetchErr: verdict}},
		{"an untitled download", "https://tube.example/watch?v=three", "URL download of https://tube.example/watch?v=three: ", untitled},
	} {
		t.Run(tc.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc := acquireFixture(t, tc.src)
			task, err := svc.Ingest.StartAcquisition(ctx, uc, tc.link, false, "music", "", "", nil, nil)
			if err != nil {
				t.Fatal(err)
			}
			drainOnce(t, ctx, svc)
			if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateFailed {
				t.Fatalf("task = %s (error %q), want it failed", row.State, row.Error)
			}
			row := waitForInbox(t, ctx, svc, uc, "tool-task-failed")
			if row.TargetPID != task.ID || !strings.HasPrefix(row.Body, tc.prefix) {
				t.Errorf("inbox row = %+v, want the failed task, its body starting %q", row, tc.prefix)
			}
		})
	}
	t.Run("a playlist sync", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc := acquireFixture(t, privateLister())
		pid := syncBinding(t, ctx, svc, uc, "Road Tapes")
		task, err := svc.Playlists.SyncPlaylistSourceNow(ctx, uc, pid)
		if err != nil {
			t.Fatal(err)
		}
		drainOnce(t, ctx, svc)
		if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateFailed {
			t.Fatalf("sync = %s (error %q), want it failed", row.State, row.Error)
		}
		row := waitForInbox(t, ctx, svc, uc, "tool-task-failed")
		if row.TargetPID != task.ID || !strings.Contains(row.Title, "Road Tapes") || !strings.HasPrefix(row.Body, "Playlist sync of Road Tapes: ") {
			t.Errorf("inbox row = %+v, want the failed sync of Road Tapes", row)
		}
	})
}

// privateLister is a source whose every playlist is private.
func privateLister() refusingLister {
	return refusingLister{err: catalogerr.Wrap(catalogerr.CodeIO, "snapshot",
		&waxtap.PlaylistUnavailableError{Reason: "This playlist is private."})}
}

// Only a sync the person started tells them it failed: a scheduled run's
// failures lead to the suspension notice instead, and a sync that finds the
// playlist deleted or unbound meanwhile, which the person did, tells
// nobody.
func TestOnlyASyncThePersonStartedTellsThemItFailed(t *testing.T) {
	t.Parallel()
	failsQuietly := func(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, id string) {
		t.Helper()
		drainOnce(t, ctx, svc)
		if row := storedTask(t, ctx, svc, id); row.State != taskStateFailed {
			t.Fatalf("sync = %s (error %q), want it failed", row.State, row.Error)
		}
		if rows := inboxOf(t, ctx, svc, uc, "tool-task-failed"); len(rows) != 0 {
			t.Errorf("the failed sync filed %+v", rows)
		}
	}
	t.Run("scheduled", func(t *testing.T) {
		t.Parallel()
		ctx, svc, uc := acquireFixture(t, privateLister())
		pid := syncBinding(t, ctx, svc, uc, "Road Tapes")
		svc.Playlists.SyncDuePlaylistSources(ctx)
		row, err := svc.db.ActiveToolTask(ctx, taskTypePlaylistSync, pid)
		if err != nil {
			t.Fatalf("the sweep queued no sync: %v", err)
		}
		failsQuietly(t, ctx, svc, uc, row.ID)
	})
	for name, gone := range map[string]func(context.Context, *Library, *UserCtx, string) error{
		"unbound meanwhile": func(ctx context.Context, svc *Library, uc *UserCtx, pid string) error {
			return svc.Playlists.UnbindPlaylistSource(ctx, uc, pid)
		},
		"deleted meanwhile": func(ctx context.Context, svc *Library, uc *UserCtx, pid string) error {
			return svc.Playlists.DeletePlaylist(ctx, uc, pid)
		},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc := acquireFixture(t, &stallingLister{})
			pid := syncBinding(t, ctx, svc, uc, "Road Tapes")
			task, err := svc.Playlists.SyncPlaylistSourceNow(ctx, uc, pid)
			if err != nil {
				t.Fatal(err)
			}
			if err := gone(ctx, svc, uc, pid); err != nil {
				t.Fatal(err)
			}
			failsQuietly(t, ctx, svc, uc, task.ID)
		})
	}
}

// listingHook is a source whose every playlist is private, which runs
// during as it lists one.
type listingHook struct {
	refusingLister
	during func()
}

func (s *listingHook) PlaylistSnapshot(ctx context.Context, url string, o syncsource.SnapshotOptions) (*syncsource.PlaylistSnapshot, error) {
	s.during()
	return s.refusingLister.PlaylistSnapshot(ctx, url, o)
}

// A sync whose playlist or binding the person removes while it lists the
// source tells nobody it failed.
func TestASyncWhosePlaylistGoesWhileItListsTellsNobody(t *testing.T) {
	t.Parallel()
	for name, gone := range map[string]func(context.Context, *Library, *UserCtx, string) error{
		"unbound": func(ctx context.Context, svc *Library, uc *UserCtx, pid string) error {
			return svc.Playlists.UnbindPlaylistSource(ctx, uc, pid)
		},
		"deleted": func(ctx context.Context, svc *Library, uc *UserCtx, pid string) error {
			return svc.Playlists.DeletePlaylist(ctx, uc, pid)
		},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			src := &listingHook{refusingLister: privateLister()}
			ctx, svc, uc := acquireFixture(t, src)
			pid := syncBinding(t, ctx, svc, uc, "Road Tapes")
			src.during = func() {
				if err := gone(ctx, svc, uc, pid); err != nil {
					t.Error(err)
				}
			}
			task, err := svc.Playlists.SyncPlaylistSourceNow(ctx, uc, pid)
			if err != nil {
				t.Fatal(err)
			}
			drainOnce(t, ctx, svc)
			if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateFailed {
				t.Fatalf("sync = %s (error %q), want it failed", row.State, row.Error)
			}
			if rows := inboxOf(t, ctx, svc, uc, "tool-task-failed"); len(rows) != 0 {
				t.Errorf("the sync whose playlist went filed %+v", rows)
			}
		})
	}
}

// Sync now while a scheduled run of the playlist waits to start answers
// that run, which then tells the person if it fails.
func TestSyncNowAsksForTheScheduledRunItAnswers(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := acquireFixture(t, privateLister())
	pid := syncBinding(t, ctx, svc, uc, "Road Tapes")
	svc.Playlists.SyncDuePlaylistSources(ctx)
	queued, err := svc.db.ActiveToolTask(ctx, taskTypePlaylistSync, pid)
	if err != nil {
		t.Fatalf("the sweep queued no sync: %v", err)
	}
	task, err := svc.Playlists.SyncPlaylistSourceNow(ctx, uc, pid)
	if err != nil || task.ID != queued.ID {
		t.Fatalf("Sync now = %+v (%v), want the scheduled run %s", task, err, queued.ID)
	}
	drainOnce(t, ctx, svc)
	if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateFailed {
		t.Fatalf("sync = %s (error %q), want it failed", row.State, row.Error)
	}
	if rows := inboxOf(t, ctx, svc, uc, "tool-task-failed"); len(rows) != 1 || rows[0].TargetPID != task.ID {
		t.Errorf("failure notices %+v, want the one for the run Sync now answered", rows)
	}
}

// A genre normalize says from the start whether it is a dry run, and still
// does once it has run.
func TestAGenreNormalizeSaysItIsADryRun(t *testing.T) {
	t.Parallel()
	f := newGenreFixture(t)
	task, err := f.svc.Reads.StartGenreNormalize(f.ctx, f.uc, true)
	if err != nil {
		t.Fatal(err)
	}
	for from, dto := range map[string]ToolTaskDTO{"answer": task, "stored": toolTaskDTO(storedTask(t, f.ctx, f.svc, task.ID))} {
		if dto.Summary["dryRun"] != true {
			t.Errorf("the %s task's summary %v, want it saying it is a dry run", from, dto.Summary)
		}
	}
	f.drainTasks(t)
	if dto := toolTaskDTO(storedTask(t, f.ctx, f.svc, task.ID)); dto.State != taskStateDone || dto.Summary["dryRun"] != true {
		t.Errorf("the run left %s with summary %v, want it done, still a dry run", dto.State, dto.Summary)
	}
}

// An import says from the start which account it imports into, by name,
// never by id, and whether it is a dry run, and still does once it has
// run.
func TestAnImportSaysWhoItImportsInto(t *testing.T) {
	t.Parallel()
	ctx, f := newMigrateFixture(t)
	ts := newFakeNavidrome(t, "demo", "demo-pass")
	acct, _ := memberAs(t, ctx, f.svc, AccountCreate{Username: "second", DisplayName: "Second Listener"})
	task, err := f.svc.Migrate.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL, Username: "demo", Password: "demo-pass",
		Stars: true, DryRun: true, AccountID: acct.User.ID,
	})
	if err != nil {
		t.Fatal(err)
	}
	for from, dto := range map[string]ToolTaskDTO{"answer": task, "stored": toolTaskDTO(storedTask(t, ctx, f.svc, task.ID))} {
		if dto.Summary["target"] != "Second Listener" || dto.Summary["dryRun"] != true {
			t.Errorf("the %s task's summary %v, want the target's name and a dry run", from, dto.Summary)
		}
	}
	own, err := f.svc.Migrate.StartMigration(ctx, f.uc, MigrationRequest{
		Source: "navidrome", ServerURL: ts.URL, Username: "demo", Password: "demo-pass", Stars: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	if own.Summary["target"] != "admin" || own.Summary["dryRun"] != false {
		t.Errorf("an import into the caller's own account has summary %v, want its username and no dry run", own.Summary)
	}
	row := storedTask(t, ctx, f.svc, task.ID)
	release := f.svc.Tools.holdToolTask(row.ID, nil)
	err = f.svc.Migrate.runMigrationTask(ctx, &row)
	release()
	if err != nil {
		t.Fatal(err)
	}
	if sum := toolTaskDTO(row).Summary; sum["target"] != "Second Listener" || sum["dryRun"] != true {
		t.Errorf("the run's summary %v, want it still naming the target and the dry run", sum)
	}
}

// A health fix queued for chosen items says how many from the start, and
// still does once it has run; a fix of the whole rule says nothing of it.
func TestAScopedHealthFixSaysHowManyItems(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, track := openLyricsFixture(t, &lyricist{name: "a"})
	if err := svc.Health.RunHealthSweep(ctx); err != nil {
		t.Fatal(err)
	}
	start, err := svc.Health.StartHealthFix(ctx, uc, ruleMissingLyrics, []string{apiPID(PrefixTrack, track)})
	if err != nil {
		t.Fatal(err)
	}
	if sum := toolTaskDTO(storedTask(t, ctx, svc, start.TaskID)).Summary; sum["scoped"] != float64(1) || sum["rule"] != ruleMissingLyrics {
		t.Errorf("the fix as queued has summary %v, want its rule and one item", sum)
	}
	if sum := fixSummary(t, ctx, svc, uc, start.TaskID); sum.Scoped != 1 || sum.Attempted != 1 {
		t.Errorf("the run's summary %+v, want it still saying one item", sum)
	}
}

// A crash after a review entry and its download's link are stored and
// before the task records the entry leaves nothing out: the next run
// takes the entry as the task's, rather than finding nothing downloaded.
func TestAnEntryOpenedButNeverRecordedIsTheTasks(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := acquireFixture(t, &stagingSource{})
	identify := false
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/watch?v=one", false, "music", "", "", &identify, nil)
	if err != nil {
		t.Fatal(err)
	}
	// The declined entry's import runs between its link and its record.
	svc.Ingest.planHook = func(context.Context, waxbin.AcquiredFile, model.Kind, waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
		panic("the run died")
	}
	func() {
		defer func() {
			if recover() == nil {
				t.Fatal("the run did not die")
			}
		}()
		drainOnce(t, ctx, svc)
	}()
	svc.Ingest.planHook = nil
	var entry string
	if err := svc.db.Reader().QueryRowContext(ctx, `SELECT review_entry_id FROM uploads`).Scan(&entry); err != nil || entry == "" {
		t.Fatalf("the download's entry = %q (%v), want it linked before the run died", entry, err)
	}
	crashed := storedTask(t, ctx, svc, task.ID)
	if got := taskParamsOf(&crashed).Entries; len(got) != 0 {
		t.Fatalf("the task recorded %v before the run died, want nothing", got)
	}
	drainTaskAt(t, ctx, svc, time.Now().Add(time.Hour))
	row := storedTask(t, ctx, svc, task.ID)
	if row.State != taskStateDone || row.ResultPIDs != `["`+entry+`"]` {
		t.Fatalf("the next run left %s with results %s (error %q, code %q), want it done listing %s",
			row.State, row.ResultPIDs, row.Error, row.ErrorCode, entry)
	}
	// Declined, the entry lands unreviewed, as the run that died would
	// have had it.
	var state string
	if err := svc.db.Reader().QueryRowContext(ctx, `SELECT state FROM uploads`).Scan(&state); err != nil || state != uploadImported {
		t.Errorf("the download is %q (%v), want it imported", state, err)
	}
}

// What an earlier run staged but could not open an entry for is reported
// as the entries failing to open, an acquisition's and a sync's alike.
func TestAFailedOpeningOfStrandedEntriesSaysSo(t *testing.T) {
	t.Parallel()
	for _, kind := range []string{taskTypeAcquire, taskTypePlaylistSync} {
		t.Run(kind, func(t *testing.T) {
			t.Parallel()
			src := &stallingLister{}
			src.answerThree(func(context.Context) error { panic("the run died") })
			ctx, svc, uc := acquireFixture(t, src)
			var task ToolTaskDTO
			var err error
			if kind == taskTypeAcquire {
				task, err = svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
			} else {
				task, err = svc.Playlists.SyncPlaylistSourceNow(ctx, uc, syncBinding(t, ctx, svc, uc, "Three"))
			}
			if err != nil {
				t.Fatal(err)
			}
			func() {
				defer func() {
					if recover() == nil {
						t.Fatal("the run did not die")
					}
				}()
				drainOnce(t, ctx, svc)
			}()
			if n := uploadsWithoutEntry(t, ctx, svc); n != 2 {
				t.Fatalf("%d staged downloads without an entry, want the two the run staged", n)
			}
			src.answerThree(nil)
			if _, err := svc.db.Writer().ExecContext(ctx, `CREATE TRIGGER refuse BEFORE INSERT ON match_queue BEGIN SELECT RAISE(ABORT, 'refused'); END`); err != nil {
				t.Fatal(err)
			}
			drainTaskAt(t, ctx, svc, time.Now().Add(time.Hour))
			row := storedTask(t, ctx, svc, task.ID)
			if row.WaitReason != "other" || !strings.HasPrefix(row.Error, "opening review entries: ") {
				t.Errorf("task = %s waiting on %q, error %q, want it waiting, saying opening the review entries failed",
					row.State, row.WaitReason, row.Error)
			}
		})
	}
}

// A download the person removed while the run went on is left out of the
// entries, and the run carries on with the rest; a later run of the task
// does not fetch it again.
func TestADownloadRemovedMidRunIsSkipped(t *testing.T) {
	t.Parallel()
	for name, hiccup := range map[string]bool{"in the run": false, "in a later run": true} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			src := &stagingSource{}
			ctx, svc, uc := acquireFixture(t, src)
			src.answerThree(func(context.Context) error {
				var id string
				if err := svc.db.Reader().QueryRowContext(ctx, `SELECT id FROM uploads WHERE file_name = 'one.mp3'`).Scan(&id); err != nil {
					return err
				}
				if err := svc.Ingest.DeleteUpload(ctx, uc, id); err != nil || !hiccup {
					return err
				}
				return errors.New("a passing hiccup")
			})
			task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
			if err != nil {
				t.Fatal(err)
			}
			drainOnce(t, ctx, svc)
			if hiccup {
				if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateRunning || row.WaitReason == "" {
					t.Fatalf("task = %s waiting on %q (error %q), want it waiting after the hiccup", row.State, row.WaitReason, row.Error)
				}
				src.answerThree(nil)
				drainTaskAt(t, ctx, svc, time.Now().Add(time.Hour))
			}
			row := storedTask(t, ctx, svc, task.ID)
			if got := entryTitles(t, ctx, svc, row); row.State != taskStateDone || !slices.Equal(got, []string{"two", "three"}) {
				t.Fatalf("task = %s with entries %q (error %q, code %q), want it done with the two still staged",
					row.State, got, row.Error, row.ErrorCode)
			}
			if n := src.fetchCounts()["https://tube.example/watch?v=one"]; n != 1 {
				t.Errorf("the removed download was fetched %d times, want once", n)
			}
		})
	}
}

// A listed book whose part the person removed before its entry opened
// opens its one entry with the other parts.
func TestABookPartRemovedMidRunLeavesTheRestOfTheBook(t *testing.T) {
	t.Parallel()
	src := &stagingSource{}
	ctx, svc, uc := acquireFixture(t, src)
	src.answerThree(func(context.Context) error {
		var id string
		if err := svc.db.Reader().QueryRowContext(ctx, `SELECT id FROM uploads WHERE file_name = 'one.mp3'`).Scan(&id); err != nil {
			return err
		}
		return svc.Ingest.DeleteUpload(ctx, uc, id)
	})
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "audiobook", "", "", nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	drainOnce(t, ctx, svc)
	row := storedTask(t, ctx, svc, task.ID)
	entries := taskParamsOf(&row).Entries
	if row.State != taskStateDone || len(entries) != 1 {
		t.Fatalf("task = %s with entries %v (error %q), want it done with the book's one entry", row.State, entries, row.Error)
	}
	var linked int
	if err := svc.db.Reader().QueryRowContext(ctx, `SELECT COUNT(*) FROM uploads WHERE review_entry_id = ?`, entries[0]).Scan(&linked); err != nil || linked != 2 {
		t.Errorf("the entry links %d downloads (%v), want the two parts left", linked, err)
	}
	dropped := 0
	for _, f := range taskParamsOf(&row).Fetched {
		if f.Dropped {
			dropped++
		}
	}
	if dropped != 1 {
		t.Errorf("%d downloads recorded removed, want the one", dropped)
	}
}

// A run whose own downloads staged and whose entries could not open says
// so, an acquisition's batch and a sync's alike.
func TestAFailedOpeningOfABatchsEntriesSaysSo(t *testing.T) {
	t.Parallel()
	for _, kind := range []string{taskTypeAcquire, taskTypePlaylistSync} {
		t.Run(kind, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc := acquireFixture(t, &stallingLister{})
			var task ToolTaskDTO
			var err error
			if kind == taskTypeAcquire {
				task, err = svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", false, "music", "", "", nil, nil)
			} else {
				task, err = svc.Playlists.SyncPlaylistSourceNow(ctx, uc, syncBinding(t, ctx, svc, uc, "Three"))
			}
			if err != nil {
				t.Fatal(err)
			}
			if _, err := svc.db.Writer().ExecContext(ctx, `CREATE TRIGGER refuse BEFORE INSERT ON match_queue BEGIN SELECT RAISE(ABORT, 'refused'); END`); err != nil {
				t.Fatal(err)
			}
			drainOnce(t, ctx, svc)
			row := storedTask(t, ctx, svc, task.ID)
			if row.WaitReason != "other" || !strings.HasPrefix(row.Error, "opening review entries: ") {
				t.Errorf("task = %s waiting on %q, error %q, want it waiting, saying opening the review entries failed",
					row.State, row.WaitReason, row.Error)
			}
		})
	}
}

// An adopted declined entry whose import dies with the run is adopted and
// imported again by the next one: the adoption records it only once it
// is imported.
func TestAnAdoptedEntryWhoseImportDiesIsAdoptedAgain(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := acquireFixture(t, &stagingSource{})
	identify := false
	task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/watch?v=one", false, "music", "", "", &identify, nil)
	if err != nil {
		t.Fatal(err)
	}
	svc.Ingest.planHook = func(context.Context, waxbin.AcquiredFile, model.Kind, waxbin.AcquiredMeta) (*waxbin.AcquiredResult, error) {
		panic("the run died")
	}
	die := func(run func()) {
		t.Helper()
		defer func() {
			if recover() == nil {
				t.Fatal("the run did not die")
			}
		}()
		run()
	}
	die(func() { drainOnce(t, ctx, svc) })
	die(func() { drainTaskAt(t, ctx, svc, time.Now().Add(time.Hour)) })
	svc.Ingest.planHook = nil
	drainTaskAt(t, ctx, svc, time.Now().Add(2*time.Hour))
	row := storedTask(t, ctx, svc, task.ID)
	var state string
	if err := svc.db.Reader().QueryRowContext(ctx, `SELECT state FROM uploads`).Scan(&state); err != nil || state != uploadImported || row.State != taskStateDone {
		t.Errorf("the download is %q (%v), task %s (error %q); want it imported and the task done", state, err, row.State, row.Error)
	}
}

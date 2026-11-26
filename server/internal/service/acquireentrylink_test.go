package service

import (
	"testing"
	"time"
)

// A run that fails between storing a review entry and linking and queuing
// it stores none of the three, and the next run gives each staged file
// exactly one entry, queued to identify.
func TestAnEntryThatFailsBeforeItsLinkIsNotOpenedTwice(t *testing.T) {
	t.Parallel()
	for name, fault := range map[string]string{
		// The identify queue write sits between storing the entry and
		// linking it.
		"queue": `CREATE TRIGGER refuse BEFORE INSERT ON match_queue BEGIN SELECT RAISE(ABORT, 'refused'); END`,
		"link": `CREATE TRIGGER refuse BEFORE UPDATE OF review_entry_id ON uploads
			WHEN NEW.review_entry_id <> '' BEGIN SELECT RAISE(ABORT, 'refused'); END`,
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc := acquireFixture(t, &stagingSource{})
			task, err := svc.Ingest.StartAcquisition(ctx, uc, "https://tube.example/playlist?list=PLthree", true, "music", "", "", nil, nil)
			if err != nil {
				t.Fatal(err)
			}
			if _, err := svc.db.Writer().ExecContext(ctx, fault); err != nil {
				t.Fatal(err)
			}
			drainOnce(t, ctx, svc)
			if _, err := svc.db.Writer().ExecContext(ctx, `DROP TRIGGER refuse`); err != nil {
				t.Fatal(err)
			}
			count := func(q string) int {
				t.Helper()
				var n int
				if err := svc.db.Reader().QueryRowContext(ctx, q).Scan(&n); err != nil {
					t.Fatal(err)
				}
				return n
			}
			if n := count(`SELECT COUNT(*) FROM review_entries`) + count(`SELECT COUNT(*) FROM match_queue`) +
				count(`SELECT COUNT(*) FROM uploads WHERE review_entry_id <> ''`); n != 0 {
				t.Errorf("the failed run left %d entries, queue rows or links, want it rolled back whole", n)
			}
			drainTaskAt(t, ctx, svc, time.Now().Add(time.Hour))
			if row := storedTask(t, ctx, svc, task.ID); row.State != taskStateDone {
				t.Fatalf("the retry left the task %s (error %q), want it done", row.State, row.Error)
			}
			if n := uploadsWithoutEntry(t, ctx, svc); n != 0 {
				t.Errorf("%d staged downloads have no review entry, want none", n)
			}
			if n := count(`SELECT COUNT(*) FROM review_entries e WHERE NOT EXISTS (SELECT 1 FROM uploads u WHERE u.review_entry_id = e.id)`); n != 0 {
				t.Errorf("%d review entries hold no download, want each file in exactly one", n)
			}
			if n := count(`SELECT COUNT(*) FROM review_entries e WHERE e.identifying AND NOT EXISTS (SELECT 1 FROM match_queue q WHERE q.entry_id = e.id)`); n != 0 {
				t.Errorf("%d identifying entries have no queue row", n)
			}
			if n := count(`SELECT COUNT(*) FROM review_entries WHERE identifying`); n == 0 {
				t.Error("no entry is identifying, want the retry's entries queued")
			}
		})
	}
}

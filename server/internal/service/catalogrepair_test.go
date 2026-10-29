package service

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"reflect"
	"slices"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxbin/waxerr"

	"github.com/colespringer/waxdeck/fixtures"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// repairFixture is the catalog fixture with six more tracks, each its own
// artist, genre and album, so every count the check makes can be seeded
// with a number of its own.
func repairFixture(t *testing.T) (context.Context, *Library, *UserCtx) {
	t.Helper()
	return newCatalogFixtureWith(t, catalogFixtureOptions{extra: func(t *testing.T, dir string) {
		var specs []fixtures.Spec
		for i := 1; i <= 6; i++ {
			specs = append(specs, fixtures.Spec{
				Name: fmt.Sprintf("extra-%d", i), Codec: fixtures.CodecFLAC, Duration: 2 * time.Second,
				Tags: map[string]string{
					"TITLE":  fmt.Sprintf("Extra %d", i),
					"ARTIST": fmt.Sprintf("Extra Artist %d", i),
					"ALBUM":  fmt.Sprintf("Extra Album %d", i),
					"GENRE":  fmt.Sprintf("Extra Genre %d", i),
				},
			})
		}
		if _, err := fixtures.Generate(dir, specs...); err != nil {
			t.Fatal(err)
		}
	}})
}

// catalogDB opens the service's catalog database beside it, read-write,
// to plant what no catalog verb writes.
func catalogDB(t *testing.T, svc *Library) *sql.DB {
	t.Helper()
	db, err := sql.Open("sqlite", "file:"+svc.catalogPath)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { db.Close() })
	return db
}

// plant runs one statement and checks it wrote as many rows as want.
func plant(t *testing.T, db *sql.DB, want int64, stmt string, args ...any) {
	t.Helper()
	res, err := db.Exec(stmt, args...)
	if err != nil {
		t.Fatalf("%s: %v", stmt, err)
	}
	if n, err := res.RowsAffected(); err != nil || n != want {
		t.Fatalf("%s wrote %d rows (%v), want %d", stmt, n, err, want)
	}
}

// seedCatalogDrift plants a different number of rows under every count
// the check makes but the two a library without books cannot carry, and
// two genres with no items: one a repair a day ago already found so, one
// it has not. It answers the check it expects.
func seedCatalogDrift(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) CatalogConsistencyDTO {
	t.Helper()
	pids := fixtureItemPIDs(t, ctx, svc, uc)
	if _, err := svc.CreatePlaylist(ctx, uc, PlaylistCreate{
		Name: "Gappy", Kind: "static", Visibility: "private", ItemPIDs: pids[:2],
	}); err != nil {
		t.Fatal(err)
	}
	db := catalogDB(t, svc)
	var last, before int64
	if err := db.QueryRow("SELECT MAX(id) FROM playable_item").Scan(&last); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRow("SELECT MAX(id) FROM playable_item WHERE id <> ?", last).Scan(&before); err != nil {
		t.Fatal(err)
	}
	plant(t, db, 9, "DELETE FROM search_fts WHERE rowid IN (SELECT id FROM playable_item WHERE id <> ?)", last)
	plant(t, db, 2, `INSERT INTO search_fts(rowid, kind, title, subtitle, artist, album, extra, credits)
		VALUES (900001, 'track', 'ghost', '', '', '', '', ''), (900002, 'track', 'ghost', '', '', '', '', '')`)
	plant(t, db, 3, "UPDATE artist_rollup SET track_count = track_count + 7 WHERE artist_id IN (SELECT id FROM artist ORDER BY id LIMIT 3)")
	plant(t, db, 4, "UPDATE genre_rollup SET track_count = track_count + 7 WHERE genre_id IN (SELECT id FROM genre ORDER BY id LIMIT 4)")
	plant(t, db, 5, "UPDATE release_group_rollup SET track_count = track_count + 7 WHERE release_group_id IN (SELECT id FROM release_group ORDER BY id LIMIT 5)")
	plant(t, db, 6, "UPDATE artist SET sort_key = 'zzzz ' || sort_key WHERE id IN (SELECT id FROM artist ORDER BY id LIMIT 6)")
	plant(t, db, 7, "UPDATE album SET year = 1901 WHERE id IN (SELECT id FROM album ORDER BY id LIMIT 7)")
	plant(t, db, 8, "UPDATE playable_item SET release_year = 1902 WHERE id IN (SELECT id FROM playable_item ORDER BY id LIMIT 8)")
	plant(t, db, 2, "UPDATE playlist_item SET position = position + 10 WHERE playlist_id = (SELECT id FROM playlist WHERE name = 'Gappy')")
	for i := range 11 {
		plant(t, db, 1, "INSERT INTO art_source (hash, format, width, height, size, created_at, data) VALUES (?, 'png', 1, 1, 1, 1, x'00')",
			fmt.Sprintf("orphan-%d", i))
		plant(t, db, 1, "INSERT INTO thumb_cache (source_hash, size, format, width, height, created_at, data) VALUES (?, 64, 'png', 1, 1, 1, x'00')",
			fmt.Sprintf("orphan-%d", i))
	}
	plant(t, db, 1, "INSERT INTO thumb_cache (source_hash, size, format, width, height, created_at, data) VALUES ('orphan-0', 128, 'png', 1, 1, 1, x'00')")
	for _, key := range model.ReservedTagKeys()[:13] {
		plant(t, db, 1, "INSERT INTO field_provenance (item_id, field, source, locked, value, updated_at) VALUES (?, ?, 'user', 0, 'x', 1)",
			before, model.TagLockField(key))
	}
	for i := range 14 {
		plant(t, db, 1, "INSERT INTO item_tag (item_id, key, value, position) VALUES (?, 'not a key', 'x', ?)", last, i)
	}
	for _, name := range []string{"Gone Genre", "Fresh Genre"} {
		plant(t, db, 1, "INSERT INTO genre (pid, facet, name, match_key, sort_key) VALUES (?, 'genre', ?, ?, ?)",
			string(model.NewPID()), name, model.SortKey(name), model.SortKey(name))
		plant(t, db, 1, "INSERT INTO genre_rollup (genre_id, track_count, total_duration_ms, updated_at) SELECT id, 0, 0, 1 FROM genre WHERE name = ?", name)
	}
	plant(t, db, 1, "INSERT INTO orphan_candidate (entity_type, entity_id, first_seen) SELECT 'genre', id, 1 FROM genre WHERE name = 'Gone Genre'")
	return CatalogConsistencyDTO{
		ItemsMissingFromSearch: 9, OrphanSearchRows: 2, ArtistRollupDrift: 3, GenreRollupDrift: 4,
		ReleaseGroupRollupDrift: 5, SortKeyDrift: 6, AlbumYearDrift: 7, ReleaseYearDrift: 8,
		PlaylistPositionDrift: 1, OrphanArtSources: 11, OrphanThumbnails: 12, OrphanTagProvenance: 13,
		StrandedTagRows: 14, Reclaimable: true,
	}
}

// repairSummary runs the queued tool tasks and reads the repair's report,
// which has to have finished.
func repairSummary(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, taskID string) map[string]any {
	t.Helper()
	for svc.DrainLongToolTasks(ctx) {
	}
	task, err := svc.GetToolTaskFor(ctx, uc, taskID)
	if err != nil {
		t.Fatal(err)
	}
	if task.State != taskStateDone {
		t.Fatalf("repair %s (%s), want it done", task.State, task.Error)
	}
	return task.Summary
}

// storedSummary is a repair's summary as its row holds it, however the
// run stands.
func storedSummary(t *testing.T, ctx context.Context, svc *Library, taskID string) map[string]any {
	t.Helper()
	row, err := svc.db.ToolTaskByID(ctx, taskID)
	if err != nil {
		t.Fatal(err)
	}
	sum := map[string]any{}
	if row.Summary != "" {
		if err := json.Unmarshal([]byte(row.Summary), &sum); err != nil {
			t.Fatal(err)
		}
	}
	return sum
}

// afterCheck is the check a summary closes on.
func afterCheck(t *testing.T, sum map[string]any) CatalogConsistencyDTO {
	t.Helper()
	raw, err := json.Marshal(sum["after"])
	if err != nil {
		t.Fatal(err)
	}
	var after CatalogConsistencyDTO
	if sum["after"] == nil || json.Unmarshal(raw, &after) != nil {
		t.Fatalf("the summary %v closes on no check", sum)
	}
	return after
}

// repairEntry is the one catalog.repair audit entry.
func repairEntry(t *testing.T, ctx context.Context, svc *Library) AuditEventDTO {
	t.Helper()
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "catalog.repair"}, "", 10)
	if err != nil || len(page.Events) != 1 {
		t.Fatalf("catalog.repair audit = %+v (%v), want one entry", page.Events, err)
	}
	return page.Events[0]
}

// The check counts what is planted, each count in its own field, and the
// repair clears all of it, saying what each step did and what the check
// read after; the record says who asked and what came of it.
func TestACatalogRepairClearsWhatTheCheckCounts(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := repairFixture(t)
	want := seedCatalogDrift(t, ctx, svc, uc)
	if got, err := svc.CatalogConsistency(ctx, uc); err != nil || got != want {
		t.Fatalf("the check = %+v (%v), want %+v", got, err, want)
	}

	task, err := svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	if task.Type != taskTypeCatalogRepair || task.State != taskStateQueued {
		t.Fatalf("the repair = %+v, want a queued %s task", task, taskTypeCatalogRepair)
	}
	sum := repairSummary(t, ctx, svc, uc, task.ID)
	clean := CatalogConsistencyDTO{Consistent: true}
	if after := afterCheck(t, sum); after != clean {
		t.Fatalf("the check after = %+v, want it clean", after)
	}
	every := []catalogRepairRun{{Steps: []string{
		catalogRepairRollups, catalogRepairSortKeys, catalogRepairOrphans, catalogRepairArt,
		catalogRepairTagProvenance, catalogRepairStrandedTags, catalogRepairSearch, catalogRepairVerify,
	}}}
	if runs := repairRuns(t, sum); !reflect.DeepEqual(runs, every) {
		t.Fatalf("the repair's runs = %+v, want one run of every step", runs)
	}
	delete(sum, "after")
	delete(sum, "runs")
	if want := map[string]any{
		"sortKeysRewritten": 6.0, "orphansDeleted": 1.0, "orphansPending": 1.0,
		"artSourcesReclaimed": 11.0, "thumbnailsReclaimed": 12.0,
		"tagProvenanceReclaimed": 13.0, "strandedTagRowsReclaimed": 14.0,
		"searchRowsRebuilt": 11.0,
	}; !maps.Equal(sum, want) {
		t.Fatalf("the summary = %v, want %v", sum, want)
	}
	if got, err := svc.CatalogConsistency(ctx, uc); err != nil || got != clean {
		t.Fatalf("the check after the repair = %+v (%v), want it clean", got, err)
	}

	// The catalog is no entity of a name its row could show, so the
	// target is its kind alone.
	e := repairEntry(t, ctx, svc)
	if e.ActorID != uc.ID || e.TargetKind != "catalog" || e.TargetName != "" ||
		e.Detail["task"] != task.ID || e.Detail["state"] != taskStateDone ||
		e.Detail["sortKeysRewritten"] != 6.0 || e.Detail["searchRowsRebuilt"] != 11.0 {
		t.Fatalf("catalog.repair entry = %+v, want the starter, the task and what it did", e)
	}
}

// One repair at a time: a second start while one waits to run is refused,
// naming the one there is, and once that one is done another may start.
// A member may neither check nor repair.
func TestACatalogRepairRunsOneAtATime(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	first, err := svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	_, err = svc.StartCatalogRepair(ctx, uc)
	if p := RefusalParams(err); KindOf(err) != KindConflict || p["task"] != first.ID {
		t.Fatalf("a second start = %v (%v), want a conflict naming %s", err, p, first.ID)
	}
	repairSummary(t, ctx, svc, uc, first.ID)
	if _, err := svc.StartCatalogRepair(ctx, uc); err != nil {
		t.Fatalf("a start after the first finished: %v", err)
	}

	member := memberCtx(t, ctx, svc, "member")
	if _, err := svc.CatalogConsistency(ctx, member); KindOf(err) != KindForbidden {
		t.Errorf("a member's check = %v, want forbidden", err)
	}
	if _, err := svc.StartCatalogRepair(ctx, member); KindOf(err) != KindForbidden {
		t.Errorf("a member's repair = %v, want forbidden", err)
	}
}

// The repair writes no file, so a read-only server runs it.
func TestACatalogRepairRunsOnAReadOnlyServer(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	execCatalog(t, svc.catalogPath, "UPDATE artist SET sort_key = 'zzzz stale'")
	setServerReadOnly(t, ctx, svc, true)
	task, err := svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	if sum := repairSummary(t, ctx, svc, uc, task.ID); sum["sortKeysRewritten"] != 2.0 || !afterCheck(t, sum).Consistent {
		t.Fatalf("the read-only repair = %v, want both artists' keys rewritten and the catalog clean", sum)
	}
}

// The release years and sort keys a repair rewrites order the catalog's
// lists, and the catalog does not say which years it rewrote, so a repair
// that got past its first step wakes connected clients when it ends, as
// the feed does for an item's change, and their pull finds their cursors
// retired. One stopped before it changed anything tells them nothing.
func TestARepairTellsClientsTheCatalogMoved(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	woken := func() bool {
		feedCaughtUp(t, ctx, svc)
		select {
		case <-svc.catalogWake:
			return true
		default:
			return false
		}
	}
	woken()
	execCatalog(t, svc.catalogPath, "UPDATE playable_item SET release_year = 1902 WHERE id = (SELECT MIN(id) FROM playable_item)")
	if c, err := svc.CatalogConsistency(ctx, uc); err != nil || c.ReleaseYearDrift != 1 {
		t.Fatalf("the check after a planted year = %+v (%v), want the one item drifted", c, err)
	}
	task, err := svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	if sum := repairSummary(t, ctx, svc, uc, task.ID); afterCheck(t, sum).ReleaseYearDrift != 0 {
		t.Fatalf("the repair = %v, want the year put back", sum)
	}
	if !woken() {
		t.Error("a repair that rewrote a release year did not wake the clients")
	}

	svc.catalogRepairHook = func(step string) error {
		if step == catalogRepairRollups {
			return &Error{Kind: KindInvalid, Msg: "refused"}
		}
		return nil
	}
	task, err = svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	for svc.DrainLongToolTasks(ctx) {
	}
	if row, err := svc.db.ToolTaskByID(ctx, task.ID); err != nil || row.State != taskStateFailed {
		t.Fatalf("the repair refused at its first step = %+v (%v), want it failed", row, err)
	}
	if woken() {
		t.Error("a repair stopped before it changed anything woke the clients")
	}
}

// A step that fails ends the attempt saying which step it was, and the
// summary and the record hold the steps that ran and none that did not.
func TestAFailedRepairStepIsNamed(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	svc.catalogRepairHook = func(step string) error {
		if step == catalogRepairArt {
			return waxerr.Wrap(waxerr.CodeInvalid, "store.GCArt", errors.New("boom"))
		}
		return nil
	}
	task, err := svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	for svc.DrainLongToolTasks(ctx) {
	}
	row, err := svc.db.ToolTaskByID(ctx, task.ID)
	if err != nil {
		t.Fatal(err)
	}
	// Three of its eight steps reported before the fourth failed.
	if row.State != taskStateFailed || row.Error != "reclaiming unused images: boom" || row.ProgressPct != 37.5 {
		t.Fatalf("the failed repair = %+v, want it failed at the art step, three steps in", row)
	}
	sum := storedSummary(t, ctx, svc, task.ID)
	for _, ran := range []string{"sortKeysRewritten", "orphansDeleted", "orphansPending"} {
		if _, ok := sum[ran]; !ok {
			t.Errorf("the summary %v lacks %s, a step that ran", sum, ran)
		}
	}
	for _, never := range []string{"artSourcesReclaimed", "thumbnailsReclaimed", "tagProvenanceReclaimed",
		"strandedTagRowsReclaimed", "searchRowsRebuilt", "after"} {
		if _, ok := sum[never]; ok {
			t.Errorf("the summary %v carries %s, which never ran", sum, never)
		}
	}
	e := repairEntry(t, ctx, svc)
	if e.Detail["state"] != taskStateFailed || e.Detail["error"] != row.Error || e.Detail["sortKeysRewritten"] != 0.0 {
		t.Fatalf("catalog.repair entry = %+v, want the failure and the steps that ran", e)
	}
	if _, ok := e.Detail["artSourcesReclaimed"]; ok {
		t.Errorf("catalog.repair entry = %+v, counting a step that never ran", e)
	}
}

// repairRuns reads what each run of a repair did from its summary or its
// record's detail.
func repairRuns(t *testing.T, doc map[string]any) []catalogRepairRun {
	t.Helper()
	raw, err := json.Marshal(doc["runs"])
	if err != nil {
		t.Fatal(err)
	}
	var runs []catalogRepairRun
	if err := json.Unmarshal(raw, &runs); err != nil {
		t.Fatalf("runs %s: %v", raw, err)
	}
	return runs
}

// A repair cut short resumes after the last step it finished, the check
// still last, and says what each run did: the first's steps and why it
// stopped, then the second's, none of them a step the first finished. The
// key the first rewrote is counted once, and a step the first never
// reached only once one reaches it.
func TestARetriedRepairResumesAfterItsLastStep(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	execCatalog(t, svc.catalogPath, "UPDATE artist SET sort_key = 'zzzz stale' WHERE name = 'Brass Nine'")
	var ran []string
	svc.catalogRepairHook = func(step string) error {
		ran = append(ran, step)
		if step == catalogRepairArt && len(ran) == 4 {
			return errors.New("the disk went away for a moment")
		}
		return nil
	}
	task, err := svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	if !svc.DrainLongToolTasks(ctx) {
		t.Fatal("the repair did not run")
	}
	first := storedSummary(t, ctx, svc, task.ID)
	if _, reached := first["artSourcesReclaimed"]; first["sortKeysRewritten"] != 1.0 || reached {
		t.Fatalf("the cut attempt's summary = %v, want the key rewritten and the art step absent", first)
	}
	cut := catalogRepairRun{
		Steps: []string{catalogRepairRollups, catalogRepairSortKeys, catalogRepairOrphans},
		Error: "reclaiming unused images: the disk went away for a moment",
	}
	if got := repairRuns(t, first); !reflect.DeepEqual(got, []catalogRepairRun{cut}) {
		t.Fatalf("the cut attempt's runs = %+v, want %+v", got, cut)
	}

	ran = nil
	if !svc.drainToolTasksAt(ctx, wdb.TaskTypes{Only: longToolTasks}, time.Now().Add(time.Hour).UnixNano()) {
		t.Fatal("the cut repair did not run again")
	}
	rest := []string{catalogRepairArt, catalogRepairTagProvenance, catalogRepairStrandedTags, catalogRepairSearch, catalogRepairVerify}
	if !slices.Equal(ran, rest) {
		t.Fatalf("the second run took %v, want only the steps the first did not finish, %v", ran, rest)
	}
	sum := repairSummary(t, ctx, svc, uc, task.ID)
	if sum["sortKeysRewritten"] != 1.0 || sum["artSourcesReclaimed"] != 0.0 || !afterCheck(t, sum).Consistent {
		t.Fatalf("the finished repair = %v, want the first attempt's key and the second's art step", sum)
	}
	runs := []catalogRepairRun{cut, {Steps: rest}}
	if got := repairRuns(t, sum); !reflect.DeepEqual(got, runs) {
		t.Fatalf("the finished repair's runs = %+v, want %+v", got, runs)
	}
	e := repairEntry(t, ctx, svc)
	if e.Detail["sortKeysRewritten"] != 1.0 || !reflect.DeepEqual(repairRuns(t, e.Detail), runs) {
		t.Fatalf("catalog.repair entry = %+v, want the key the first attempt rewrote and both runs", e)
	}
}

// A hand-off that cuts a repair short is waited out, the attempt not
// spent, and the repair starts over once the catalog is back, the cut run
// on the record. Clients are woken by the run that finishes, never while
// the catalog they would read again is handed off.
func TestACatalogRepairWaitsOutAHandOff(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	execCatalog(t, svc.catalogPath, "UPDATE artist SET sort_key = 'zzzz stale' WHERE name = 'Brass Nine'")
	woken := func() bool {
		select {
		case <-svc.catalogWake:
			return true
		default:
			return false
		}
	}
	feedCaughtUp(t, ctx, svc)
	woken()
	var steps []string
	svc.catalogRepairHook = func(step string) error {
		steps = append(steps, step)
		if step == catalogRepairSortKeys && len(steps) == 2 {
			return svc.lib.BeginMaintenance(ctx)
		}
		return nil
	}
	task, err := svc.StartCatalogRepair(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	if !svc.DrainLongToolTasks(ctx) {
		t.Fatal("the repair did not run")
	}
	row, err := svc.db.ToolTaskByID(ctx, task.ID)
	if err != nil {
		t.Fatal(err)
	}
	if row.State != taskStateRunning || row.WaitReason != "catalog-maintenance" || row.Attempts != 0 {
		t.Fatalf("the cut repair = %+v, want it waiting out the hand-off with no attempt spent", row)
	}
	if woken() {
		t.Error("a repair cut short by the hand-off woke the clients while the catalog was handed off")
	}
	if runs := repairRuns(t, storedSummary(t, ctx, svc, task.ID)); len(runs) != 1 || !runs[0].HandedOff ||
		!slices.Equal(runs[0].Steps, []string{catalogRepairRollups}) {
		t.Fatalf("the cut run = %+v, want its rollups step on the record and the hand-off that cut it", runs)
	}
	if err := svc.lib.EndMaintenance(ctx); err != nil {
		t.Fatal(err)
	}
	if !svc.drainToolTasksAt(ctx, wdb.TaskTypes{Only: longToolTasks}, time.Now().Add(time.Hour).UnixNano()) {
		t.Fatal("the waiting repair did not run again")
	}
	sum := repairSummary(t, ctx, svc, uc, task.ID)
	if sum["sortKeysRewritten"] != 1.0 || steps[2] != catalogRepairRollups {
		t.Fatalf("the second run = %v after steps %v, want it from the start, rewriting the key", sum, steps)
	}
	if runs := repairRuns(t, sum); len(runs) != 2 || runs[1].HandedOff || len(runs[1].Steps) != 8 {
		t.Fatalf("the runs = %+v, want the cut run, then one of every step", runs)
	}
	feedCaughtUp(t, ctx, svc)
	if !woken() {
		t.Error("the repair's finished run did not wake the clients")
	}
}

package service

import (
	"context"
	"errors"
	"fmt"
	"os"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// WaxBin's kind refusals are answered in WaxDeck's words, with no path or
// bare pid, and a reword upstream fails here rather than falling through
// to the generic sentence.
func TestKindRefusalsKeepTheirWording(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCueFixture(t)
	one, _, _ := carvedTracks(t, ctx, svc, uc)
	_, cue := svc.SetItemsKind(ctx, uc, []string{one}, "audiobook", false)
	if KindOf(cue) != KindInvalid || !strings.Contains(cue.Error(), "is a cue track") {
		t.Fatalf("a cue track = %v, want the cue-track refusal", cue)
	}

	var plain string
	for _, pid := range fixtureItemPIDs(t, ctx, svc, uc) {
		it, err := svc.getVisibleItem(ctx, uc, pid)
		if err != nil {
			t.Fatal(err)
		}
		if !it.Virtual {
			plain = pid
			if err := os.Remove(string(it.Path)); err != nil {
				t.Fatal(err)
			}
			break
		}
	}
	_, err := svc.SetItemsKind(ctx, uc, []string{plain}, "audiobook", false)
	if KindOf(err) != KindConflict || !strings.Contains(err.Error(), "is not on disk") {
		t.Fatalf("a part not on disk = %v, want the missing-file conflict", err)
	}
	for _, refusal := range []error{cue, err} {
		if msg := refusal.Error(); strings.Contains(msg, "/") || strings.Contains(msg, strings.TrimPrefix(plain, "tr-")) {
			t.Errorf("the refusal carries a path or a bare pid: %q", msg)
		}
	}
}

// refuseJobOriginWrites makes every record of who started a job fail, as
// a full disk or an I/O error would.
func refuseJobOriginWrites(t *testing.T, ctx context.Context, svc *Library) {
	t.Helper()
	if _, err := svc.db.Writer().ExecContext(ctx, `CREATE TRIGGER refuse_job_origins BEFORE INSERT ON job_origins
		BEGIN SELECT RAISE(ABORT, 'refused'); END`); err != nil {
		t.Fatal(err)
	}
}

// A starter who is not an administrator is answered the kind change they
// started even when recording them as its starter failed: the job runs
// either way, and a refusal would send them to retry into its lease.
func TestAKindChangesStarterIsAnsweredWhenTheirOriginIsNotRecorded(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "uploader", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	pid := fixtureItemPIDs(t, ctx, svc, admin)[0]
	_, bare, _ := parseAPIPID(pid)
	if err := svc.db.InsertUpload(ctx, wdb.Upload{ID: "up-own", UserID: acct.User.ID, FileName: "own.flac",
		State: uploadImported, ItemPID: string(bare), CreatedAtNS: time.Now().UnixNano()}); err != nil {
		t.Fatal(err)
	}
	refuseJobOriginWrites(t, ctx, svc)

	job, err := svc.SetItemsKind(ctx, uc, []string{pid}, "audiobook", false)
	if err != nil {
		t.Fatalf("the starter's answer = %v, want the job they started", err)
	}
	if job.Kind != "set-kind" || job.PID == "" {
		t.Fatalf("answer = %+v, want the set-kind job", job)
	}
	waitFor(t, func() bool {
		j, err := svc.JobStatus(ctx, job.PID)
		return err == nil && j.State != string(model.JobRunning)
	}, "the kind change should end")
}

// kindWalkHolders reads every table and text column of waxdeck.db for
// values holding s, in any case, and counts the rows of each column that
// do: the schema is read, not listed, so a table added later is read too.
func kindWalkHolders(t *testing.T, ctx context.Context, svc *Library, s string) map[string]int {
	t.Helper()
	db := svc.db.Reader()
	strs := func(q string, args ...any) []string {
		t.Helper()
		rows, err := db.QueryContext(ctx, q, args...)
		if err != nil {
			t.Fatal(err)
		}
		defer rows.Close()
		var out []string
		for rows.Next() {
			var v string
			if err := rows.Scan(&v); err != nil {
				t.Fatal(err)
			}
			out = append(out, v)
		}
		return out
	}
	quote := func(name string) string { return `"` + strings.ReplaceAll(name, `"`, `""`) + `"` }
	out := map[string]int{}
	for _, table := range strs(`SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite\_%' ESCAPE '\'`) {
		for _, col := range strs(`SELECT name FROM pragma_table_info(?) WHERE upper(type) LIKE '%TEXT%'`, table) {
			var n int
			if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM `+quote(table)+` WHERE instr(upper(`+quote(col)+`), upper(?)) > 0`, s).Scan(&n); err != nil {
				t.Fatal(err)
			}
			if n > 0 {
				out[table+"."+col] = n
			}
		}
	}
	return out
}

// Once a kind change converts an item, no column of waxdeck.db still holds
// it under its old prefix, but for the few that must, each saying why. An
// administrator reading the audit log by the item's current pid finds the
// change and what came before it.
func TestAKindChangeLeavesNoColumnOnTheOldPrefix(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	pids := fixtureItemPIDs(t, ctx, svc, uc)
	track, other := pids[0], pids[1]
	_, bare, _ := parseAPIPID(track)
	// WaxDeck's rows naming the track by its prefixed pid: a link, a tool
	// task that ran on it and lists it among its results, a Subsonic
	// bookmark, earlier history, and the change's own audit entry.
	if _, err := svc.CreateShare(ctx, uc, track, 0, false, 0); err != nil {
		t.Fatal(err)
	}
	if err := svc.db.InsertToolTask(ctx, wdb.ToolTask{ID: "tk-kindwalk", Type: "cue-split", State: "done", ItemPID: track,
		UserID: uc.ID, Params: "{}", ResultPIDs: `["` + other + `","` + track + `"]`, CreatedAtNS: 1}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.db.Writer().ExecContext(ctx, `INSERT INTO subsonic_bookmarks (user_id, item_pid, position_ms, created_at_ns, updated_at_ns)
		VALUES (?, ?, 5000, 1, 1)`, uc.ID, track); err != nil {
		t.Fatal(err)
	}
	svc.Audit(ctx, uc, "item.edit", AuditTarget{Kind: "item", PID: track}, nil)

	job, err := svc.SetItemsKind(ctx, uc, []string{track}, "audiobook", false)
	if err != nil {
		t.Fatal(err)
	}
	_, jobPID, _ := parseAPIPID(job.PID)
	waitFor(t, func() bool {
		has, err := svc.db.HasJobOrigin(ctx, string(jobPID))
		return err == nil && !has
	}, "the kind change's follow-up should land and its end be told")

	keeps := map[string]string{
		"audit_log.detail": "an audit entry's detail is the request as made, its pids as the caller named them",
	}
	held := kindWalkHolders(t, ctx, svc, track)
	for col, n := range held {
		if _, ok := keeps[col]; !ok {
			t.Errorf("%s: %d rows still hold %s after it became a book", col, n, track)
		}
	}
	for col := range keeps {
		if held[col] == 0 {
			t.Errorf("%s holds no %s, so it needs no exception", col, track)
		}
	}
	events, err := svc.db.ListAudit(ctx, wdb.AuditFilter{TargetPID: "bk-" + string(bare)}, 0, 10)
	if err != nil {
		t.Fatal(err)
	}
	var actions []string
	for _, e := range events {
		actions = append(actions, e.Action)
	}
	if !slices.Contains(actions, "item.kind") || !slices.Contains(actions, "item.edit") {
		t.Fatalf("audit by the book's pid = %v, want the kind change and the edit before it", actions)
	}
}

// A book's own fields, roles and tags on a track are refused with the way
// a track becomes a book: by its kind, not by editing.
func TestBookOnlyEditsOnATrackPointAtTheKind(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	track := fixtureItemPIDs(t, ctx, svc, uc)[0]
	for _, c := range []struct {
		name string
		err  error
	}{
		{"narrator field", func() error {
			_, err := svc.EditItemMetadata(ctx, uc, track, map[string]string{"narrator": "Ann Reader"}, MetadataEditParams{})
			return err
		}()},
		{"narrator role", func() error {
			_, err := svc.SetItemCredits(ctx, uc, track, "narrator", []string{"Ann Reader"}, MetadataEditParams{})
			return err
		}()},
		{"NARRATOR tag", func() error {
			_, err := svc.SetItemTag(ctx, uc, track, "narrator", []string{"Ann Reader"}, MetadataEditParams{})
			return err
		}()},
		{"MEDIATYPE tag", func() error {
			_, err := svc.SetItemTag(ctx, uc, track, "MEDIATYPE", []string{"2"}, MetadataEditParams{})
			return err
		}()},
	} {
		if KindOf(c.err) != KindInvalid || !strings.Contains(c.err.Error(), "changing its kind") {
			t.Errorf("%s = %v, want a refusal pointing at the kind", c.name, c.err)
		}
	}
}

// A kind change's follow-up that fails keeps the job's origin, untold,
// so the next start's settle repeats it; once it lands the end is told
// and the origin goes.
func TestAFailedKindFollowUpIsRepeatedAtTheNextStart(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	j := &model.Job{PID: "01JZX5N8QW3F4V9T2B7KDKINDJ", Kind: "set-kind", State: model.JobDone,
		Result: `{"absorbed":{"01JZX5N8QW3F4V9T2B7KDOLD000":"01JZX5N8QW3F4V9T2B7KDNEW000"}}`}
	if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{PID: string(j.PID), UserID: uc.ID, CreatedAtNS: 1}); err != nil {
		t.Fatal(err)
	}
	runs := 0
	svc.remapHook = func(context.Context, wdb.KindMoves) error {
		runs++
		if runs == 1 {
			return errors.New("injected")
		}
		return nil
	}
	svc.settleJobOrigin(ctx, j)
	if has, err := svc.db.HasJobOrigin(ctx, string(j.PID)); err != nil || !has {
		t.Fatalf("origin after a failed follow-up = %v (%v), want it kept", has, err)
	}
	svc.openedAtNS = time.Now().UnixNano() + 1 // the next start
	svc.settleJobOrigin(ctx, j)
	if has, err := svc.db.HasJobOrigin(ctx, string(j.PID)); err != nil || has || runs != 2 {
		t.Fatalf("origin after the repeat = %v (%v), runs %d; want it settled after a second run", has, err, runs)
	}
}

// A follow-up that could not read the catalog failed like any other:
// the origin stays for the next start, rather than the rows staying
// where they were for good.
func TestAKindFollowUpThatCannotReadTheCatalogIsRepeated(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	const converted = "01JZX5N8QW3F4V9T2B7KDCONV00"
	j := &model.Job{PID: "01JZX5N8QW3F4V9T2B7KDKINDR", Kind: "set-kind", State: model.JobDone,
		Result: `{"converted":["` + converted + `"]}`}
	if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{PID: string(j.PID), UserID: uc.ID, CreatedAtNS: 1}); err != nil {
		t.Fatal(err)
	}
	reads := 0
	svc.kindReadHook = func(_ context.Context, pid model.PID) (*model.ItemView, error) {
		reads++
		if reads == 1 {
			return nil, errors.New("database is closed")
		}
		return &model.ItemView{PID: pid, Kind: model.KindBook}, nil
	}
	var remapped []wdb.KindMoves
	svc.remapHook = func(_ context.Context, m wdb.KindMoves) error {
		remapped = append(remapped, m)
		return nil
	}
	svc.settleJobOrigin(ctx, j)
	if has, err := svc.db.HasJobOrigin(ctx, string(j.PID)); err != nil || !has || len(remapped) != 0 {
		t.Fatalf("after an unreadable catalog: origin %v (%v), remaps %v; want the origin kept and nothing moved", has, err, remapped)
	}
	svc.openedAtNS = time.Now().UnixNano() + 1 // the next start
	svc.settleJobOrigin(ctx, j)
	if has, err := svc.db.HasJobOrigin(ctx, string(j.PID)); err != nil || has ||
		len(remapped) != 1 || remapped[0].Kinds[converted] != "audiobook" {
		t.Fatalf("after the repeat: origin %v (%v), remaps %v; want the book's kind moved and the origin gone", has, err, remapped)
	}
}

// A kind change nobody here started has no origin to keep its follow-up
// for a repeat; one of no one's is left for the next start.
func TestAnUnownedKindFollowUpThatFailsIsKeptForTheNextStart(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	j := &model.Job{PID: "01JZX5N8QW3F4V9T2B7KDKINDU", Kind: "set-kind", State: model.JobDone,
		Result: `{"converted":["01JZX5N8QW3F4V9T2B7KDCONV01"]}`}
	failing := true
	svc.kindReadHook = func(_ context.Context, pid model.PID) (*model.ItemView, error) {
		if failing {
			return nil, errors.New("database is closed")
		}
		return &model.ItemView{PID: pid, Kind: model.KindBook}, nil
	}
	runs := 0
	svc.remapHook = func(context.Context, wdb.KindMoves) error {
		runs++
		return nil
	}
	svc.onJobFinished(ctx, j)
	if has, err := svc.db.HasJobOrigin(ctx, string(j.PID)); err != nil || !has {
		t.Fatalf("origin after a failed unowned follow-up = %v (%v), want one kept", has, err)
	}
	failing = false
	svc.openedAtNS = time.Now().UnixNano() + 1
	svc.settleJobOrigin(ctx, j)
	if has, err := svc.db.HasJobOrigin(ctx, string(j.PID)); err != nil || has || runs != 1 {
		t.Fatalf("after the repeat: origin %v (%v), runs %d; want it settled once", has, err, runs)
	}
}

// A kind change nobody here started whose follow-up fails is tried once a
// pass: the origin kept for it is the next start's to settle, not this
// pass's to repeat on the one write connection.
func TestAnUnownedKindFollowUpThatFailsIsTriedOncePerPass(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	j := &model.Job{PID: "01JZX5N8QW3F4V9T2B7KDKINDO", Kind: "set-kind", State: model.JobDone,
		Result: `{"converted":["01JZX5N8QW3F4V9T2B7KDCONV01"]}`}
	svc.kindReadHook = func(_ context.Context, pid model.PID) (*model.ItemView, error) {
		return &model.ItemView{PID: pid, Kind: model.KindBook}, nil
	}
	runs := 0
	svc.remapHook = func(context.Context, wdb.KindMoves) error {
		runs++
		return errors.New("disk I/O error")
	}
	svc.onJobFinished(ctx, j)
	if has, err := svc.db.HasJobOrigin(ctx, string(j.PID)); err != nil || !has || runs != 1 {
		t.Fatalf("origin %v (%v), remaps %d; want one kept and one remap", has, err, runs)
	}
}

// A part a split minted is credited to the book it came from: the book
// on its album, or the one book the change split when there was only
// that one. With a second book folded into a track already there, an
// unmatched part could be either's, so it is credited to neither.
func TestASplitPartIsCreditedOnlyToTheBookItCameFrom(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := newCatalogFixture(t)
	const a, b, loose, part = "01JZX5N8QW3F4V9T2B7KDBOOKA0", "01JZX5N8QW3F4V9T2B7KDBOOKB0", "01JZX5N8QW3F4V9T2B7KDLOOSE0", "01JZX5N8QW3F4V9T2B7KDPART00"
	albums := map[model.PID]model.PID{a: "01JZX5N8QW3F4V9T2B7KDALBA00", loose: "01JZX5N8QW3F4V9T2B7KDALBL00", part: "01JZX5N8QW3F4V9T2B7KDALBP00"}
	svc.kindReadHook = func(_ context.Context, pid model.PID) (*model.ItemView, error) {
		return &model.ItemView{PID: pid, Kind: model.KindTrack, AlbumPID: albums[pid]}, nil
	}
	for _, c := range []struct {
		name, result string
		want         map[string]string
	}{
		{"one book split", `{"converted":["` + a + `"],"created":["` + part + `"]}`, map[string]string{part: a}},
		{"a second book folded", `{"converted":["` + a + `"],"absorbed":{"` + b + `":"` + loose + `"},"created":["` + part + `"]}`, map[string]string{}},
	} {
		var got wdb.KindMoves
		svc.remapHook = func(_ context.Context, m wdb.KindMoves) error {
			got = m
			return nil
		}
		j := &model.Job{PID: model.PID("01JZX5N8QW3F4V9T2B7KD" + strings.ToUpper(c.name[:3]) + "JOB"), Kind: "set-kind", State: model.JobDone, Result: c.result}
		if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{PID: string(j.PID), UserID: uc.ID, CreatedAtNS: 1}); err != nil {
			t.Fatal(err)
		}
		svc.settleJobOrigin(ctx, j)
		if len(got.Created) != len(c.want) || (len(c.want) > 0 && got.Created[part] != c.want[part]) {
			t.Errorf("%s: created = %v, want %v", c.name, got.Created, c.want)
		}
	}
}

// A jobs list reads each item its jobs name once, however many jobs and
// chapters name it: an album turned into one book names the same
// survivor for every chapter, and the list keeps every such change.
func TestAJobsListReadsEachItemOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, _ := newCatalogFixture(t)
	const book = "01JZX5N8QW3F4V9T2B7KDBOOK00"
	reads := map[model.PID]int{}
	svc.kindReadHook = func(_ context.Context, pid model.PID) (*model.ItemView, error) {
		reads[pid]++
		return &model.ItemView{PID: pid, Kind: model.KindBook}, nil
	}
	var jobs []Job
	for j := range 3 {
		tally := &KindTallyDTO{Converted: []string{book}, Absorbed: map[string]string{}}
		for i := range 100 {
			tally.Absorbed[fmt.Sprintf("01JZX5N8QW3F4V9T2B7KD%d%04d", j, i)] = book
		}
		jobs = append(jobs, Job{Kind: "set-kind", SetKind: tally})
	}
	svc.nameJobTargets(ctx, jobs)
	if reads[book] != 1 {
		t.Fatalf("the survivor was read %d times, want once", reads[book])
	}
	if k := jobs[2].SetKind; k.Converted[0] != "bk-"+book || k.Absorbed["tr-01JZX5N8QW3F4V9T2B7KD20042"] != "bk-"+book {
		t.Fatalf("tally = %+v, want every pid in its current form", k)
	}
}

// A part split out by a change someone who is not an administrator
// started, whose source the report cannot say, is granted to them: every
// item they named was theirs to edit, so whichever book it came from, it
// is too. An administrator's change grants nothing on that guess.
func TestAnUnplacedSplitPartIsGrantedToAStarterWhoMayEditEveryBook(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "splitter", Password: "correct-horse", UploadEnabled: true})
	if err != nil {
		t.Fatal(err)
	}
	const a, b, part = "01JZX5N8QW3F4V9T2B7KDBOOKA0", "01JZX5N8QW3F4V9T2B7KDBOOKB0", "01JZX5N8QW3F4V9T2B7KDPART00"
	svc.kindReadHook = func(_ context.Context, pid model.PID) (*model.ItemView, error) {
		return &model.ItemView{PID: pid, Kind: model.KindTrack}, nil
	}
	for _, c := range []struct {
		name, starter string
		want          map[string]string
	}{
		{"a curator's split", acct.User.ID, map[string]string{part: acct.User.ID}},
		{"an administrator's split", admin.ID, map[string]string{}},
	} {
		var got wdb.KindMoves
		svc.remapHook = func(_ context.Context, m wdb.KindMoves) error {
			got = m
			return nil
		}
		j := &model.Job{PID: model.PID("01JZX5N8QW3F4V9T2B7KD" + strings.ToUpper(c.name[:3]) + "JOB"), Kind: "set-kind",
			State: model.JobDone, Result: `{"converted":["` + a + `","` + b + `"],"created":["` + part + `"]}`}
		if err := svc.db.InsertJobOrigin(ctx, wdb.JobOrigin{PID: string(j.PID), UserID: c.starter, CreatedAtNS: 1}); err != nil {
			t.Fatal(err)
		}
		svc.settleJobOrigin(ctx, j)
		if len(got.Created) != 0 || len(got.Grants) != len(c.want) || got.Grants[part] != c.want[part] {
			t.Errorf("%s: created %v, grants %v; want no source and grants %v", c.name, got.Created, got.Grants, c.want)
		}
	}
}

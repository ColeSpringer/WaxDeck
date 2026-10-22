package db

import (
	"context"
	"encoding/json"
	"maps"
	"slices"
	"testing"
	"time"
)

// A kind change's follow-up moves WaxDeck's rows: a converted item keeps
// its rows under its new kind, a folded-away item's rows go to the item
// that took it in, a share of a folded-away item is revoked rather than
// widened to the whole book, and an upload's edit grant never moves. A
// second run changes nothing.
func TestRemapItemsAfterAKindChange(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.CreateUser(ctx, mkUser("us-1", "u1", nil), false); err != nil {
		t.Fatal(err)
	}
	const book, folded, other = "01AAAAAAAAAAAAAAAAAAAAAAAA", "01BBBBBBBBBBBBBBBBBBBBBBBB", "01CCCCCCCCCCCCCCCCCCCCCCCC"
	const solo, split, part = "01DDDDDDDDDDDDDDDDDDDDDDDD", "01EEEEEEEEEEEEEEEEEEEEEEEE", "01FFFFFFFFFFFFFFFFFFFFFFFF"
	now := time.Now()
	for _, s := range []Share{
		{ID: "sh-book", UserID: "us-1", TargetPID: "tr-" + book, TargetKind: "track", CreatedAt: now},
		{ID: "sh-folded", UserID: "us-1", TargetPID: "tr-" + folded, TargetKind: "track", CreatedAt: now},
		{ID: "sh-other", UserID: "us-1", TargetPID: "tr-" + other, TargetKind: "track", CreatedAt: now},
		{ID: "sh-solo", UserID: "us-1", TargetPID: "tr-" + solo, TargetKind: "track", CreatedAt: now},
	} {
		if err := d.InsertShare(ctx, s); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := d.InsertListens(ctx, []ListenSession{
		{UserID: "us-1", SessionID: "s1", ItemPID: book, MediaType: "music", StartedAt: now, MsPlayed: 1000},
		{UserID: "us-1", SessionID: "s2", ItemPID: folded, MediaType: "music", StartedAt: now, MsPlayed: 1000},
		{UserID: "us-1", SessionID: "s3", ItemPID: other, MediaType: "music", StartedAt: now, MsPlayed: 1000},
	}); err != nil {
		t.Fatal(err)
	}
	for _, s := range []struct {
		pid string
		ns  int64
	}{{book, 100}, {folded, 300}} {
		if err := d.StampPlayState(ctx, "us-1", s.pid, s.ns, 0); err != nil {
			t.Fatal(err)
		}
	}
	for _, pid := range []string{book, folded} {
		if err := d.UpsertHealthRow(ctx, HealthRow{ItemPID: pid, MediaType: "music", SweptAtNS: 1}); err != nil {
			t.Fatal(err)
		}
	}
	if _, err := d.w.ExecContext(ctx, `INSERT INTO uploads (id, user_id, file_name, size_bytes, media_type, state, created_at_ns, item_pid)
		VALUES ('up-1', 'us-1', 'two.mp3', 1, 'music', 'imported', 1, ?)`, folded); err != nil {
		t.Fatal(err)
	}
	if _, err := d.w.ExecContext(ctx, `INSERT INTO uploads (id, user_id, file_name, size_bytes, media_type, state, created_at_ns, item_pid)
		VALUES ('up-2', 'us-1', 'book.mp3', 1, 'audiobook', 'imported', 1, ?)`, split); err != nil {
		t.Fatal(err)
	}
	if _, err := d.w.ExecContext(ctx, `INSERT INTO playlist_source_map (source, entry_id, item_pid, updated_at_ns) VALUES ('yt', 'e1', ?, 1)`, folded); err != nil {
		t.Fatal(err)
	}

	moves := KindMoves{
		Absorbed: map[string]string{folded: book},
		Kinds:    map[string]string{book: "audiobook", solo: "audiobook", split: "music"},
		// A book split into tracks: its new part is its uploader's too.
		Created: map[string]string{part: split},
	}
	for run := range 2 {
		if err := d.RemapItems(ctx, moves); err != nil {
			t.Fatal(err)
		}
		share := func(id string) *Share {
			s, err := d.ShareByID(ctx, id)
			if err != nil {
				t.Fatal(err)
			}
			return s
		}
		// The survivor took a chapter in, so its track's link would now
		// serve the whole book: revoked like the folded one's. A track
		// that became a book alone keeps its link, on the book.
		if s := share("sh-book"); !s.Revoked {
			t.Fatalf("run %d: the survivor's share = %+v, want it revoked rather than widened", run, s)
		}
		if s := share("sh-solo"); s.TargetPID != "bk-"+solo || s.TargetKind != "book" || s.Revoked {
			t.Fatalf("run %d: converted share = %+v, want it on the book", run, s)
		}
		if s := share("sh-folded"); !s.Revoked || s.TargetPID != "tr-"+folded {
			t.Fatalf("run %d: folded-away share = %+v, want it revoked where it was", run, s)
		}
		if s := share("sh-other"); s.TargetPID != "tr-"+other || s.Revoked {
			t.Fatalf("run %d: an untouched share = %+v", run, s)
		}
		var listens [][2]string
		rows, err := d.r.QueryContext(ctx, `SELECT item_pid, media_type FROM listen_sessions ORDER BY session_id`)
		if err != nil {
			t.Fatal(err)
		}
		for rows.Next() {
			var l [2]string
			if err := rows.Scan(&l[0], &l[1]); err != nil {
				t.Fatal(err)
			}
			listens = append(listens, l)
		}
		rows.Close()
		want := [][2]string{{book, "audiobook"}, {book, "audiobook"}, {other, "music"}}
		for i := range want {
			if i >= len(listens) || listens[i] != want[i] {
				t.Fatalf("run %d: listens = %v, want %v", run, listens, want)
			}
		}
		if s, err := d.PlayStamp(ctx, "us-1", book); err != nil || s.PositionNS != 300 {
			t.Fatalf("run %d: survivor stamp = %+v (%v), want the newer 300", run, s, err)
		}
		if s, err := d.PlayStamp(ctx, "us-1", folded); err != nil || s.PositionNS != 0 {
			t.Fatalf("run %d: folded-away stamp = %+v (%v), want none", run, s, err)
		}
		var media string
		if err := d.r.QueryRowContext(ctx, `SELECT media_type FROM health_index WHERE item_pid = ?`, book).Scan(&media); err != nil || media != "audiobook" {
			t.Fatalf("run %d: health row = %q (%v), want audiobook", run, media, err)
		}
		var n int
		if err := d.r.QueryRowContext(ctx, `SELECT COUNT(*) FROM health_index WHERE item_pid = ?`, folded).Scan(&n); err != nil || n != 0 {
			t.Fatalf("run %d: folded-away health rows = %d (%v), want none", run, n, err)
		}
		var grant, mapped string
		if err := d.r.QueryRowContext(ctx, `SELECT item_pid FROM uploads WHERE id = 'up-1'`).Scan(&grant); err != nil || grant != folded {
			t.Fatalf("run %d: upload grant = %q (%v), want it left on the folded-away item", run, grant, err)
		}
		if err := d.r.QueryRowContext(ctx, `SELECT item_pid FROM playlist_source_map WHERE entry_id = 'e1'`).Scan(&mapped); err != nil || mapped != book {
			t.Fatalf("run %d: playlist source map = %q (%v), want the book", run, mapped, err)
		}
		if owns, err := d.UploadOwnsItem(ctx, "us-1", part); err != nil || !owns {
			t.Fatalf("run %d: the split's new part owned = %v (%v), want its book's uploader to keep it", run, owns, err)
		}
		if owned, err := d.UploadedItemPIDs(ctx, []string{part}); err != nil || !owned[part] {
			t.Fatalf("run %d: the new part reads as uploaded = %v (%v), want it", run, owned, err)
		}
	}
}

// A book whose part joined a track already holding its audio folds into
// that track, which stays a track: the book's links go, the track's own
// stay, whoever made them.
func TestABookFoldedIntoATrackKeepsTheTracksLinks(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	if err := d.CreateUser(ctx, mkUser("us-1", "u1", nil), false); err != nil {
		t.Fatal(err)
	}
	const book, loose = "01GGGGGGGGGGGGGGGGGGGGGGGG", "01HHHHHHHHHHHHHHHHHHHHHHHH"
	now := time.Now()
	for _, s := range []Share{
		{ID: "sh-book", UserID: "us-1", TargetPID: "bk-" + book, TargetKind: "book", CreatedAt: now},
		{ID: "sh-loose", UserID: "us-1", TargetPID: "tr-" + loose, TargetKind: "track", CreatedAt: now},
	} {
		if err := d.InsertShare(ctx, s); err != nil {
			t.Fatal(err)
		}
	}
	if err := d.RemapItems(ctx, KindMoves{
		Absorbed: map[string]string{book: loose},
		Kinds:    map[string]string{loose: "music"},
	}); err != nil {
		t.Fatal(err)
	}
	for id, revoked := range map[string]bool{"sh-book": true, "sh-loose": false} {
		if s, err := d.ShareByID(ctx, id); err != nil || s.Revoked != revoked {
			t.Fatalf("%s = %+v (%v), want revoked %v", id, s, err, revoked)
		}
	}
}

// A converted item's tool tasks, audit entries and Subsonic bookmarks take
// its new prefix, inside a task's list of results too, a bookmark held
// under both forms keeping the newer. A folded-away item's stay where they
// were: what was done to it, and a place inside it, mean nothing on the
// item that took it in. A list that is not one is left alone, and a
// second run changes nothing.
func TestAKindChangeMovesTasksAuditEntriesAndBookmarks(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	for _, id := range []string{"us-1", "us-2"} {
		if err := d.CreateUser(ctx, mkUser(id, id, nil), false); err != nil {
			t.Fatal(err)
		}
	}
	// book was a track and took folded in; split was a book and is a track.
	const book, folded, split, other = "01KKKKKKKKKKKKKKKKKKKKKKKK", "01LLLLLLLLLLLLLLLLLLLLLLLL", "01MMMMMMMMMMMMMMMMMMMMMMMM", "01NNNNNNNNNNNNNNNNNNNNNNNN"
	for _, task := range []ToolTask{
		{ID: "tk-book", ItemPID: "tr-" + book, ResultPIDs: `["tr-` + book + `","tr-` + other + `","tr-` + folded + `","bk-` + split + `"]`},
		{ID: "tk-folded", ItemPID: "tr-" + folded, ResultPIDs: `["tr-` + folded + `"]`},
		{ID: "tk-split", ItemPID: "bk-" + split, ResultPIDs: "[]"},
		{ID: "tk-garbled", ItemPID: "lb-" + other, ResultPIDs: `not a list: "tr-` + book + `"`},
	} {
		task.Type, task.State, task.Params, task.CreatedAtNS = "cue-split", "done", "{}", 1
		if err := d.InsertToolTask(ctx, task); err != nil {
			t.Fatal(err)
		}
	}
	for action, target := range map[string]string{
		"a.book": "tr-" + book, "a.folded": "tr-" + folded, "a.split": "bk-" + split, "a.library": "lb-" + other,
	} {
		if err := d.AppendAudit(ctx, AuditEvent{Action: action, TargetKind: "item", TargetPID: target, Detail: "{}", CreatedAtNS: 1}); err != nil {
			t.Fatal(err)
		}
	}
	for _, b := range []struct {
		user, pid string
		pos, atNS int64
	}{
		{"us-1", "tr-" + book, 1000, 1}, {"us-1", "tr-" + folded, 2000, 1},
		// Held under both forms: the old one newer for us-1, older for us-2.
		{"us-1", "bk-" + split, 3000, 9}, {"us-1", "tr-" + split, 4000, 5},
		{"us-2", "bk-" + split, 3000, 1}, {"us-2", "tr-" + split, 4000, 5},
	} {
		if _, err := d.w.ExecContext(ctx, `INSERT INTO subsonic_bookmarks (user_id, item_pid, position_ms, created_at_ns, updated_at_ns)
			VALUES (?, ?, ?, 1, ?)`, b.user, b.pid, b.pos, b.atNS); err != nil {
			t.Fatal(err)
		}
	}

	moves := KindMoves{
		Absorbed: map[string]string{folded: book},
		Kinds:    map[string]string{book: "audiobook", split: "music"},
	}
	for run := range 2 {
		if err := d.RemapItems(ctx, moves); err != nil {
			t.Fatal(err)
		}
		for id, want := range map[string]struct {
			item    string
			results []string
		}{
			"tk-book":   {"bk-" + book, []string{"bk-" + book, "tr-" + other, "tr-" + folded, "tr-" + split}},
			"tk-folded": {"tr-" + folded, []string{"tr-" + folded}},
			"tk-split":  {"tr-" + split, []string{}},
		} {
			task, err := d.ToolTaskByID(ctx, id)
			if err != nil {
				t.Fatal(err)
			}
			var results []string
			if err := json.Unmarshal([]byte(task.ResultPIDs), &results); err != nil {
				t.Fatalf("run %d: %s results %q: %v", run, id, task.ResultPIDs, err)
			}
			if task.ItemPID != want.item || !slices.Equal(results, want.results) {
				t.Fatalf("run %d: %s = item %s, results %v; want %s, %v", run, id, task.ItemPID, results, want.item, want.results)
			}
		}
		if task, err := d.ToolTaskByID(ctx, "tk-garbled"); err != nil || task.ResultPIDs != `not a list: "tr-`+book+`"` {
			t.Fatalf("run %d: the garbled list = %q (%v), want it left alone", run, task.ResultPIDs, err)
		}
		for action, want := range map[string]string{
			"a.book": "bk-" + book, "a.folded": "tr-" + folded, "a.split": "tr-" + split, "a.library": "lb-" + other,
		} {
			var got string
			if err := d.r.QueryRowContext(ctx, `SELECT target_pid FROM audit_log WHERE action = ?`, action).Scan(&got); err != nil || got != want {
				t.Fatalf("run %d: %s target = %q (%v), want %q", run, action, got, err, want)
			}
		}
		bookmarks := map[string]int64{}
		rows, err := d.r.QueryContext(ctx, `SELECT user_id, item_pid, position_ms FROM subsonic_bookmarks`)
		if err != nil {
			t.Fatal(err)
		}
		for rows.Next() {
			var user, pid string
			var pos int64
			if err := rows.Scan(&user, &pid, &pos); err != nil {
				t.Fatal(err)
			}
			bookmarks[user+" "+pid] = pos
		}
		rows.Close()
		want := map[string]int64{
			"us-1 bk-" + book: 1000, "us-1 tr-" + folded: 2000, "us-1 tr-" + split: 3000, "us-2 tr-" + split: 4000,
		}
		if !maps.Equal(bookmarks, want) {
			t.Fatalf("run %d: bookmarks = %v, want %v", run, bookmarks, want)
		}
	}
}

// A remap that fails part way leaves none of its map tables on the write
// connection, its transaction taking their creation back with the rest,
// so the next run starts clean.
func TestARemapThatFailsLeavesNoMapTablesBehind(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	const pid = "01JJJJJJJJJJJJJJJJJJJJJJJJ"
	if err := d.UpsertHealthRow(ctx, HealthRow{ItemPID: pid, MediaType: "music", SweptAtNS: 1}); err != nil {
		t.Fatal(err)
	}
	// The one write connection's own temp table, which a fresh connection
	// would not have: what is read below is the connection the remap ran on.
	for _, q := range []string{
		`CREATE TEMP TABLE remap_probe (x)`,
		`CREATE TRIGGER refuse_health BEFORE UPDATE ON health_index BEGIN SELECT RAISE(ABORT, 'refused'); END`,
	} {
		if _, err := d.w.ExecContext(ctx, q); err != nil {
			t.Fatal(err)
		}
	}
	moves := KindMoves{Kinds: map[string]string{pid: "audiobook"}}
	if err := d.RemapItems(ctx, moves); err == nil {
		t.Fatal("the remap passed a refused write")
	}
	var left []string
	rows, err := d.w.QueryContext(ctx, `SELECT name FROM sqlite_temp_master WHERE type = 'table'`)
	if err != nil {
		t.Fatal(err)
	}
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatal(err)
		}
		left = append(left, name)
	}
	rows.Close()
	if len(left) != 1 || left[0] != "remap_probe" {
		t.Fatalf("temp tables after the failed run = %v, want the probe alone", left)
	}
	if _, err := d.w.ExecContext(ctx, `DROP TRIGGER refuse_health`); err != nil {
		t.Fatal(err)
	}
	if err := d.RemapItems(ctx, moves); err != nil {
		t.Fatalf("the run after a failed one = %v", err)
	}
	var media string
	if err := d.r.QueryRowContext(ctx, `SELECT media_type FROM health_index WHERE item_pid = ?`, pid).Scan(&media); err != nil || media != "audiobook" {
		t.Fatalf("health row = %q (%v), want the run after the failed one to land", media, err)
	}
}

// A part granted to an account directly is that account's to edit after
// the remap, and only theirs; one granted to an account deleted since
// grants nothing and stops nothing else.
func TestARemapGrantsAPartToTheAccountNamed(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	for _, u := range []string{"us-split", "us-other"} {
		if err := d.CreateUser(ctx, mkUser(u, u, nil), false); err != nil {
			t.Fatal(err)
		}
	}
	const part, orphan = "01JZX5N8QW3F4V9T2B7KDPART00", "01JZX5N8QW3F4V9T2B7KDPART01"
	if err := d.RemapItems(ctx, KindMoves{Grants: map[string]string{part: "us-split", orphan: "us-gone"}}); err != nil {
		t.Fatal(err)
	}
	for user, want := range map[string]bool{"us-split": true, "us-other": false} {
		if owns, err := d.UploadOwnsItem(ctx, user, part); err != nil || owns != want {
			t.Errorf("%s may edit the part = %v (%v), want %v", user, owns, err, want)
		}
	}
}

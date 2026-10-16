package api

import (
	"context"
	"os"
	"slices"
	"strings"
	"testing"
	"time"

	"github.com/colespringer/waxdeck/fixtures"

	"github.com/colespringer/waxdeck/server/internal/service"
)

// waitForJobDone polls a job until it ends and answers it.
func waitForJobDone(t *testing.T, h *harness, token, pid string) Job {
	t.Helper()
	for deadline := time.Now().Add(30 * time.Second); ; time.Sleep(25 * time.Millisecond) {
		j := decodeStatus[Job](t, reqAs(t, h, "GET", "/api/v1/jobs/"+pid, token, nil), 200, "job")
		if j.State != "running" && j.State != "queued" {
			return j
		}
		if time.Now().After(deadline) {
			t.Fatalf("job %s did not finish", pid)
		}
	}
}

// looseTracks scans the loose two-part book into the library, as the
// music it reads as, and answers its tracks' pids in reading order.
func looseTracks(t *testing.T, h *harness) []string {
	t.Helper()
	if _, err := fixtures.GenerateLooseMP3Book(h.library); err != nil {
		t.Fatal(err)
	}
	h.rescanAndWait(t)
	return []string{h.itemTitled(t, h.token, "Chapter One").Pid, h.itemTitled(t, h.token, "Chapter Two").Pid}
}

// waitUntilKindChangeTold waits for a kind change's end to reach its
// starter's inbox, which its follow-up comes before.
func waitUntilKindChangeTold(t *testing.T, h *harness, token, jobPID string) {
	t.Helper()
	for deadline := time.Now().Add(10 * time.Second); ; time.Sleep(25 * time.Millisecond) {
		inbox := decode[NotificationPage](t, reqAs(t, h, "GET", "/api/v1/users/me/notifications?limit=100", token, nil))
		if slices.ContainsFunc(inbox.Notifications, func(n Notification) bool {
			return n.TargetPid != nil && *n.TargetPid == jobPID
		}) {
			return
		}
		if time.Now().After(deadline) {
			t.Fatalf("the end of %s never reached its starter", jobPID)
		}
	}
}

// setKind asks for a kind change as token and answers the finished job.
func setKind(t *testing.T, h *harness, token string, pids []string, mediaType string) Job {
	t.Helper()
	started := decodeStatus[Job](t, postJSONAs(t, h, token, "/api/v1/items/kind",
		map[string]any{"pids": pids, "mediaType": mediaType}), 202, "kind change")
	if started.Kind != "set-kind" {
		t.Fatalf("started job = %+v, want a set-kind job", started)
	}
	return waitForJobDone(t, h, token, started.Pid)
}

// Two tracks that make one book become it: the first keeps its pid
// under the book's prefix, the second folds into it, the result says
// both, and the old track pids answer 404.
func TestTreatAnAlbumAsAnAudiobook(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	tracks := looseTracks(t, h)
	book := "bk-" + strings.TrimPrefix(tracks[0], "tr-")
	var shares []string
	for _, pid := range tracks {
		shares = append(shares, decodeStatus[Share](t, h.postJSON(t, "/api/v1/shares",
			map[string]any{"pid": pid}), 201, "a share of "+pid).Pid)
	}

	j := setKind(t, h, h.token, tracks, "audiobook")
	if j.State != "done" || j.Result == nil {
		t.Fatalf("job = %+v, want done with a result", j)
	}
	// Tasks lists it finished, its result line with it, unlike the
	// per-item jobs a burst of which would push the passes out.
	if !slices.ContainsFunc(decode[JobList](t, get(t, h.ts, "/api/v1/jobs?limit=50", h.token)).Jobs,
		func(l Job) bool { return l.Pid == j.Pid && l.Result != nil }) {
		t.Fatalf("the finished kind change %s is not listed", j.Pid)
	}
	// WaxDeck's own rows follow: a link to one chapter is revoked rather
	// than widened into the whole book, the folded chapter's and the
	// first's alike, since the first now carries every part.
	for deadline := time.Now().Add(10 * time.Second); ; time.Sleep(25 * time.Millisecond) {
		listed := map[string]Share{}
		for _, sh := range decode[SharePage](t, get(t, h.ts, "/api/v1/shares", h.token)).Shares {
			listed[sh.Pid] = sh
		}
		_, firstListed := listed[shares[0]]
		_, foldedListed := listed[shares[1]]
		if !firstListed && !foldedListed {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("shares after the change = %+v, want both chapter links revoked", listed)
		}
	}
	res := *j.Result
	converted, _ := res["converted"].([]any)
	absorbed, _ := res["absorbed"].(map[string]any)
	if len(converted) != 1 || converted[0] != book || absorbed[tracks[1]] != book {
		t.Fatalf("result = %v, want %s converted and %s folded into it", res, book, tracks[1])
	}
	detail := decodeStatus[BookDetail](t, get(t, h.ts, "/api/v1/books/"+book, h.token), 200, "the book")
	if len(detail.Parts) != 2 {
		t.Fatalf("book parts = %d, want both chapters", len(detail.Parts))
	}
	// A queue, a playlist or a shelf still holding the first chapter's
	// track pid reaches the book it became, under its current pid; the
	// folded chapter is gone.
	if it := decodeStatus[Item](t, get(t, h.ts, "/api/v1/items/"+tracks[0], h.token), 200, "the old track pid"); it.Pid != book {
		t.Fatalf("old track pid answers %s, want the book %s", it.Pid, book)
	}
	if d := decodeStatus[BookDetail](t, get(t, h.ts, "/api/v1/books/"+tracks[0], h.token), 200, "the book under its old prefix"); d.Pid != book {
		t.Fatalf("book read by its old pid = %s, want %s", d.Pid, book)
	}
	wantStatus(t, get(t, h.ts, "/api/v1/items/"+tracks[1], h.token), 404, "the folded chapter")
	// A stream started from the old pid plays the whole book, part by part,
	// with the listener's settings for the book.
	ctx := context.Background()
	if parts, err := h.svc.BookParts(ctx, tracks[0]); err != nil || len(parts) != 2 {
		t.Fatalf("parts laid out for the old pid = %v (%v), want the book's two", parts, err)
	}
	wantStatus(t, h.putJSON(t, "/api/v1/books/"+book+"/settings", map[string]any{"voiceBoost": true}), 200, "book settings")
	uc, err := h.svc.UserCtxByID(ctx, adminUserID(t, h))
	if err != nil {
		t.Fatal(err)
	}
	if !h.svc.EffectiveVoiceBoost(ctx, uc, tracks[0]) {
		t.Fatal("the old track pid plays the book without its stored voice boost")
	}
}

// A Subsonic client keeps the ids it was handed, and a stream follows the
// item's kind, not its pid's prefix: a track's id that became a book in
// parts streams the whole book joined, with the engine and without it,
// and the book's id turned back into a track streams the track.
func TestSubsonicStreamFollowsAKindChange(t *testing.T) {
	t.Parallel()
	for name, c := range map[string]struct {
		harness func(*testing.T) *harness
		joined  func(loc string) bool
	}{
		"with the engine": {
			harness: func(t *testing.T) *harness { return newHarness(t) },
			joined:  func(loc string) bool { return redirectQuery(t, loc).Get("join") == "1" },
		},
		"without the engine": {
			harness: newHarnessDirect,
			joined:  func(loc string) bool { return redirectQuery(t, loc).Get(service.JoinKey) == "1" },
		},
	} {
		t.Run(name, func(t *testing.T) {
			h := c.harness(t)
			secret := newSubsonicSecret(t, h)
			tracks := looseTracks(t, h)
			stream := func(id string) string {
				return streamRedirect(t, h, "/rest/stream.view?apiKey="+secret+"&id="+id)
			}
			if loc := stream(tracks[0]); c.joined(loc) {
				t.Fatalf("a track streams as %s, want itself", loc)
			}
			setKind(t, h, h.token, tracks, "audiobook")
			if loc := stream(tracks[0]); !c.joined(loc) {
				t.Fatalf("the track's id of the book it became streams as %s, want the book joined", loc)
			}
			// The app's play-info reads the kind the same way: a position
			// in the second chapter resolves to the book's second part.
			pi := decode[PlayInfo](t, get(t, h.ts, "/api/v1/items/"+tracks[0]+"/play-info?positionMs=3500", h.token))
			if pi.PartCount == nil || *pi.PartCount != 2 || pi.PartIndex == nil || *pi.PartIndex != 1 {
				t.Fatalf("play-info 3.5 s into the track's id of the book = parts %v, index %v; want part two of two", pi.PartCount, pi.PartIndex)
			}
			book := "bk-" + strings.TrimPrefix(tracks[0], "tr-")
			setKind(t, h, h.token, []string{book}, "music")
			if loc := stream(book); c.joined(loc) {
				t.Fatalf("the book's id of the track it became streams as %s, want the track", loc)
			}
		})
	}
}

// A book turned back into tracks is gone from /books: 404, not the
// catalog's "not a book".
func TestTreatABookAsMusicAnswers404NotInvalid(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	tracks := looseTracks(t, h)
	book := "bk-" + strings.TrimPrefix(tracks[0], "tr-")
	setKind(t, h, h.token, tracks, "audiobook")

	j := setKind(t, h, h.token, []string{book}, "music")
	if j.State != "done" {
		t.Fatalf("job = %+v, want done", j)
	}
	wantStatus(t, get(t, h.ts, "/api/v1/books/"+book, h.token), 404, "the former book")
	wantStatus(t, get(t, h.ts, "/api/v1/items/"+tracks[0], h.token), 200, "its first part, a track again")
	// A queue still holding the book's pid streams the track it became.
	ctx := context.Background()
	if parts, err := h.svc.BookParts(ctx, book); err != nil || parts != nil {
		t.Fatalf("parts laid out for the former book's pid = %v (%v), want the track as itself", parts, err)
	}
	// A shelf that pinned the book hears it departed, so the pin goes.
	uc, err := h.svc.UserCtxByID(ctx, adminUserID(t, h))
	if err != nil {
		t.Fatal(err)
	}
	if cards, gone, err := h.svc.EntityCards(ctx, uc, []string{book}); err != nil || len(cards) != 0 || len(gone) != 1 || gone[0] != book {
		t.Fatalf("cards for the pinned former book = %v, departed %v (%v), want it departed", cards, gone, err)
	}
}

// Only someone who may edit every item named may change their kind:
// a plain account is refused, the uploader of an item is not.
func TestKindChangeNeedsCurateRights(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	tracks := looseTracks(t, h)
	wantStatus(t, postJSONAs(t, h, bob, "/api/v1/items/kind",
		map[string]any{"pids": tracks, "mediaType": "audiobook"}), 403, "an account that may not edit them")

	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "lecture", Codec: fixtures.CodecMP3, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "A Lecture", "ARTIST": "Speaker", "ALBUM": "Lectures"},
	})
	if err != nil {
		t.Fatal(err)
	}
	pid := importAs(t, h, bob, paths[0], "music")
	j := setKind(t, h, bob, []string{pid}, "audiobook")
	if j.State != "done" {
		t.Fatalf("the uploader's change = %+v, want done", j)
	}
	// Once the end is told the job's origin is gone, and the uploader
	// still reads the result, as someone who may edit its item.
	for deadline := time.Now().Add(10 * time.Second); ; time.Sleep(25 * time.Millisecond) {
		inbox := decode[NotificationPage](t, reqAs(t, h, "GET", "/api/v1/users/me/notifications?limit=100", bob, nil))
		if slices.ContainsFunc(inbox.Notifications, func(n Notification) bool { return n.Title == "Kind changed" }) {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the uploader was never told the change ended")
		}
	}
	wantStatus(t, reqAs(t, h, "GET", "/api/v1/jobs/"+j.Pid, bob, nil), 200, "the told job, read by the uploader")
	if !mayCurateAs(t, h, bob, "bk-"+strings.TrimPrefix(pid, "tr-")) {
		t.Fatal("the uploader lost the right to edit the book their upload became")
	}
	wantStatus(t, postJSONAs(t, h, bob, "/api/v1/items/kind",
		map[string]any{"pids": []string{"bk-" + strings.TrimPrefix(pid, "tr-"), tracks[0]}, "mediaType": "music"}),
		403, "a batch holding one item they may not edit")
}

// The verb refuses before anything starts: no items, too many, a media
// type nothing becomes, and an item nobody can see.
func TestKindChangeRefusesBadRequests(t *testing.T) {
	t.Parallel()
	h := newHarness(t)
	alpha := h.itemTitled(t, h.token, "Alpha Song").Pid
	many := make([]string, 501)
	for i := range many {
		many[i] = alpha
	}
	for _, c := range []struct {
		name   string
		body   map[string]any
		status int
	}{
		{"no items", map[string]any{"pids": []string{}, "mediaType": "audiobook"}, 400},
		{"too many", map[string]any{"pids": many, "mediaType": "audiobook"}, 400},
		{"podcast", map[string]any{"pids": []string{alpha}, "mediaType": "podcast"}, 400},
		{"unknown item", map[string]any{"pids": []string{"tr-01JZX5N8QW3F4V9T2B7KD3M9R6"}, "mediaType": "audiobook"}, 404},
	} {
		wantStatus(t, h.postJSON(t, "/api/v1/items/kind", c.body), c.status, c.name)
	}
}

// An upload whose library its uploader can no longer see is not theirs to
// change the kind of, though their upload still lets them edit it: the
// verb answers as if it did not exist, and nothing starts.
func TestAKindChangeOnAnUploadOutOfSightStartsNothing(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "faded", Codec: fixtures.CodecMP3, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Faded Lecture", "ARTIST": "Speaker", "ALBUM": "Lost Lectures"},
	})
	if err != nil {
		t.Fatal(err)
	}
	pid := importAs(t, h, bob, paths[0], "music")
	users := decode[UserPage](t, get(t, h.ts, "/api/v1/users", h.token)).Users
	bobID := users[slices.IndexFunc(users, func(u UserAccount) bool { return u.Username == "bob" })].Id
	wantStatus(t, h.patchJSON(t, "/api/v1/users/"+bobID, map[string]any{
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": []string{}},
	}), 200, "taking bob's libraries away")
	ctx := context.Background()
	uc, err := h.svc.UserCtxByID(ctx, bobID)
	if err != nil {
		t.Fatal(err)
	}
	if may, err := h.svc.MayCurateItem(ctx, uc, pid); err != nil || !may {
		t.Fatalf("bob may edit his upload = %v (%v), want his upload to still say so", may, err)
	}

	wantStatus(t, postJSONAs(t, h, bob, "/api/v1/items/kind",
		map[string]any{"pids": []string{pid}, "mediaType": "audiobook"}), 404, "a kind change of an upload out of sight")
	if slices.ContainsFunc(decode[JobList](t, get(t, h.ts, "/api/v1/jobs?limit=50", h.token)).Jobs,
		func(j Job) bool { return j.Kind == "set-kind" }) {
		t.Fatal("the refused kind change started a job")
	}
	if it := decodeStatus[Item](t, get(t, h.ts, "/api/v1/items/"+pid, h.token), 200, "the upload"); it.Pid != pid {
		t.Fatalf("the upload reads as %s, want it still the track %s", it.Pid, pid)
	}
}

// A kind change that fails on a file tells its uploader why without the
// server's paths or the catalog's operation names, in the job and in the
// notice of its end.
func TestAFailedKindChangeKeepsTheServersPathsFromItsUploader(t *testing.T) {
	t.Parallel()
	skipWithoutUnwritablePaths(t)
	h, bob := joinHarness(t)
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "sealed", Codec: fixtures.CodecMP3, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Sealed Away", "ARTIST": "Speaker", "ALBUM": "Locked Lectures"},
	})
	if err != nil {
		t.Fatal(err)
	}
	pid := importAs(t, h, bob, paths[0], "music")
	file := *h.itemFiles(t, h.token, pid)[0].Path
	if err := os.Chmod(file, 0); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.Chmod(file, 0o644) })

	j := setKind(t, h, bob, []string{pid}, "audiobook")
	if j.State == "done" {
		t.Fatalf("job = %+v, want it to fail on the unreadable file", j)
	}
	if j.Error == nil || strings.Contains(*j.Error, h.library) || strings.Contains(*j.Error, "waxbin.") {
		t.Fatalf("job error = %v, want a reason without paths or op names", j.Error)
	}
	for deadline := time.Now().Add(10 * time.Second); ; time.Sleep(25 * time.Millisecond) {
		inbox := decode[NotificationPage](t, reqAs(t, h, "GET", "/api/v1/users/me/notifications?limit=100", bob, nil))
		i := slices.IndexFunc(inbox.Notifications, func(n Notification) bool { return n.Title == "Changing the kind failed" })
		if i >= 0 {
			if body := inbox.Notifications[i].Body; strings.Contains(body, h.library) {
				t.Fatalf("notice = %q, want it without the server's paths", body)
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("the uploader was never told the change failed")
		}
	}
}

// An uploader can turn the book their upload made into music and back:
// the parts the split mints stay theirs to edit, so the album of them
// can become the book again.
func TestAnUploaderSplitsTheirBookAndGathersItBack(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	batch := createBatch(t, h, bob, "album", "audiobook")
	for _, p := range looseBook(t) {
		uploadBatchMember(t, h, bob, p, "audiobook", batch.Id, "")
	}
	entry := finalizeBatch(t, h, bob, batch.Id).ReviewEntryIds[0]
	drainMatches(t, h)
	decideAs(t, h, bob, entry, map[string]any{"action": "as-is"})
	book, _ := bookOfParts(t, h, "The Loose Chapters")

	split := setKind(t, h, bob, []string{book}, "music")
	if split.State != "done" {
		t.Fatalf("splitting = %+v, want done", split)
	}
	// The parts' grants land in the change's follow-up, after the job
	// reads done and before its starter is told.
	waitUntilKindChangeTold(t, h, bob, split.Pid)
	var tracks []string
	for _, it := range h.items(t, "?mediaType=music&limit=500").Items {
		if it.Album != nil && *it.Album == "The Loose Chapters" {
			tracks = append(tracks, it.Pid)
		}
	}
	if len(tracks) != 2 {
		t.Fatalf("tracks after the split = %v, want both chapters", tracks)
	}
	for _, pid := range tracks {
		if !mayCurateAs(t, h, bob, pid) {
			t.Fatalf("the uploader may not edit %s, a part of their own book", pid)
		}
	}
	if j := setKind(t, h, bob, tracks, "audiobook"); j.State != "done" {
		t.Fatalf("gathering back = %+v, want done", j)
	}
}

// Reading a finished kind change as someone who may edit its first item
// shows only the items they can see: an administrator's change can run
// over libraries they are not granted.
func TestAKindChangeResultShowsAReaderOnlyWhatTheyMaySee(t *testing.T) {
	t.Parallel()
	h, bob := joinHarness(t)
	paths, err := fixtures.Generate(t.TempDir(), fixtures.Spec{
		Name: "mine", Codec: fixtures.CodecMP3, Duration: 2 * time.Second,
		Tags: map[string]string{"TITLE": "Mine Alone", "ARTIST": "Speaker", "ALBUM": "Own Lectures"},
	})
	if err != nil {
		t.Fatal(err)
	}
	mine := importAs(t, h, bob, paths[0], "music")
	elsewhere := t.TempDir()
	if _, err := fixtures.Generate(elsewhere, fixtures.Spec{
		Name: "theirs", Codec: fixtures.CodecMP3, Duration: 3 * time.Second,
		Tags: map[string]string{"TITLE": "Out Of Sight", "ARTIST": "Other", "ALBUM": "Hidden Lectures"},
	}); err != nil {
		t.Fatal(err)
	}
	hidden := decodeStatus[Library](t, h.postJSON(t, "/api/v1/libraries", map[string]any{
		"name": "hidden", "path": elsewhere,
	}), 201, "a second library")
	waitForScans(t, h)
	theirs := h.itemTitled(t, h.token, "Out Of Sight").Pid
	var granted []string
	for _, l := range decode[Libraries](t, get(t, h.ts, "/api/v1/libraries", h.token)).Libraries {
		if l.Pid != hidden.Pid {
			granted = append(granted, l.Pid)
		}
	}
	users := decode[UserPage](t, get(t, h.ts, "/api/v1/users", h.token)).Users
	bobID := users[slices.IndexFunc(users, func(u UserAccount) bool { return u.Username == "bob" })].Id
	wantStatus(t, h.patchJSON(t, "/api/v1/users/"+bobID, map[string]any{
		"libraryAccess": map[string]any{"mode": "granted", "libraryPids": granted},
	}), 200, "narrowing bob's libraries")

	j := setKind(t, h, h.token, []string{mine, theirs}, "audiobook")
	if j.State != "done" {
		t.Fatalf("admin's change = %+v, want done", j)
	}
	read := decodeStatus[Job](t, reqAs(t, h, "GET", "/api/v1/jobs/"+j.Pid, bob, nil), 200, "bob reads the change")
	converted, _ := (*read.Result)["converted"].([]any)
	for _, p := range converted {
		if strings.HasSuffix(p.(string), strings.TrimPrefix(theirs, "tr-")) {
			t.Fatalf("bob's read names %s, an item he cannot see: %v", p, converted)
		}
	}
	if len(converted) != 1 {
		t.Fatalf("bob's read = %v, want his own item alone", converted)
	}
}

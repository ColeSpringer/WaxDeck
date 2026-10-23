package service

import (
	"context"
	"errors"
	"fmt"
	"io"
	"slices"
	"strings"
	"sync"
	"testing"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// The handover of a smart playlist as a fixed list is run again after any
// failure, and the run after finds the copy the one before made: the
// recipient is never left with two lists under the one name, whatever
// stopped the first, and whether or not the catalog would take the copy
// back.

// handoverFixture is a member with one shared smart list over their stars,
// a reader who pinned it, and the administrator who deletes the member.
type handoverFixture struct {
	ctx    context.Context
	svc    *Library
	admin  *UserCtx
	sam    *Account
	reader *UserCtx
	list   string
	stars  []string
}

const handedName = "Sam's favourites"

func newHandoverFixture(t *testing.T) handoverFixture {
	t.Helper()
	return newHandoverFixtureLogging(t, nil)
}

// newHandoverFixtureLogging is the fixture with the service's log going to
// logs, for a test that asks what the log kept.
func newHandoverFixtureLogging(t *testing.T, logs io.Writer) handoverFixture {
	t.Helper()
	ctx, svc, admin := newCatalogFixtureWith(t, catalogFixtureOptions{logs: logs})
	pids := fixtureItemPIDs(t, ctx, svc, admin)
	sam, samCtx := playlistMember(t, ctx, svc, "sam")
	_, reader := playlistMember(t, ctx, svc, "reader")
	stars := pids[:2]
	for _, pid := range stars {
		if _, err := svc.SetStar(ctx, samCtx, pid, true, nil); err != nil {
			t.Fatal(err)
		}
	}
	list := smartPlaylist(t, ctx, svc, samCtx, handedName, "shared", SmartRule{
		Root: RuleNode{Type: "condition", Field: "starred", Op: "is", Value: "true"},
	})
	if _, err := svc.PutPrefs(ctx, reader, Prefs{Pinned: []string{list}}); err != nil {
		t.Fatal(err)
	}
	return handoverFixture{ctx: ctx, svc: svc, admin: admin, sam: sam, reader: reader, list: list, stars: stars}
}

// copiesNamed is every static playlist anyone holds under the name, or
// under it with the marker a copy carries while its handover runs, which
// is what a reader's playlist grid shows as duplicates of the one list.
func (f handoverFixture) copiesNamed(t *testing.T, name string) []*model.Playlist {
	t.Helper()
	all, err := f.svc.lib.Playlists().List(f.ctx, model.PID(f.admin.CatalogPID))
	if err != nil {
		t.Fatal(err)
	}
	var out []*model.Playlist
	for _, pl := range all {
		if pl.Kind == model.PlaylistStatic && (pl.Name == name || strings.HasPrefix(pl.Name, name+" [handover ")) {
			out = append(out, pl)
		}
	}
	return out
}

// stored is what a static list holds, as the catalog stores it: a reader
// is not shown a member that has since gone to the trash, so a list that
// kept one cannot be told from one that dropped it by reading it.
func (f handoverFixture) stored(t *testing.T, pid model.PID) []string {
	t.Helper()
	pl, err := f.svc.lib.Playlists().Get(f.ctx, pid)
	if err != nil {
		t.Fatal(err)
	}
	items, err := f.svc.lib.Playlists().Items(f.ctx, pid, pl.OwnerPID)
	if err != nil {
		t.Fatal(err)
	}
	out := make([]string, 0, len(items))
	for _, it := range items {
		out = append(out, itemAPIPID(it))
	}
	return out
}

// evaluated is what the member's smart list evaluates to for the member now.
func (f handoverFixture) evaluated(t *testing.T) []string {
	t.Helper()
	pl, err := f.svc.lib.Playlists().Get(f.ctx, mustBare(t, f.list))
	if err != nil {
		t.Fatal(err)
	}
	items, err := f.svc.playlistMembers(f.ctx, pl)
	if err != nil {
		t.Fatal(err)
	}
	out := make([]string, 0, len(items))
	for _, it := range items {
		out = append(out, itemAPIPID(it))
	}
	return out
}

func (f handoverFixture) record(t *testing.T) (wdb.PlaylistHandover, error) {
	t.Helper()
	return f.svc.db.PlaylistHandoverFor(f.ctx, string(mustBare(t, f.list)))
}

// errCatalogAway is the cause failAt's failures carry: the raw words of an
// internal fault, which the client is never shown.
var errCatalogAway = errors.New("the catalog went away")

// failAt fails the named stages of a handover, every time they are reached.
func failAt(svc *Library, stages ...string) {
	svc.handoverHook = func(stage string, _ *model.Playlist) error {
		if slices.Contains(stages, stage) {
			return fmt.Errorf("%w at %s", errCatalogAway, stage)
		}
		return nil
	}
}

// stopHandoverAt makes the named stage the end of the process, as far
// as the handover can tell: nothing after it runs, and nothing is
// cleaned up.
func stopHandoverAt(svc *Library, stage string) {
	svc.handoverHook = func(got string, _ *model.Playlist) error {
		if got == stage {
			panic("the process stopped at " + stage)
		}
		return nil
	}
}

// stopped runs a deletion that stopHandoverAt ends, and says whether it did.
func (f handoverFixture) stopped(t *testing.T, opts AccountDeletion) bool {
	t.Helper()
	var ended bool
	func() {
		defer func() { ended = recover() != nil }()
		_, _ = f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, opts)
	}()
	return ended
}

// The swap fails and so does taking the copy back: the catalog that failed
// is the one asked to clean up after it. The copy is left, on record; the
// error says so; and the retry finishes with that copy.
func TestAHandoverThatCannotTakeItsCopyBackIsFinishedByTheRetry(t *testing.T) {
	t.Parallel()
	logs := &syncBuffer{}
	f := newHandoverFixtureLogging(t, logs)
	failAt(f.svc, "swap", "discard")

	got, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{})
	if err == nil || !strings.Contains(err.Error(), "could not be removed") {
		t.Fatalf("err = %v, want the failure, saying a copy was left", err)
	}
	// What the client is told is the copy and what to do, none of the
	// cause's own words, which the log keeps with the copy's pid.
	if strings.Contains(err.Error(), "went away") {
		t.Errorf("the failure %q carries the cause's raw text", err)
	}
	if !errors.Is(err, errCatalogAway) {
		t.Errorf("the failure %v does not keep its cause for the log", err)
	}
	for _, detail := range []string{"went away at swap", "went away at discard"} {
		if !strings.Contains(logs.String(), detail) {
			t.Errorf("the log does not keep %q:\n%s", detail, logs)
		}
	}
	if got.PlaylistsTransferred != 0 || !got.Disabled {
		t.Errorf("result = %+v, want nothing handed over and the account disabled", got)
	}
	copies := f.copiesNamed(t, handedName)
	if len(copies) != 1 {
		t.Fatalf("static lists named %q = %d, want the one copy that could not be removed", handedName, len(copies))
	}
	left := copies[0].PID
	// The failure names the copy, so the record of it can.
	var leftCopy interface{ LeftCopy() string }
	if !errors.As(err, &leftCopy) || leftCopy.LeftCopy() != apiPID(PrefixPlaylist, left) {
		t.Errorf("the failure %v names no copy, want %s", err, apiPID(PrefixPlaylist, left))
	}
	if KindOf(err) != KindInternal {
		t.Errorf("the failure's kind = %q, want internal whatever its cause", KindOf(err))
	}
	rec, err := f.record(t)
	if err != nil || rec.CopyPID != string(left) {
		t.Fatalf("the record = %+v (%v), want it to name the copy %s", rec, err, left)
	}
	// The playlist is still the member's and the pins are back on it.
	if pl, err := f.svc.lib.Playlists().Get(f.ctx, mustBare(t, f.list)); err != nil || pl.Kind != model.PlaylistSmart {
		t.Errorf("the old list = %+v (%v), want it still there and smart", pl, err)
	}
	if prefs, err := f.svc.Prefs(f.ctx, f.reader); err != nil || !slices.Equal(prefs.Pinned, []string{f.list}) {
		t.Errorf("the reader's pins = %v (%v), want the old list", prefs.Pinned, err)
	}

	f.svc.handoverHook = nil
	got, err = f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{})
	if err != nil {
		t.Fatalf("the retry: %v", err)
	}
	if got.PlaylistsFixed != 1 {
		t.Errorf("the retry = %+v, want the one fixed list", got)
	}
	copies = f.copiesNamed(t, handedName)
	if len(copies) != 1 || copies[0].PID != left {
		t.Fatalf("static lists named %q after the retry = %d, want the one the first run made (%s)", handedName, len(copies), left)
	}
	if catalogHas(f.ctx, f.svc, f.list) {
		t.Error("the member's smart list survived the retry")
	}
	if members := memberPIDs(t, f.ctx, f.svc, f.reader, apiPID(PrefixPlaylist, left)); !slices.Equal(members, f.stars) {
		t.Errorf("the copy holds %v, want sam's stars %v", members, f.stars)
	}
	if prefs, _ := f.svc.Prefs(f.ctx, f.reader); !slices.Equal(prefs.Pinned, []string{apiPID(PrefixPlaylist, left)}) {
		t.Errorf("the reader's pins after the retry = %v, want the copy", prefs.Pinned)
	}
	if rec, err := f.record(t); !errors.Is(err, wdb.ErrNotFound) {
		t.Errorf("the record after the retry = %+v (%v), want it cleared", rec, err)
	}
}

// A process that stops between making the copy and naming it on record
// leaves a copy no record names. The intent was recorded first, so the
// retry finds that copy by what it is, and finishes with it. A copy the
// stop left without its members gets them.
func TestAHandoverThatStopsBetweenMakingAndNamingItsCopyIsFinishedByTheRetry(t *testing.T) {
	t.Parallel()
	f := newHandoverFixture(t)
	f.svc.handoverHook = func(stage string, _ *model.Playlist) error {
		if stage == "created" {
			panic("the process stopped here")
		}
		return nil
	}
	stopped := func() (stopped bool) {
		defer func() { stopped = recover() != nil }()
		_, _ = f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{})
		return false
	}()
	if !stopped {
		t.Fatal("the handover did not reach the point the test stops it at")
	}
	copies := f.copiesNamed(t, handedName)
	if len(copies) != 1 {
		t.Fatalf("static lists named %q after the stop = %d, want the one the stop left", handedName, len(copies))
	}
	stray := copies[0].PID
	if rec, err := f.record(t); err != nil || rec.CopyPID != "" {
		t.Fatalf("the record = %+v (%v), want an intent that names no copy", rec, err)
	}
	// The copy carries its identity from the moment it exists: the source's
	// pid is in its name, and the final name is not yet.
	if name := copies[0].Name; name == handedName || !strings.Contains(name, string(mustBare(t, f.list))) {
		t.Fatalf("the copy the stop left is named %q, want the name with the source's marker", name)
	}
	// The stop can as well have come between making the list and adding to it.
	if err := f.svc.lib.Playlists().Set(f.ctx, stray, nil); err != nil {
		t.Fatal(err)
	}

	f.svc.handoverHook = nil
	if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err != nil {
		t.Fatalf("the retry: %v", err)
	}
	copies = f.copiesNamed(t, handedName)
	if len(copies) != 1 || copies[0].PID != stray {
		t.Fatalf("static lists named %q after the retry = %d, want the one the stop left (%s)", handedName, len(copies), stray)
	}
	if members := memberPIDs(t, f.ctx, f.svc, f.reader, apiPID(PrefixPlaylist, stray)); !slices.Equal(members, f.stars) {
		t.Errorf("the copy holds %v, want sam's stars %v", members, f.stars)
	}
	if catalogHas(f.ctx, f.svc, f.list) {
		t.Error("the member's smart list survived the retry")
	}
	if rec, err := f.record(t); !errors.Is(err, wdb.ErrNotFound) {
		t.Errorf("the record after the retry = %+v (%v), want it cleared", rec, err)
	}
}

// A copy that could not be recorded is taken back at once; one that could
// not even be taken back is left for the retry to find. Either way the
// retry ends with one list.
func TestACopyThatCannotBeRecordedIsNotLeftToBeDuplicated(t *testing.T) {
	t.Parallel()
	for name, stages := range map[string][]string{
		"taken back":                   {"record"},
		"neither recorded nor removed": {"record", "discard"},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			f := newHandoverFixture(t)
			failAt(f.svc, stages...)

			if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err == nil {
				t.Fatal("the deletion went through a failing step")
			}
			left := len(f.copiesNamed(t, handedName))
			if wantLeft := len(stages) - 1; left != wantLeft {
				t.Errorf("copies left after the failure = %d, want %d", left, wantLeft)
			}

			f.svc.handoverHook = nil
			if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err != nil {
				t.Fatalf("the retry: %v", err)
			}
			if copies := f.copiesNamed(t, handedName); len(copies) != 1 {
				t.Errorf("static lists named %q after the retry = %d, want one", handedName, len(copies))
			}
			if catalogHas(f.ctx, f.svc, f.list) {
				t.Error("the member's smart list survived the retry")
			}
		})
	}
}

// A copy somebody deleted between the runs is not taken up; the retry
// makes the one list the member's list becomes.
func TestARetryDoesNotTakeUpACopyThatHasGone(t *testing.T) {
	t.Parallel()
	f := newHandoverFixture(t)
	failAt(f.svc, "swap", "discard")
	if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err == nil {
		t.Fatal("the deletion went through a failing step")
	}
	copies := f.copiesNamed(t, handedName)
	if len(copies) != 1 {
		t.Fatalf("copies after the failure = %d, want 1", len(copies))
	}
	if err := f.svc.removePlaylist(f.ctx, copies[0]); err != nil {
		t.Fatal(err)
	}

	f.svc.handoverHook = nil
	if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err != nil {
		t.Fatalf("the retry: %v", err)
	}
	copies = f.copiesNamed(t, handedName)
	if len(copies) != 1 {
		t.Fatalf("static lists named %q after the retry = %d, want one", handedName, len(copies))
	}
	if members := memberPIDs(t, f.ctx, f.svc, f.reader, apiPID(PrefixPlaylist, copies[0].PID)); !slices.Equal(members, f.stars) {
		t.Errorf("the copy holds %v, want sam's stars %v", members, f.stars)
	}
}

// The retry may name another recipient than the run that left the copy:
// the copy goes to them, and nobody is left holding a second one.
func TestARetryForAnotherRecipientTakesUpTheCopyForThem(t *testing.T) {
	t.Parallel()
	f := newHandoverFixture(t)
	pat, _ := playlistMember(t, f.ctx, f.svc, "pat")
	failAt(f.svc, "swap", "discard")
	if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err == nil {
		t.Fatal("the deletion went through a failing step")
	}

	f.svc.handoverHook = nil
	got, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{TransferTo: pat.User.ID})
	if err != nil {
		t.Fatalf("the retry: %v", err)
	}
	if got.TransferredTo != "pat" {
		t.Errorf("the retry = %+v, want the list handed to pat", got)
	}
	if held := ownedBy(t, f.ctx, f.svc, pat.User.WaxbinUserPID); !slices.Contains(held, handedName) {
		t.Errorf("pat holds %v, want the copy", held)
	}
	if held := ownedBy(t, f.ctx, f.svc, f.admin.CatalogPID); slices.Contains(held, handedName) {
		t.Errorf("the administrator still holds %v, want the copy to have moved on", held)
	}
	if copies := f.copiesNamed(t, handedName); len(copies) != 1 {
		t.Errorf("static lists named %q after the retry = %d, want one", handedName, len(copies))
	}
}

// Two requests to delete one account do not run beside each other: the
// second is refused while the first is under way, and nothing is made
// twice.
func TestOneDeletionOfAnAccountRunsAtATime(t *testing.T) {
	t.Parallel()
	f := newHandoverFixture(t)
	entered, release := make(chan struct{}), make(chan struct{})
	var once sync.Once
	f.svc.handoverHook = func(stage string, _ *model.Playlist) error {
		if stage == "start" {
			once.Do(func() { close(entered) })
			<-release
		}
		return nil
	}
	first := make(chan error, 1)
	go func() {
		_, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{})
		first <- err
	}()
	<-entered

	if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); KindOf(err) != KindConflict {
		t.Errorf("a second deletion while the first runs = %v, want a conflict", err)
	}
	close(release)
	if err := <-first; err != nil {
		t.Fatalf("the first deletion: %v", err)
	}
	if copies := f.copiesNamed(t, handedName); len(copies) != 1 {
		t.Errorf("static lists named %q = %d, want one", handedName, len(copies))
	}
	// And once it is over, the account is simply gone.
	if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); KindOf(err) != KindNotFound {
		t.Errorf("a deletion after the first finished = %v, want not found", err)
	}
}

// The retry takes up only what the handover made: a list the recipient
// made under the same name since, with other members in it, is theirs, and
// is neither taken up nor written over.
func TestARetryNeverWritesOverAListTheRecipientMade(t *testing.T) {
	t.Parallel()
	f := newHandoverFixture(t)
	pids := fixtureItemPIDs(t, f.ctx, f.svc, f.admin)
	f.svc.handoverHook = func(stage string, _ *model.Playlist) error {
		if stage == "created" {
			panic("the process stopped here")
		}
		return nil
	}
	func() {
		defer func() { _ = recover() }()
		_, _ = f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{})
	}()
	stray := f.copiesNamed(t, handedName)
	if len(stray) != 1 {
		t.Fatalf("static lists named %q after the stop = %d, want the one it left", handedName, len(stray))
	}
	// The stop left nothing to find; the administrator makes a list of their
	// own under the same name after it, with other tracks in it.
	if err := f.svc.removePlaylist(f.ctx, stray[0]); err != nil {
		t.Fatal(err)
	}
	theirs := playlistAs(t, f.ctx, f.svc, f.admin, handedName, "shared", pids[2:])

	f.svc.handoverHook = nil
	if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err != nil {
		t.Fatalf("the retry: %v", err)
	}

	if members := memberPIDs(t, f.ctx, f.svc, f.admin, theirs); !slices.Equal(members, pids[2:]) {
		t.Errorf("the administrator's own list holds %v, want it left as it was (%v)", members, pids[2:])
	}
	copies := f.copiesNamed(t, handedName)
	if len(copies) != 2 {
		t.Fatalf("static lists named %q after the retry = %d, want theirs and the copy", handedName, len(copies))
	}
	var holdingStars int
	for _, c := range copies {
		if slices.Equal(memberPIDs(t, f.ctx, f.svc, f.reader, apiPID(PrefixPlaylist, c.PID)), f.stars) {
			holdingStars++
		}
	}
	if holdingStars != 1 {
		t.Errorf("lists holding sam's stars = %d, want the one copy", holdingStars)
	}
}

// The copy is told from every other list by the marker in its name, and by
// nothing else: a list the recipient made under the same name is theirs and
// is left alone, empty or not, even when the copy no longer holds what the
// member's list evaluates to and an empty list would be the closer match.
func TestARetryTakesUpOnlyTheListCarryingTheMarker(t *testing.T) {
	t.Parallel()
	f := newHandoverFixture(t)
	stopHandoverAt(f.svc, "created")
	if !f.stopped(t, AccountDeletion{}) {
		t.Fatal("the handover did not reach the point the test stops it at")
	}
	stray := f.copiesNamed(t, handedName)
	if len(stray) != 1 {
		t.Fatalf("static lists named %q after the stop = %d, want the one it left", handedName, len(stray))
	}
	trashItems(t, f.ctx, f.svc, f.admin, f.stars[0])
	now := f.evaluated(t)
	// An empty list under the plain name, made after the stop: what a copy
	// that lost its members would look like, but not the marker.
	theirs := playlistAs(t, f.ctx, f.svc, f.admin, handedName, "shared", nil)

	f.svc.handoverHook = nil
	if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err != nil {
		t.Fatalf("the retry: %v", err)
	}
	if stored := f.stored(t, stray[0].PID); !slices.Equal(stored, now) {
		t.Errorf("the list the stop left holds %v, want what the member's list evaluated to (%v)", stored, now)
	}
	if pl, err := f.svc.lib.Playlists().Get(f.ctx, stray[0].PID); err != nil || pl.Name != handedName {
		t.Errorf("the list the stop left = %+v (%v), want it under the plain name now", pl, err)
	}
	if stored := f.stored(t, mustBare(t, theirs)); len(stored) != 0 {
		t.Errorf("the administrator's own list holds %v, want it left empty", stored)
	}
	if copies := f.copiesNamed(t, handedName); len(copies) != 2 {
		t.Errorf("static lists named %q after the retry = %d, want theirs and the copy", handedName, len(copies))
	}
}

// What a copy holds is the evaluation of the member's list at the run that
// finishes it, not at the run that made it: a starred track that went to the
// trash in between is not in the copy, and no second copy is made for the
// change. A stop between making the copy and recording it is the case a
// retry finds the copy by its marker.
func TestARetryAfterAStopHoldsWhatTheListEvaluatesToNow(t *testing.T) {
	t.Parallel()
	f := newHandoverFixture(t)
	stopHandoverAt(f.svc, "created")
	if !f.stopped(t, AccountDeletion{}) {
		t.Fatal("the handover did not reach the point the test stops it at")
	}
	stray := f.copiesNamed(t, handedName)
	if len(stray) != 1 {
		t.Fatalf("static lists named %q after the stop = %d, want the one it left", handedName, len(stray))
	}
	trashItems(t, f.ctx, f.svc, f.admin, f.stars[0])
	now := f.evaluated(t)
	if len(now) != 1 {
		t.Fatalf("the list evaluates to %v after the trashing, want the one track left", now)
	}

	f.svc.handoverHook = nil
	if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err != nil {
		t.Fatalf("the retry: %v", err)
	}
	copies := f.copiesNamed(t, handedName)
	if len(copies) != 1 || copies[0].PID != stray[0].PID || copies[0].Name != handedName {
		t.Fatalf("static lists named %q after the retry = %+v, want the one the stop left (%s), under the plain name", handedName, copies, stray[0].PID)
	}
	if stored := f.stored(t, copies[0].PID); !slices.Equal(stored, now) {
		t.Errorf("the copy holds %v, want what the list evaluates to now (%v)", stored, now)
	}
	if rec, err := f.record(t); !errors.Is(err, wdb.ErrNotFound) {
		t.Errorf("the record after the retry = %+v (%v), want it cleared", rec, err)
	}
}

// The same for a copy a failed swap left, which the record names: it is
// brought up to what the list evaluates to when the retry runs.
func TestARetryBringsTheCopyItTakesUpUpToWhatTheListEvaluatesToNow(t *testing.T) {
	t.Parallel()
	f := newHandoverFixture(t)
	failAt(f.svc, "swap", "discard")
	if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err == nil {
		t.Fatal("the deletion went through a failing step")
	}
	left := f.copiesNamed(t, handedName)
	if len(left) != 1 {
		t.Fatalf("copies after the failure = %d, want 1", len(left))
	}
	trashItems(t, f.ctx, f.svc, f.admin, f.stars[0])
	now := f.evaluated(t)
	if len(now) != 1 {
		t.Fatalf("the list evaluates to %v after the trashing, want the one track left", now)
	}

	f.svc.handoverHook = nil
	if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err != nil {
		t.Fatalf("the retry: %v", err)
	}
	copies := f.copiesNamed(t, handedName)
	if len(copies) != 1 || copies[0].PID != left[0].PID {
		t.Fatalf("static lists named %q after the retry = %+v, want the one the first run made", handedName, copies)
	}
	if stored := f.stored(t, copies[0].PID); !slices.Equal(stored, now) {
		t.Errorf("the copy holds %v, want what the list evaluates to now (%v)", stored, now)
	}
}

// The copy is renamed once the record names it, and a stop before the
// rename leaves a copy the record names under the marker's name: the retry
// takes it up by the pid and gives it the name.
func TestARetryRenamesACopyThatAStopLeftUnderItsMarker(t *testing.T) {
	t.Parallel()
	f := newHandoverFixture(t)
	stopHandoverAt(f.svc, "rename")
	if !f.stopped(t, AccountDeletion{}) {
		t.Fatal("the handover did not reach the point the test stops it at")
	}
	stray := f.copiesNamed(t, handedName)
	rec, err := f.record(t)
	if len(stray) != 1 || err != nil || rec.CopyPID != string(stray[0].PID) || stray[0].Name == handedName {
		t.Fatalf("after the stop: copies %+v, record %+v (%v), want one copy under its marker, named by the record", stray, rec, err)
	}

	f.svc.handoverHook = nil
	if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err != nil {
		t.Fatalf("the retry: %v", err)
	}
	copies := f.copiesNamed(t, handedName)
	if len(copies) != 1 || copies[0].PID != stray[0].PID || copies[0].Name != handedName {
		t.Errorf("static lists named %q after the retry = %+v, want the one the stop left, renamed", handedName, copies)
	}
}

// A rename that fails is a failure of the handover like any other: the copy
// is taken back, or left on record when the catalog will not take it back,
// and the retry ends with one list.
func TestACopyThatCannotBeRenamedIsNotLeftToBeDuplicated(t *testing.T) {
	t.Parallel()
	for name, stages := range map[string][]string{
		"taken back":                  {"rename"},
		"neither renamed nor removed": {"rename", "discard"},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			f := newHandoverFixture(t)
			failAt(f.svc, stages...)
			if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err == nil {
				t.Fatal("the deletion went through a failing step")
			}
			if left, want := len(f.copiesNamed(t, handedName)), len(stages)-1; left != want {
				t.Errorf("copies left after the failure = %d, want %d", left, want)
			}

			f.svc.handoverHook = nil
			if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err != nil {
				t.Fatalf("the retry: %v", err)
			}
			copies := f.copiesNamed(t, handedName)
			if len(copies) != 1 || copies[0].Name != handedName {
				t.Errorf("static lists named %q after the retry = %+v, want one under the plain name", handedName, copies)
			}
		})
	}
}

// A retry that deletes the member's playlists instead removes the copy an
// earlier attempt left, whether the record names it or the stop that left
// it came before the record could: the administrator chose to delete what
// the member had, and a copy of it is that.
func TestARetryThatDeletesInsteadRemovesTheCopyAnEarlierAttemptLeft(t *testing.T) {
	t.Parallel()
	for name, leave := range map[string]func(*testing.T, handoverFixture){
		"a copy the record names": func(t *testing.T, f handoverFixture) {
			failAt(f.svc, "swap", "discard")
			if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err == nil {
				t.Fatal("the deletion went through a failing step")
			}
		},
		"a copy a stop left under its marker": func(t *testing.T, f handoverFixture) {
			stopHandoverAt(f.svc, "created")
			if !f.stopped(t, AccountDeletion{}) {
				t.Fatal("the handover did not reach the point the test stops it at")
			}
		},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			f := newHandoverFixture(t)
			leave(t, f)
			left := f.copiesNamed(t, handedName)
			if len(left) != 1 {
				t.Fatalf("copies before the retry = %d, want the one the attempt left", len(left))
			}
			since, err := f.svc.MintServerCursor(f.ctx)
			if err != nil {
				t.Fatal(err)
			}

			f.svc.handoverHook = nil
			got, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{Playlists: PlaylistsDelete})
			if err != nil {
				t.Fatalf("the retry: %v", err)
			}
			// The retry says what became of the copy: the entry names it.
			if want := []string{apiPID(PrefixPlaylist, left[0].PID)}; !slices.Equal(got.FixedCopiesRemoved, want) || len(got.FixedCopiesKept) != 0 {
				t.Errorf("the retry's result = %+v, want the copy %v reported removed", got, want)
			}
			if copies := f.copiesNamed(t, handedName); len(copies) != 0 {
				t.Errorf("static lists named %q after the member's playlists were deleted = %+v, want none", handedName, copies)
			}
			if catalogHas(f.ctx, f.svc, f.list) {
				t.Error("the member's smart list survived the deletion")
			}
			if rec, err := f.record(t); !errors.Is(err, wdb.ErrNotFound) {
				t.Errorf("the record after the deletion = %+v (%v), want it gone", rec, err)
			}
			if _, err := f.svc.Account(f.ctx, f.sam.User.ID); KindOf(err) != KindNotFound {
				t.Errorf("the account after the deletion = %v, want it gone", err)
			}
			// Every account hears that the copy went, as it heard of the playlist.
			delta, err := f.svc.SyncServerDelta(f.ctx, f.reader, since, 200)
			if err != nil {
				t.Fatal(err)
			}
			for _, e := range delta.Events {
				if e.Kind == eventPlaylist && e.Playlist != nil && strings.HasPrefix(e.Playlist.Name, handedName) {
					t.Errorf("the reader's stream still carries the playlist %+v", e.Playlist)
				}
			}
		})
	}
}

// When the member's list was deleted by hand between the attempts, the copy
// is what is left of it, and handing the playlists over finishes the copy
// rather than dropping its record and leaving a list under a marker: it goes
// to the recipient under its own name.
func TestARetryAfterTheListWasDeletedByHandKeepsItsCopyForTheRecipient(t *testing.T) {
	t.Parallel()
	for name, leave := range map[string]func(*testing.T, handoverFixture){
		"a copy the record names": func(t *testing.T, f handoverFixture) {
			failAt(f.svc, "swap", "discard")
			if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{}); err == nil {
				t.Fatal("the deletion went through a failing step")
			}
		},
		"a copy a stop left under its marker": func(t *testing.T, f handoverFixture) {
			stopHandoverAt(f.svc, "created")
			if !f.stopped(t, AccountDeletion{}) {
				t.Fatal("the handover did not reach the point the test stops it at")
			}
		},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			f := newHandoverFixture(t)
			pat, _ := playlistMember(t, f.ctx, f.svc, "pat")
			leave(t, f)
			if err := f.svc.DeletePlaylist(f.ctx, f.admin, f.list); err != nil {
				t.Fatal(err)
			}

			f.svc.handoverHook = nil
			got, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, AccountDeletion{TransferTo: pat.User.ID})
			if err != nil {
				t.Fatalf("the retry: %v", err)
			}
			copies := f.copiesNamed(t, handedName)
			if len(copies) != 1 || copies[0].Name != handedName || string(copies[0].OwnerPID) != pat.User.WaxbinUserPID {
				t.Fatalf("static lists named %q after the retry = %+v, want the one copy, pat's, under its own name", handedName, copies)
			}
			// The retry says what became of the copy: the entry names it.
			if want := []string{apiPID(PrefixPlaylist, copies[0].PID)}; !slices.Equal(got.FixedCopiesKept, want) || len(got.FixedCopiesRemoved) != 0 {
				t.Errorf("the retry's result = %+v, want the copy %v reported kept", got, want)
			}
			if rec, err := f.record(t); !errors.Is(err, wdb.ErrNotFound) {
				t.Errorf("the record after the deletion = %+v (%v), want it gone", rec, err)
			}
		})
	}
}

// What a deletion did is told apart from nothing at all: a call that only
// dealt with a copy an earlier attempt left still changed something, and a
// stopped one with that much done is on the record.
func TestWhatADeletionChangedIsTold(t *testing.T) {
	t.Parallel()
	for name, tc := range map[string]struct {
		done AccountDeleted
		want bool
	}{
		"nothing":                 {AccountDeleted{}, false},
		"disabled the account":    {AccountDeleted{Disabled: true}, true},
		"handed a playlist over":  {AccountDeleted{PlaylistsTransferred: 1}, true},
		"deleted a playlist":      {AccountDeleted{PlaylistsDeleted: 1}, true},
		"removed a copy":          {AccountDeleted{FixedCopiesRemoved: []string{"pl-1"}}, true},
		"kept a copy":             {AccountDeleted{FixedCopiesKept: []string{"pl-1"}}, true},
		"only counted its links":  {AccountDeleted{LinksEnded: 2}, false},
		"only named a recipient":  {AccountDeleted{TransferredTo: "admin"}, false},
		"only fixed a list count": {AccountDeleted{PlaylistsFixed: 1}, false},
	} {
		if got := tc.done.Changed(); got != tc.want {
			t.Errorf("%s: Changed = %v, want %v", name, got, tc.want)
		}
	}
}

// A record the catalog can no longer answer for - the account's catalog user
// is not in the catalog, as after a reset - names nothing to deal with and
// does not stop the account's deletion.
func TestADeletionIgnoresARecordTheCatalogCanNoLongerAnswerFor(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newCatalogFixture(t)
	sam, _ := playlistMember(t, ctx, svc, "sam")
	if err := svc.db.PutPlaylistHandover(ctx, wdb.PlaylistHandover{
		SourcePID: "01JZX5N8QW3F4V9T2B7KDAAAAA", CopyPID: "01JZX5N8QW3F4V9T2B7KDBBBBB", UserID: sam.User.ID, TakerID: admin.ID,
	}); err != nil {
		t.Fatal(err)
	}
	svc.catalogUsersMu.Lock()
	svc.catalogUsers = map[string]model.PID{sam.User.ID: "01JZX5N8QW3F4V9T2B7KDXXXXX"}
	svc.catalogUsersMu.Unlock()

	for name, opts := range map[string]AccountDeletion{"handing over": {}, "deleting": {Playlists: PlaylistsDelete}} {
		if _, err := svc.db.PlaylistHandoverFor(ctx, "01JZX5N8QW3F4V9T2B7KDAAAAA"); err != nil {
			t.Fatalf("%s: the record before the deletion: %v", name, err)
		}
		if _, err := svc.DeleteAccount(ctx, admin, sam.User.ID, opts); err != nil {
			t.Fatalf("%s: %v", name, err)
		}
		if _, err := svc.db.PlaylistHandoverFor(ctx, "01JZX5N8QW3F4V9T2B7KDAAAAA"); !errors.Is(err, wdb.ErrNotFound) {
			t.Errorf("%s: the record after the deletion = %v, want it gone", name, err)
		}
		// The next round runs against another account.
		sam, _ = playlistMember(t, ctx, svc, "sam2")
		if err := svc.db.PutPlaylistHandover(ctx, wdb.PlaylistHandover{
			SourcePID: "01JZX5N8QW3F4V9T2B7KDAAAAA", CopyPID: "01JZX5N8QW3F4V9T2B7KDBBBBB", UserID: sam.User.ID, TakerID: admin.ID,
		}); err != nil {
			t.Fatal(err)
		}
		svc.catalogUsersMu.Lock()
		svc.catalogUsers = map[string]model.PID{sam.User.ID: "01JZX5N8QW3F4V9T2B7KDXXXXX"}
		svc.catalogUsersMu.Unlock()
	}
}

// A list is the handover's copy only if the recipient holds it: another
// account's list that carries the marker in its name is never taken for the
// copy, taken over, written over or deleted, whatever it is called.
func TestAnotherAccountsListCarryingTheMarkerIsNeverTakenForTheCopy(t *testing.T) {
	t.Parallel()
	for name, retry := range map[string]AccountDeletion{
		"a retry that deletes":       {Playlists: PlaylistsDelete},
		"a retry that hands over":    {},
		"a retry for another member": {TransferTo: "pat"},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			f := newHandoverFixture(t)
			pids := fixtureItemPIDs(t, f.ctx, f.svc, f.admin)
			mallory, malloryCtx := playlistMember(t, f.ctx, f.svc, "mallory")
			pat, _ := playlistMember(t, f.ctx, f.svc, "pat")
			if retry.TransferTo != "" {
				retry.TransferTo = pat.User.ID
			}
			// Made before the stop, so it is the earliest list that carries
			// the marker.
			hers := "Mine" + handoverMarker(mustBare(t, f.list))
			theirs := playlistAs(t, f.ctx, f.svc, malloryCtx, hers, "shared", pids[2:])
			stopHandoverAt(f.svc, "created")
			if !f.stopped(t, AccountDeletion{}) {
				t.Fatal("the handover did not reach the point the test stops it at")
			}

			f.svc.handoverHook = nil
			if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, retry); err != nil {
				t.Fatalf("the retry: %v", err)
			}

			pl, err := f.svc.lib.Playlists().Get(f.ctx, mustBare(t, theirs))
			if err != nil || pl.Name != hers || string(pl.OwnerPID) != mallory.User.WaxbinUserPID {
				t.Fatalf("her list = %+v (%v), want it as she made it, hers", pl, err)
			}
			if stored := f.stored(t, mustBare(t, theirs)); !slices.Equal(stored, pids[2:]) {
				t.Errorf("her list holds %v, want %v", stored, pids[2:])
			}
			copies := f.copiesNamed(t, handedName)
			if retry.Playlists == PlaylistsDelete {
				if len(copies) != 0 {
					t.Errorf("static lists named %q after the member's playlists were deleted = %+v, want none: the copy was the one to go", handedName, copies)
				}
				return
			}
			if len(copies) != 1 || copies[0].Name != handedName {
				t.Fatalf("static lists named %q after the retry = %+v, want the handover's copy under its own name", handedName, copies)
			}
			if stored := f.stored(t, copies[0].PID); !slices.Equal(stored, f.stars) {
				t.Errorf("the copy holds %v, want sam's stars %v", stored, f.stars)
			}
		})
	}
}

// The copy is found through the recipient's view of the catalog, not the
// departing member's: a member the catalog has no user for sees nothing,
// and the copy, which every account sees, is still there to be dealt with.
func TestACopyIsFoundWhenTheDepartingMemberIsUnmapped(t *testing.T) {
	t.Parallel()
	for name, retry := range map[string]AccountDeletion{
		"a retry that deletes":    {Playlists: PlaylistsDelete},
		"a retry that hands over": {},
	} {
		t.Run(name, func(t *testing.T) {
			t.Parallel()
			f := newHandoverFixture(t)
			stopHandoverAt(f.svc, "created")
			if !f.stopped(t, AccountDeletion{}) {
				t.Fatal("the handover did not reach the point the test stops it at")
			}
			stray := f.copiesNamed(t, handedName)
			if len(stray) != 1 {
				t.Fatalf("static lists named %q after the stop = %d, want the one it left", handedName, len(stray))
			}
			f.svc.catalogUsersMu.Lock()
			f.svc.catalogUsers = map[string]model.PID{f.sam.User.ID: "01JZX5N8QW3F4V9T2B7KDXXXXX"}
			f.svc.catalogUsersMu.Unlock()

			f.svc.handoverHook = nil
			if _, err := f.svc.DeleteAccount(f.ctx, f.admin, f.sam.User.ID, retry); err != nil {
				t.Fatalf("the retry: %v", err)
			}
			copies := f.copiesNamed(t, handedName)
			switch {
			case retry.Playlists == PlaylistsDelete && len(copies) != 0:
				t.Errorf("static lists named %q after the deletion = %+v, want none", handedName, copies)
			case retry.Playlists != PlaylistsDelete && (len(copies) != 1 || copies[0].Name != handedName):
				t.Errorf("static lists named %q after the retry = %+v, want the copy kept under its own name", handedName, copies)
			}
		})
	}
}

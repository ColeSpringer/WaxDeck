package service

import (
	"context"
	"errors"
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/colespringer/waxdeck/fixtures"
	"github.com/oklog/ulid/v2"
)

// marksFixture is the catalog fixture plus a second account, whose marks
// must never show up in the first one's reads.
func marksFixture(t *testing.T) (context.Context, *Library, *UserCtx, *UserCtx) {
	t.Helper()
	ctx, svc, admin := newCatalogFixture(t)
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "other", Password: "correct-horse-2"})
	if err != nil {
		t.Fatal(err)
	}
	other, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return ctx, svc, admin, other
}

func fixtureEntityPIDs(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx) (album, artist string) {
	t.Helper()
	res, err := svc.Search(ctx, uc, "Signal Garden", 10)
	if err != nil || len(res.Albums) == 0 {
		t.Fatalf("fixture album not found: %+v (%v)", res, err)
	}
	res2, err := svc.Search(ctx, uc, "Test Ensemble", 10)
	if err != nil || len(res2.Artists) == 0 {
		t.Fatalf("fixture artist not found: %+v (%v)", res2, err)
	}
	return res.Albums[0].PID, res2.Artists[0].PID
}

func TestItemMarksAreTheCallersOwnInOneBatch(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, other := marksFixture(t)
	starred, _ := fixtureTrackPID(t, ctx, svc, uc, "Amber Waves")
	rated, _ := fixtureTrackPID(t, ctx, svc, uc, "Basalt Steps")
	played, _ := fixtureTrackPID(t, ctx, svc, uc, "Cobalt Sky")
	untouched, _ := fixtureTrackPID(t, ctx, svc, uc, "Delta Groove")

	before := time.Now().Add(-time.Second)
	if _, err := svc.SetStar(ctx, uc, starred, true, nil); err != nil {
		t.Fatal(err)
	}
	r := 80
	if _, err := svc.SetRating(ctx, uc, rated, &r, nil); err != nil {
		t.Fatal(err)
	}
	if res, err := svc.IngestListens(ctx, uc, []ListenSession{{
		SessionID: "m-1", PID: played, StartedAt: time.Now().UTC(), MsPlayed: 3000, Finished: true,
	}}); err != nil || res.Accepted != 1 {
		t.Fatalf("ingest = %+v (%v)", res, err)
	}

	marks, err := svc.ItemMarks(ctx, uc, []string{starred, rated, played, untouched, "nonsense", starred})
	if err != nil {
		t.Fatal(err)
	}
	if m := marks[starred]; m.StarredAt.Before(before) || m.Rating != nil {
		t.Errorf("starred track mark = %+v, want a star time and no rating", m)
	}
	if m := marks[rated]; m.Rating == nil || *m.Rating != 80 || !m.StarredAt.IsZero() {
		t.Errorf("rated track mark = %+v, want rating 80 and no star", m)
	}
	if m := marks[played]; m.PlayCount != 1 || m.LastPlayedAt.Before(before) {
		t.Errorf("played track mark = %+v, want one play just now", m)
	}
	if m, ok := marks[untouched]; ok {
		t.Errorf("untouched track carries a mark: %+v", m)
	}

	theirs, err := svc.ItemMarks(ctx, other, []string{starred, rated, played})
	if err != nil {
		t.Fatal(err)
	}
	if len(theirs) != 0 {
		t.Errorf("another account reads %+v, want none of the first one's marks", theirs)
	}
}

func TestEntityMarksStarsAndBoundedRatings(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, other := marksFixture(t)
	album, artist := fixtureEntityPIDs(t, ctx, svc, uc)

	before := time.Now().Add(-time.Second)
	if _, err := svc.SetEntityStar(ctx, uc, album, true, nil); err != nil {
		t.Fatal(err)
	}
	r := 60
	if _, err := svc.SetEntityRating(ctx, uc, artist, &r, nil); err != nil {
		t.Fatal(err)
	}

	marks, err := svc.EntityMarks(ctx, uc, []string{album, artist, "nonsense", "tr-" + ulid.Make().String()})
	if err != nil {
		t.Fatal(err)
	}
	if m := marks[album]; m.StarredAt.Before(before) || m.Rating != nil {
		t.Errorf("starred album mark = %+v, want a star time and no rating", m)
	}
	if m := marks[artist]; m.Rating == nil || *m.Rating != 60 || !m.StarredAt.IsZero() {
		t.Errorf("rated artist mark = %+v, want rating 60 and no star", m)
	}

	// Past the per-request bound only stars are read, for every entity in
	// the request rather than for whichever ones came first.
	many := []string{artist, album}
	for len(many) <= entityRatingReadCap {
		many = append(many, "ar-"+ulid.Make().String())
	}
	bounded, err := svc.EntityMarks(ctx, uc, many)
	if err != nil {
		t.Fatal(err)
	}
	if m := bounded[artist]; m.Rating != nil {
		t.Errorf("a request past the bound read ratings: %+v", m)
	}
	if bounded[album].StarredAt.IsZero() {
		t.Error("a request past the bound lost the stars")
	}

	theirs, err := svc.EntityMarks(ctx, other, []string{album, artist})
	if err != nil {
		t.Fatal(err)
	}
	if len(theirs) != 0 {
		t.Errorf("another account reads %+v, want none of the first one's marks", theirs)
	}
}

// The ratings a list ranked by them reads come from a per-user memo, so
// the point reads are paid once rather than per request, and the caller's
// own rating write clears what it held for that entity.
func TestEntityRatingsAreMemoizedUntilTheUsersNextWrite(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, other := marksFixture(t)
	album, _ := fixtureEntityPIDs(t, ctx, svc, uc)
	_, albumPID, _ := parseAPIPID(album)

	r := 80
	if _, err := svc.SetEntityRating(ctx, uc, album, &r, nil); err != nil {
		t.Fatal(err)
	}
	got, err := svc.EntityRatings(ctx, uc, []string{album})
	if err != nil || got[album] != 80 {
		t.Fatalf("ratings = %v (%v), want the album at 80", got, err)
	}

	// Written beneath the service, so nothing clears the memo: the read
	// still answers what it read before.
	beneath := 20
	if _, err := svc.lib.SetEntityRating(ctx, model.PID(uc.CatalogPID), model.MergeAlbum, albumPID, &beneath, nil); err != nil {
		t.Fatal(err)
	}
	if got, _ := svc.EntityRatings(ctx, uc, []string{album}); got[album] != 80 {
		t.Fatalf("ratings = %v, want the memoized 80", got)
	}

	// A star changes no rating, the caller's own or another account's, so
	// neither clears it; the caller's own rating write does.
	if _, err := svc.SetEntityStar(ctx, other, album, true, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SetEntityStar(ctx, uc, album, true, nil); err != nil {
		t.Fatal(err)
	}
	if got, _ := svc.EntityRatings(ctx, uc, []string{album}); got[album] != 80 {
		t.Fatalf("ratings after two stars = %v, want the memoized 80", got)
	}
	r = 40
	if _, err := svc.SetEntityRating(ctx, uc, album, &r, nil); err != nil {
		t.Fatal(err)
	}
	if got, _ := svc.EntityRatings(ctx, uc, []string{album}); got[album] != 40 {
		t.Fatalf("ratings after the account's own write = %v, want 40", got)
	}
	if _, err := svc.SetEntityRating(ctx, uc, album, nil, nil); err != nil {
		t.Fatal(err)
	}
	if got, _ := svc.EntityRatings(ctx, uc, []string{album}); len(got) != 0 {
		t.Fatalf("ratings after clearing = %v, want none", got)
	}
}

// One account's rating write touches that account's memo alone: another
// account's ranked read stays warm, and a fill it was making when the
// write landed is kept.
func TestARatingWriteClearsOnlyItsOwnAccountsMemo(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, other := marksFixture(t)
	album, artist := fixtureEntityPIDs(t, ctx, svc, uc)
	wants := []string{album, artist}
	var reads atomic.Int32
	var hold atomic.Bool
	arrived, release := make(chan struct{}), make(chan struct{})
	svc.trackFacts.entityReadHook = func(ctx context.Context, user model.PID, kind model.MergeEntity, pid model.PID) (*model.EntityPlayState, error) {
		if user == model.PID(uc.CatalogPID) {
			reads.Add(1)
			if hold.CompareAndSwap(true, false) {
				close(arrived)
				<-release
			}
		}
		return svc.lib.EntityPlayState(ctx, user, kind, pid)
	}
	rate := func(who *UserCtx, pid string, r int) {
		t.Helper()
		if _, err := svc.SetEntityRating(ctx, who, pid, &r, nil); err != nil {
			t.Fatal(err)
		}
	}
	ratings := func() map[string]int {
		t.Helper()
		got, err := svc.EntityRatings(ctx, uc, wants)
		if err != nil {
			t.Fatal(err)
		}
		return got
	}

	rate(uc, album, 80)
	reads.Store(0)
	if got := ratings(); got[album] != 80 || reads.Load() != 2 {
		t.Fatalf("ratings = %v after %d point reads, want the album at 80 after two", got, reads.Load())
	}
	rate(other, album, 30)
	reads.Store(0)
	if got := ratings(); got[album] != 80 || reads.Load() != 0 {
		t.Fatalf("after another account's rating: %v with %d point reads, want the memoized 80 and none", got, reads.Load())
	}

	rate(uc, artist, 60)
	reads.Store(0)
	hold.Store(true)
	done := make(chan map[string]int, 1)
	go func() {
		got, _ := svc.EntityRatings(ctx, uc, wants)
		done <- got
	}()
	select {
	case <-arrived:
	case <-time.After(10 * time.Second):
		t.Fatal("the ranked read made no point read")
	}
	rate(other, artist, 10)
	close(release)
	if got := <-done; got[album] != 80 || got[artist] != 60 {
		t.Fatalf("the read across another account's write = %v, want the album at 80 and the artist at 60", got)
	}
	reads.Store(0)
	if got := ratings(); got[artist] != 60 || reads.Load() != 0 {
		t.Fatalf("after a read another account's write crossed: %v with %d point reads, want what it read kept", got, reads.Load())
	}
}

// Clearing the memo's write numbers at their bound never lets a fill read
// before an account's write land after it, and a fill read after lands as
// before.
func TestTheRatingMemoStaysSafePastItsWriterBound(t *testing.T) {
	t.Parallel()
	var m entityRatingMemo
	stamp := ratingStamp{gen: 1}
	pid, r := model.PID("al-1"), 50
	_, before := m.lookup("a", stamp, nil)
	m.forget("a", pid)
	for i := range ratingMemoWriters {
		m.forget(fmt.Sprintf("u%d", i), pid)
	}
	m.store("a", stamp, before, map[model.PID]*int{pid: &r})
	if known, _ := m.lookup("a", stamp, []model.PID{pid}); len(known) != 0 {
		t.Fatalf("a fill read before the account's write landed after it: %v", known)
	}
	_, now := m.lookup("a", stamp, nil)
	m.store("a", stamp, now, map[model.PID]*int{pid: &r})
	if known, _ := m.lookup("a", stamp, []model.PID{pid}); known[pid] == nil || *known[pid] != 50 {
		t.Fatalf("a fill read after the bound was passed = %v, want it kept", known)
	}
}

// twoAlbumFixture is the catalog fixture plus a second album by the same
// artist, for merging one into the other.
func twoAlbumFixture(t *testing.T) (context.Context, *Library, *UserCtx, string, string) {
	t.Helper()
	ctx, svc, uc := newCatalogFixtureWith(t, catalogFixtureOptions{extra: func(t *testing.T, dir string) {
		if _, err := fixtures.Generate(dir, fixtures.Spec{Name: "echo", Codec: fixtures.CodecFLAC, Duration: time.Second,
			Tags: map[string]string{"TITLE": "Echo Field", "ARTIST": "Test Ensemble", "ALBUM": "Signal Gardens"}}); err != nil {
			t.Fatal(err)
		}
	}})
	find := func(name string) string {
		t.Helper()
		res, err := svc.Search(ctx, uc, name, 10)
		if err != nil {
			t.Fatal(err)
		}
		for _, hit := range res.Albums {
			if hit.Title == name {
				return hit.PID
			}
		}
		t.Fatalf("no album %q in %+v", name, res.Albums)
		return ""
	}
	return ctx, svc, uc, find("Signal Garden"), find("Signal Gardens")
}

// A merge moves every user's rating onto the survivor without any write
// of theirs, so the memo follows the catalog's own artist and album
// changes, not only the caller's writes.
func TestEntityRatingsFollowAMerge(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, survivor, loser := twoAlbumFixture(t)

	r := 80
	if _, err := svc.SetEntityRating(ctx, uc, loser, &r, nil); err != nil {
		t.Fatal(err)
	}
	if got, err := svc.EntityRatings(ctx, uc, []string{survivor, loser}); err != nil || got[loser] != 80 || len(got) != 1 {
		t.Fatalf("ratings = %v (%v), want the loser at 80", got, err)
	}
	if _, err := svc.MergeDuplicates(ctx, uc, "album", survivor, []string{loser}); err != nil {
		t.Fatal(err)
	}
	if got, err := svc.EntityRatings(ctx, uc, []string{survivor}); err != nil || got[survivor] != 80 {
		t.Fatalf("ratings after the merge = %v (%v), want the survivor at 80", got, err)
	}
}

// An entity the catalog no longer holds is unrated rather than a failure
// of the whole read, and is not remembered as unrated.
func TestEntityMarksOutliveAVanishedEntity(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := marksFixture(t)
	album, _ := fixtureEntityPIDs(t, ctx, svc, uc)
	gone := PrefixAlbum + "-" + ulid.Make().String()
	r := 60
	if _, err := svc.SetEntityRating(ctx, uc, album, &r, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SetEntityStar(ctx, uc, album, true, nil); err != nil {
		t.Fatal(err)
	}
	reads := map[string]int{}
	svc.trackFacts.entityReadHook = func(ctx context.Context, user model.PID, kind model.MergeEntity, pid model.PID) (*model.EntityPlayState, error) {
		reads[string(pid)]++
		return svc.lib.EntityPlayState(ctx, user, kind, pid)
	}
	for range 2 {
		got, err := svc.EntityRatings(ctx, uc, []string{album, gone})
		if err != nil || len(got) != 1 || got[album] != 60 {
			t.Fatalf("ratings = %v (%v), want the album at 60 and nothing for the vanished one", got, err)
		}
	}
	_, gonePID, _ := parseAPIPID(gone)
	if reads[string(gonePID)] != 2 {
		t.Errorf("the vanished entity was read %d times over two calls, want it re-read each time", reads[string(gonePID)])
	}
	marks, err := svc.EntityMarks(ctx, uc, []string{album, gone})
	if err != nil {
		t.Fatal(err)
	}
	if m := marks[album]; m.StarredAt.IsZero() || m.Rating == nil || *m.Rating != 60 {
		t.Errorf("album mark = %+v, want its star and rating 60", m)
	}
}

// A rating read that fails part way keeps what it read, so a retry
// continues rather than starting over; and a failure that is not the
// entity being gone still leaves the stars in the answer.
func TestEntityRatingsKeepWhatTheyRead(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, survivor, other := twoAlbumFixture(t)
	_, ensemble := fixtureEntityPIDs(t, ctx, svc, uc)
	res, err := svc.Search(ctx, uc, "Brass Nine", 10)
	if err != nil || len(res.Artists) == 0 {
		t.Fatalf("no Brass Nine: %+v (%v)", res, err)
	}
	brass := res.Artists[0].PID
	if _, err := svc.SetEntityStar(ctx, uc, survivor, true, nil); err != nil {
		t.Fatal(err)
	}
	var reads []string
	failAt := 2
	svc.trackFacts.entityReadHook = func(ctx context.Context, user model.PID, kind model.MergeEntity, pid model.PID) (*model.EntityPlayState, error) {
		reads = append(reads, string(pid))
		if len(reads) == failAt {
			return nil, errors.New("disk on fire")
		}
		return svc.lib.EntityPlayState(ctx, user, kind, pid)
	}
	if _, err := svc.EntityRatings(ctx, uc, []string{ensemble, other}); err == nil || len(reads) != 2 {
		t.Fatalf("a failed second read = %v after %d reads, want an error after 2", err, len(reads))
	}
	reads, failAt = nil, 0
	if _, err := svc.EntityRatings(ctx, uc, []string{ensemble, other}); err != nil {
		t.Fatal(err)
	}
	if len(reads) != 1 {
		t.Errorf("the retry read %v, want only the entity the failed call did not reach", reads)
	}

	// The starred album's rating rides its star read; the artist's point
	// read fails, and the star is still answered beside the error.
	reads, failAt = nil, 1
	marks, err := svc.EntityMarks(ctx, uc, []string{survivor, brass})
	if err == nil || len(reads) != 1 {
		t.Fatalf("a failed rating read = %v after %d reads, want an error after 1", err, len(reads))
	}
	if marks[survivor].StarredAt.IsZero() {
		t.Errorf("marks = %+v, want the star kept beside the rating error", marks)
	}
}

// A look at the change log that reads a merge's rows and then fails still
// counts the merge: the memo can never hold a rating from before it.
func TestEntityRatingsKeepAMergeSeenBeforeAFailure(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, survivor, loser := twoAlbumFixture(t)
	r := 80
	if _, err := svc.SetEntityRating(ctx, uc, loser, &r, nil); err != nil {
		t.Fatal(err)
	}
	if got, err := svc.EntityRatings(ctx, uc, []string{survivor, loser}); err != nil || got[loser] != 80 {
		t.Fatalf("ratings = %v (%v), want the loser at 80", got, err)
	}
	if _, err := svc.MergeDuplicates(ctx, uc, "album", survivor, []string{loser}); err != nil {
		t.Fatal(err)
	}
	// The look reads the merge's rows, then its next read of the log fails:
	// the head it is told of lies past them, so it asks for a second page.
	head, err := svc.lib.LatestChangeSeq(ctx)
	if err != nil {
		t.Fatal(err)
	}
	svc.trackFacts.headHook = func(context.Context) (int64, error) { return head + 3, nil }
	reads := 0
	svc.trackFacts.changesHook = func(ctx context.Context, since int64) ([]model.Change, error) {
		if reads++; reads == 2 {
			return nil, errors.New("catalog busy")
		}
		return svc.lib.Changes(ctx, since)
	}
	_, _ = svc.EntityRatings(ctx, uc, []string{survivor})
	svc.trackFacts.changesHook, svc.trackFacts.headHook = nil, nil
	if reads != 2 {
		t.Fatalf("the look read the log %d times, want the merge's page and then the failure", reads)
	}
	for range 2 {
		if got, err := svc.EntityRatings(ctx, uc, []string{survivor}); err != nil || got[survivor] != 80 {
			t.Fatalf("ratings after the merge = %v (%v), want the survivor at 80", got, err)
		}
	}
}

// A look that cannot read the log says nothing about the catalog. A caller
// whose context is already gone leaves every user's memo warm, and a caller
// whose look fails reads its own answer from the catalog and keeps nothing.
func TestAFailedLookLeavesTheRatingsMemoWarm(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := marksFixture(t)
	album, _ := fixtureEntityPIDs(t, ctx, svc, uc)
	_, albumPID, _ := parseAPIPID(album)
	r := 80
	if _, err := svc.SetEntityRating(ctx, uc, album, &r, nil); err != nil {
		t.Fatal(err)
	}
	reads := 0
	svc.trackFacts.entityReadHook = func(ctx context.Context, user model.PID, kind model.MergeEntity, pid model.PID) (*model.EntityPlayState, error) {
		reads++
		return svc.lib.EntityPlayState(ctx, user, kind, pid)
	}
	ratings := func(want int) {
		t.Helper()
		if got, err := svc.EntityRatings(ctx, uc, []string{album}); err != nil || got[album] != want {
			t.Fatalf("ratings = %v (%v), want the album at %d", got, err, want)
		}
	}
	ratings(80)

	gone, cancel := context.WithCancel(ctx)
	cancel()
	svc.CatalogContentSeq(gone)
	svc.entityEpoch(gone)
	reads = 0
	ratings(80)
	if reads != 0 {
		t.Errorf("callers who left cost the next one %d point reads, want the memo's answer", reads)
	}

	// Written beneath the service, so only a read of the catalog sees it.
	beneath := 20
	if _, err := svc.lib.SetEntityRating(ctx, model.PID(uc.CatalogPID), model.MergeAlbum, albumPID, &beneath, nil); err != nil {
		t.Fatal(err)
	}
	svc.trackFacts.headHook = func(context.Context) (int64, error) { return 0, errors.New("catalog busy") }
	ratings(20)
	svc.trackFacts.headHook = nil
	reads = 0
	ratings(80)
	if reads != 0 {
		t.Errorf("the memo was read again %d times after a failed look, want its own answer untouched", reads)
	}
}

// A starred entity's rating rides the starred read, which a ranked read
// makes before it takes the account's write number: a rating write that
// lands between the two leaves nothing older behind for the next read.
func TestAStarredRatingReadBeforeAWriteIsNotKept(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := marksFixture(t)
	album, _ := fixtureEntityPIDs(t, ctx, svc, uc)
	rate := func(r int) {
		t.Helper()
		if _, err := svc.SetEntityRating(ctx, uc, album, &r, nil); err != nil {
			t.Fatal(err)
		}
	}
	rate(40)
	if _, err := svc.SetEntityStar(ctx, uc, album, true, nil); err != nil {
		t.Fatal(err)
	}
	var hold atomic.Bool
	arrived, release := make(chan struct{}), make(chan struct{})
	svc.trackFacts.headHook = func(ctx context.Context) (int64, error) {
		if hold.CompareAndSwap(true, false) {
			close(arrived)
			<-release
		}
		return svc.lib.LatestChangeSeq(ctx)
	}
	hold.Store(true)
	type answer struct {
		ratings map[string]int
		err     error
	}
	done := make(chan answer, 1)
	go func() {
		got, err := svc.EntityRatings(ctx, uc, []string{album})
		done <- answer{got, err}
	}()
	select {
	case <-arrived:
	case <-time.After(10 * time.Second):
		t.Fatal("the ranked read made no look at the catalog")
	}
	rate(80)
	close(release)
	if in := <-done; in.err != nil || in.ratings[album] != 40 {
		t.Fatalf("the read across the write = %v (%v), want the 40 it read", in.ratings, in.err)
	}
	if got, err := svc.EntityRatings(ctx, uc, []string{album}); err != nil || got[album] != 80 {
		t.Fatalf("the next read = %v (%v), want the written 80", got, err)
	}
}

// A rating write forgets the entity it wrote and nothing else of the
// account's: another album still answers from the memo, with no point
// read, and the one written answers its new rating.
func TestARatingWriteForgetsOnlyTheEntityItWrote(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, first, second := twoAlbumFixture(t)
	_, firstPID, _ := parseAPIPID(first)
	_, secondPID, _ := parseAPIPID(second)
	reads := map[model.PID]int{}
	svc.trackFacts.entityReadHook = func(ctx context.Context, user model.PID, kind model.MergeEntity, pid model.PID) (*model.EntityPlayState, error) {
		reads[pid]++
		return svc.lib.EntityPlayState(ctx, user, kind, pid)
	}
	rate := func(pid string, r int) {
		t.Helper()
		if _, err := svc.SetEntityRating(ctx, uc, pid, &r, nil); err != nil {
			t.Fatal(err)
		}
	}
	ratings := func() map[string]int {
		t.Helper()
		got, err := svc.EntityRatings(ctx, uc, []string{first, second})
		if err != nil {
			t.Fatal(err)
		}
		return got
	}
	rate(first, 80)
	rate(second, 30)
	if got := ratings(); got[first] != 80 || got[second] != 30 {
		t.Fatalf("ratings = %v, want 80 and 30", got)
	}
	clear(reads)
	rate(first, 40)
	if got := ratings(); got[first] != 40 || got[second] != 30 {
		t.Fatalf("ratings after the first album's write = %v, want 40 and the second's 30", got)
	}
	if reads[secondPID] != 0 || reads[firstPID] != 1 {
		t.Errorf("point reads after the write = %v, want the written album's alone", reads)
	}
}

// The starred albums come in one read with their marks, ratings
// included; an album rated and not starred is not among them.
func TestStarredAlbumMarksCarryTheirRatings(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, starred, rated := twoAlbumFixture(t)
	r := 80
	if _, err := svc.SetEntityStar(ctx, uc, starred, true, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SetEntityRating(ctx, uc, starred, &r, nil); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.SetEntityRating(ctx, uc, rated, &r, nil); err != nil {
		t.Fatal(err)
	}
	order, marks, err := svc.StarredAlbumMarks(ctx, uc)
	if err != nil {
		t.Fatal(err)
	}
	m := marks[starred]
	if len(order) != 1 || order[0] != starred || m.StarredAt.IsZero() || m.Rating == nil || *m.Rating != 80 {
		t.Fatalf("starred albums = %v %+v, want %s alone, starred and rated 80", order, marks, starred)
	}
}

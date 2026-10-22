package service

import (
	"context"
	"fmt"
	"math/rand/v2"
	"sync"
	"testing"
	"time"

	"github.com/colespringer/waxbin/model"
	"github.com/oklog/ulid/v2"
)

// A ranked read over a quarter of a million albums costs its point reads
// once: asked again, it reads nothing.
func TestALargeRankedReadIsPaidOnce(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := marksFixture(t)
	reads := 0
	svc.trackFacts.entityReadHook = func(context.Context, model.PID, model.MergeEntity, model.PID) (*model.EntityPlayState, error) {
		reads++
		return &model.EntityPlayState{}, nil
	}
	pids := albumPIDs(250_000)
	for call, want := range []int{250_000, 0, 0} {
		reads = 0
		if _, err := svc.EntityRatings(ctx, uc, pids); err != nil {
			t.Fatal(err)
		}
		if reads != want {
			t.Fatalf("call %d made %d point reads, want %d", call+1, reads, want)
		}
	}
}

// ratingAccounts are n accounts sharing uc's catalog user, each with an
// id of its own for the memo.
func ratingAccounts(uc *UserCtx, n int) []*UserCtx {
	out := make([]*UserCtx, n)
	for i := range out {
		c := *uc
		c.ID = fmt.Sprintf("%s-%d", uc.ID, i)
		out[i] = &c
	}
	return out
}

func albumPIDs(n int) []string {
	out := make([]string, n)
	for i := range out {
		out[i] = PrefixAlbum + "-" + ulid.Make().String()
	}
	return out
}

// Accounts asking in turn for a ranked read over the same albums each pay
// it once.
func TestRankedReadsByManyAccountsArePaidOnceEach(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := marksFixture(t)
	reads := 0
	svc.trackFacts.entityReadHook = func(context.Context, model.PID, model.MergeEntity, model.PID) (*model.EntityPlayState, error) {
		reads++
		return &model.EntityPlayState{}, nil
	}
	pids := albumPIDs(40_000)
	accounts := ratingAccounts(uc, 6)
	for round := range 3 {
		for i, who := range accounts {
			reads = 0
			if _, err := svc.EntityRatings(ctx, who, pids); err != nil {
				t.Fatal(err)
			}
			if want := map[bool]int{true: 40_000, false: 0}[round == 0]; reads != want {
				t.Fatalf("round %d, account %d made %d point reads, want %d", round+1, i, reads, want)
			}
		}
	}
}

// countingReads counts the point reads a ratings read makes, every entity
// unrated.
func countingReads(svc *Library) *int {
	reads := new(int)
	svc.trackFacts.entityReadHook = func(context.Context, model.PID, model.MergeEntity, model.PID) (*model.EntityPlayState, error) {
		*reads++
		return &model.EntityPlayState{}, nil
	}
	return reads
}

// rankedReads answers a func that makes who's ranked read over pids and
// says how many point reads it made.
func rankedReads(t *testing.T, ctx context.Context, svc *Library) func(who *UserCtx, pids []string) int {
	reads := countingReads(svc)
	return func(who *UserCtx, pids []string) int {
		t.Helper()
		*reads = 0
		if _, err := svc.EntityRatings(ctx, who, pids); err != nil {
			t.Fatal(err)
		}
		return *reads
	}
}

// A read past the budget keeps what fits and reads only its overflow
// again; the account already held keeps all of its answers.
func TestARatingReadPastTheBudgetRereadsOnlyItsOverflow(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := marksFixture(t)
	svc.trackFacts.ratings.budget = 1000
	ask := rankedReads(t, ctx, svc)
	accounts := ratingAccounts(uc, 2)
	a, b := accounts[0], accounts[1]
	held, past := albumPIDs(600), albumPIDs(600)
	ask(a, held)
	for call, want := range []int{600, 200, 200} {
		if n := ask(b, past); n != want {
			t.Errorf("read %d past the budget made %d point reads, want %d", call+1, n, want)
		}
	}
	if n := ask(a, held); n != 0 {
		t.Errorf("the account held first, asked again, made %d point reads, want none", n)
	}
}

// To make room, accounts idle for more than ten minutes give way, least
// recently used first and no more of them than the read needs.
func TestIdleAccountsGiveWayToTheRatingBudget(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := marksFixture(t)
	m := &svc.trackFacts.ratings
	m.budget = 1000
	start := time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)
	at := start
	m.clock = func() time.Time { return at }
	ask := rankedReads(t, ctx, svc)
	accounts := ratingAccounts(uc, 4)
	oldest, older, active, newcomer := accounts[0], accounts[1], accounts[2], accounts[3]
	oldestPIDs, olderPIDs, activePIDs := albumPIDs(300), albumPIDs(300), albumPIDs(400)
	ask(oldest, oldestPIDs)
	at = start.Add(time.Minute)
	ask(older, olderPIDs)
	at = start.Add(6 * time.Minute)
	ask(active, activePIDs)
	at = start.Add(16 * time.Minute)
	if n := ask(newcomer, albumPIDs(300)); n != 300 {
		t.Fatalf("the newcomer's read made %d point reads, want 300", n)
	}
	if n := ask(active, activePIDs); n != 0 {
		t.Errorf("the account used ten minutes ago lost answers: %d point reads, want none", n)
	}
	if n := ask(older, olderPIDs); n != 0 {
		t.Errorf("the second least recently used account gave way too: %d point reads, want none", n)
	}
	if n := ask(oldest, oldestPIDs); n != 300 {
		t.Errorf("the least recently used account, asked again, made %d point reads, want 300", n)
	}
}

// An account used within the last ten minutes keeps its answers whatever
// another read needs; past ten minutes idle it gives way.
func TestAnAccountUsedWithinTenMinutesKeepsItsAnswers(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := marksFixture(t)
	m := &svc.trackFacts.ratings
	m.budget = 1000
	start := time.Date(2026, 10, 21, 12, 0, 0, 0, time.UTC)
	at := start
	m.clock = func() time.Time { return at }
	ask := rankedReads(t, ctx, svc)
	accounts := ratingAccounts(uc, 2)
	held, other := accounts[0], accounts[1]
	heldPIDs, otherPIDs := albumPIDs(1000), albumPIDs(100)
	ask(held, heldPIDs)
	at = start.Add(10 * time.Minute)
	ask(other, otherPIDs)
	if n := ask(other, otherPIDs); n != 100 {
		t.Errorf("a read beside an account used ten minutes ago, asked again, made %d point reads, want 100", n)
	}
	if n := ask(held, heldPIDs); n != 0 {
		t.Fatalf("the account used ten minutes ago, asked again, made %d point reads, want none", n)
	}
	at = at.Add(10*time.Minute + time.Second)
	ask(other, otherPIDs)
	if n := ask(other, otherPIDs); n != 0 {
		t.Errorf("a read beside an account idle past ten minutes, asked again, made %d point reads, want none", n)
	}
}

// Answers held under a stamp the catalog has left give way to a read
// under the new one at once, however recently used: nothing can ask for
// them again.
func TestRatingAnswersUnderAPassedStampGiveWay(t *testing.T) {
	t.Parallel()
	m := entityRatingMemo{budget: 2}
	passed, current := ratingStamp{gen: 1, entities: 1}, ratingStamp{gen: 1, entities: 2}
	r := 50
	keep := func(userID string, stamp ratingStamp, pids ...model.PID) {
		t.Helper()
		_, writes := m.lookup(userID, stamp, nil)
		read := map[model.PID]*int{}
		for _, pid := range pids {
			read[pid] = &r
		}
		m.store(userID, stamp, writes, read)
	}
	keep("a", passed, "al-1", "al-2")
	keep("b", current, "al-3", "al-4")
	if known, _ := m.lookup("b", current, []model.PID{"al-3", "al-4"}); len(known) != 2 {
		t.Fatalf("the read under the new stamp kept %v, want both answers", known)
	}
	if m.entries != 2 {
		t.Fatalf("the memo counts %d answers, want 2", m.entries)
	}
}

// A rating the account makes once the memo is full is served rated on
// every read after it, held or not.
func TestARatingMadeOnceTheMemoIsFullIsServedRated(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := marksFixture(t)
	var mu sync.Mutex
	rated := map[model.PID]int{}
	reads := 0
	svc.trackFacts.entityReadHook = func(_ context.Context, _ model.PID, _ model.MergeEntity, pid model.PID) (*model.EntityPlayState, error) {
		mu.Lock()
		defer mu.Unlock()
		reads++
		if r, ok := rated[pid]; ok {
			return &model.EntityPlayState{Rating: r, HasRating: true}, nil
		}
		return &model.EntityPlayState{}, nil
	}
	albums := albumPIDs(10)
	ask := func() (map[string]int, int) {
		t.Helper()
		mu.Lock()
		reads = 0
		mu.Unlock()
		got, err := svc.EntityRatings(ctx, uc, albums)
		if err != nil {
			t.Fatal(err)
		}
		mu.Lock()
		defer mu.Unlock()
		return got, reads
	}
	m := &svc.trackFacts.ratings
	m.budget = 1000
	ask()
	fillRatingMemo(t, ctx, svc, ratingAccounts(uc, 5))
	_, bare, _ := parseAPIPID(albums[3])
	mu.Lock()
	rated[bare] = 80
	mu.Unlock()
	m.forget(uc.ID, bare) // as SetEntityRating does
	fillRatingMemo(t, ctx, svc, ratingAccounts(uc, 1))
	for call := range 3 {
		if got, n := ask(); got[albums[3]] != 80 || n != 1 {
			t.Errorf("ask %d after the rating = %v with %d point reads, want the album at 80 read alone", call+1, got, n)
		}
	}
}

// fillRatingMemo stores unrated answers for accounts, used just now, until
// the memo holds its budget.
func fillRatingMemo(t *testing.T, ctx context.Context, svc *Library, accounts []*UserCtx) {
	t.Helper()
	epoch, ok := svc.entityEpoch(ctx)
	if !ok {
		t.Fatal("the catalog watch could not tell its epoch")
	}
	stamp := ratingStamp{gen: svc.catalogGeneration(), entities: epoch}
	m := &svc.trackFacts.ratings
	for i, who := range accounts {
		m.mu.Lock()
		room := m.limit() - m.entries
		m.mu.Unlock()
		share := room / (len(accounts) - i)
		if i == len(accounts)-1 {
			share = room
		}
		read := make(map[model.PID]*int, share)
		for range share {
			read[model.PID(ulid.Make().String())] = nil
		}
		_, writes := m.lookup(who.ID, stamp, nil)
		m.store(who.ID, stamp, writes, read)
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if m.entries != m.limit() {
		t.Fatalf("the memo holds %d answers after filling, want its budget of %d", m.entries, m.limit())
	}
}

// Answers carry across the sets they were read in: a page of albums each
// answered alone, random pages over albums answered before, and a ranked
// read over them all cost no point reads.
func TestRatingAnswersCarryAcrossPages(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _ := marksFixture(t)
	reads := 0
	svc.trackFacts.entityReadHook = func(context.Context, model.PID, model.MergeEntity, model.PID) (*model.EntityPlayState, error) {
		reads++
		return &model.EntityPlayState{}, nil
	}
	library := albumPIDs(2_000)
	marks := func(pids []string) {
		t.Helper()
		if _, err := svc.EntityMarks(ctx, uc, pids); err != nil {
			t.Fatal(err)
		}
	}
	for _, pid := range library[:500] {
		marks([]string{pid})
	}
	reads = 0
	if marks(library[:500]); reads != 0 {
		t.Errorf("a page of albums each answered alone made %d point reads, want none", reads)
	}
	for from := 500; from < len(library); from += 500 {
		marks(library[from : from+500])
	}
	reads = 0
	rng := rand.New(rand.NewPCG(1, 2))
	for range 50 {
		page := make([]string, 50)
		for i, j := range rng.Perm(len(library))[:50] {
			page[i] = library[j]
		}
		marks(page)
	}
	if reads != 0 {
		t.Errorf("50 random pages over albums answered before made %d point reads, want none", reads)
	}
	reads = 0
	if _, err := svc.EntityRatings(ctx, uc, library); err != nil {
		t.Fatal(err)
	}
	if reads != 0 {
		t.Errorf("a ranked read over albums answered page by page made %d point reads, want none", reads)
	}
}

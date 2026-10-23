package service

import (
	"testing"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// A merge is audited under the administrator who queued it, by id, even
// once that account is disabled, as on its way to deletion: a run that
// trashed a book's parts is on the record whoever still holds the account.
func TestAMergeIsAuditedUnderItsStarterOnceDisabled(t *testing.T) {
	t.Parallel()
	ctx, svc, _, book, _, _ := bookToolFixture(t, false)
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "second", Password: "long-enough-pw", Roles: []string{"admin"}})
	if err != nil {
		t.Fatal(err)
	}
	second, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	task, err := svc.StartBookMerge(ctx, second, apiPID(PrefixBook, book), nil, false)
	if err != nil {
		t.Fatal(err)
	}
	off := true
	if _, err := svc.UpdateAccount(ctx, second.ID, AccountUpdate{Disabled: &off}); err != nil {
		t.Fatal(err)
	}
	if err := attempt(t, ctx, svc, 1); err != nil {
		t.Fatalf("the merge = %v, want it finished", err)
	}
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "book.merge"}, "", 10)
	if err != nil {
		t.Fatal(err)
	}
	var mine int
	for _, e := range page.Events {
		if e.Detail["task"] == task.ID {
			mine++
			if e.ActorID != second.ID {
				t.Errorf("the merge's audit actor = %q, want %q", e.ActorID, second.ID)
			}
		}
	}
	if mine != 1 {
		t.Fatalf("audits of the merge = %d, want one", mine)
	}
}

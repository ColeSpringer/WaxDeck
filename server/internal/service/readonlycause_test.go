package service

import (
	"testing"

	"github.com/colespringer/waxbin/organize"
)

// A read-only server holds every planned move, and each hold names the
// server as its cause, not a library.
func TestAReadOnlyServersHoldsNameTheServer(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, _ := managedTrackFixture(t)
	setServerReadOnly(t, ctx, svc, true)
	plan, err := svc.PreviewOrganize(ctx, uc, organize.DefaultProfileName, nil)
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.Holds) == 0 {
		t.Fatalf("preview = %+v, want the move held", plan)
	}
	for _, h := range plan.Holds {
		if h.Code != string(organize.HoldReadOnly) || h.Reason != "read-only server" {
			t.Errorf("hold %+v, want it held as read-only for the server", h)
		}
	}
}

// A write-back fix the server's switch stops says the server skipped its
// items; one a library's flag stops still names the library
// (TestAWriteBackFixLeavesAReadOnlyLibraryAlone).
func TestAWriteBackFixAReadOnlyServerStopsNamesTheServer(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, _, pid := managedTrackFixture(t)
	start, err := svc.StartHealthFix(ctx, uc, ruleWriteUnsynced, []string{pid})
	if err != nil {
		t.Fatal(err)
	}
	setServerReadOnly(t, ctx, svc, true)
	sum := fixSummary(t, ctx, svc, uc, start.TaskID)
	if sum.Skipped["read-only server"] != 1 || sum.Skipped["read-only library"] != 0 {
		t.Fatalf("summary %+v, want the track skipped for the read-only server", sum)
	}
}

// A path fix the server's switch stops says the server held its items;
// one a library's flag holds names the library.
func TestAPathFixNamesWhatMadeItsItemsReadOnly(t *testing.T) {
	t.Parallel()
	for _, c := range []struct {
		name   string
		server bool
		want   string
	}{
		{"the server", true, "Moved 0 of 1; 1 held (read-only server 1); 0 failed"},
		{"a library", false, "Moved 0 of 1; 1 held (read-only library 1); 0 failed"},
	} {
		t.Run(c.name, func(t *testing.T) {
			t.Parallel()
			ctx, svc, uc, _, pid := managedTrackFixture(t)
			if !c.server {
				setLibrariesReadOnly(t, ctx, svc, uc, true)
			}
			start, err := svc.StartHealthFix(ctx, uc, rulePathMismatch, []string{pid})
			if err != nil {
				t.Fatal(err)
			}
			if c.server {
				setServerReadOnly(t, ctx, svc, true)
			}
			fixSummary(t, ctx, svc, uc, start.TaskID)
			if row := waitForInbox(t, ctx, svc, uc, "health-fix-finished"); row.Body != c.want {
				t.Fatalf("body = %q, want %q", row.Body, c.want)
			}
		})
	}
}

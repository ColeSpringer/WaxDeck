package service

import (
	"os"
	"testing"
)

// A read-only library's files stay where they are: a preview and an
// apply count them as held rather than listing or moving them.
func TestOrganizeLeavesAReadOnlyLibraryInPlace(t *testing.T) {
	t.Parallel()
	ctx, svc, uc, path, _ := managedTrackFixture(t)
	profile := svc.defaultOrganizeProfile()
	if plan, err := svc.PreviewOrganize(ctx, uc, profile, nil); err != nil || plan.TotalActions != 1 || plan.Held != 0 {
		t.Fatalf("writable preview = %+v (%v), want the track's move", plan, err)
	}
	setLibrariesReadOnly(t, ctx, svc, uc, true)
	plan, err := svc.PreviewOrganize(ctx, uc, profile, nil)
	if err != nil || plan.TotalActions != 0 || plan.Held != 1 {
		t.Fatalf("read-only preview = %+v (%v), want the move held", plan, err)
	}
	rep, err := svc.ApplyOrganize(ctx, uc, profile, nil)
	if err != nil || rep.Moved != 0 || rep.Skipped != 0 || rep.Held != 1 {
		t.Fatalf("apply = %+v (%v), want the move held", rep, err)
	}
	if _, err := os.Stat(path); err != nil {
		t.Fatalf("the track moved out of a read-only library: %v", err)
	}
}

// The listing says how many libraries organize can lay out, which is
// none until a root is managed.
func TestOrganizeProfilesCountTheManagedLibraries(t *testing.T) {
	t.Parallel()
	ctx, svc, uc := openEnrichFixture(t, func(*Config) {})
	if got, err := svc.OrganizeProfilesFor(ctx, uc); err != nil || got.ManagedLibraries != 0 || len(got.Profiles) == 0 {
		t.Fatalf("in-place profiles = %+v (%v), want the built-in and no managed library", got, err)
	}
	ctx, svc, uc, _, _ = managedTrackFixture(t)
	if got, err := svc.OrganizeProfilesFor(ctx, uc); err != nil || got.ManagedLibraries != 1 {
		t.Fatalf("managed profiles = %+v (%v), want one managed library", got, err)
	}
}

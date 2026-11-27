package service

import (
	"context"
	"testing"
)

// readByline answers the submitter name the entry's detail carries.
func readByline(t *testing.T, ctx context.Context, svc *Library, uc *UserCtx, id string) ReviewDetailDTO {
	t.Helper()
	d, err := svc.Ingest.GetReviewEntry(ctx, uc, id)
	if err != nil {
		t.Fatal(err)
	}
	return d
}

func TestAnUploadEntryNamesItsSubmitter(t *testing.T) {
	ctx, svc, uc := managedUploadFixture(t)
	name := "Ada Admin"
	if _, err := svc.Identity.UpdateAccount(ctx, uc.ID, AccountUpdate{DisplayName: &name}); err != nil {
		t.Fatal(err)
	}
	_, id := pendingUploadEntry(t, ctx, svc, uc)
	d := readByline(t, ctx, svc, uc, id)
	if d.UploadedBy != uc.ID || d.UploadedByName != "Ada Admin" {
		t.Errorf("submitter = %q named %q, want %q named %q", d.UploadedBy, d.UploadedByName, uc.ID, "Ada Admin")
	}
}

func TestAnAcquisitionEntryNamesItsSubmitterByUsernameWithoutADisplayName(t *testing.T) {
	ctx, svc, admin := managedUploadFixture(t)
	acct, _ := memberAs(t, ctx, svc, AccountCreate{Username: "ann"})
	id := openAcquired(t, ctx, svc, acct.User.ID, "Found Album")
	d := readByline(t, ctx, svc, admin, id)
	if d.UploadedBy != acct.User.ID || d.UploadedByName != "ann" {
		t.Errorf("submitter = %q named %q, want %q named %q", d.UploadedBy, d.UploadedByName, acct.User.ID, "ann")
	}
}

func TestAnEntryWhoseAccountIsGoneKeepsThePidAndNoName(t *testing.T) {
	ctx, svc, admin := managedUploadFixture(t)
	acct, _ := memberAs(t, ctx, svc, AccountCreate{Username: "gone", DisplayName: "Gone Girl"})
	id := openAcquired(t, ctx, svc, acct.User.ID, "Left Behind")
	if _, err := svc.Identity.DeleteAccount(ctx, admin, acct.User.ID, AccountDeletion{}); err != nil {
		t.Fatal(err)
	}
	d := readByline(t, ctx, svc, admin, id)
	if d.UploadedBy != acct.User.ID || d.UploadedByName != "" {
		t.Errorf("submitter = %q named %q, want the pid and no name", d.UploadedBy, d.UploadedByName)
	}
}

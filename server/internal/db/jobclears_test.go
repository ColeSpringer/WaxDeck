package db

import (
	"context"
	"testing"
)

func TestJobsClearedAtIsZeroUntilSet(t *testing.T) {
	d := openTwoUsersTest(t)
	ns, err := d.JobsClearedAt(context.Background(), "us-1")
	if err != nil || ns != 0 {
		t.Fatalf("JobsClearedAt before any clear = (%d, %v), want (0, nil)", ns, err)
	}
}

func TestSetJobsClearedAtKeepsOnePerAccount(t *testing.T) {
	d := openTwoUsersTest(t)
	ctx := context.Background()
	for _, set := range []struct {
		user string
		ns   int64
	}{{"us-1", 100}, {"us-1", 250}, {"us-2", 7}} {
		if err := d.SetJobsClearedAt(ctx, set.user, set.ns); err != nil {
			t.Fatal(err)
		}
	}
	for user, want := range map[string]int64{"us-1": 250, "us-2": 7} {
		if got, err := d.JobsClearedAt(ctx, user); err != nil || got != want {
			t.Errorf("%s watermark = (%d, %v), want %d", user, got, err, want)
		}
	}
}

func TestSetJobsClearedAtNeverMovesBack(t *testing.T) {
	d := openTwoUsersTest(t)
	ctx := context.Background()
	for _, ns := range []int64{250, 100} {
		if err := d.SetJobsClearedAt(ctx, "us-1", ns); err != nil {
			t.Fatal(err)
		}
	}
	if got, err := d.JobsClearedAt(ctx, "us-1"); err != nil || got != 250 {
		t.Fatalf("watermark after an older clear landed last = (%d, %v), want 250", got, err)
	}
}

func TestJobsClearedAtGoesWithTheAccount(t *testing.T) {
	d := openTwoUsersTest(t)
	ctx := context.Background()
	if err := d.SetJobsClearedAt(ctx, "us-1", 100); err != nil {
		t.Fatal(err)
	}
	if err := d.DeleteUser(ctx, "us-1", false); err != nil {
		t.Fatal(err)
	}
	var rows int
	if err := d.r.QueryRowContext(ctx, `SELECT COUNT(*) FROM job_clears`).Scan(&rows); err != nil || rows != 0 {
		t.Fatalf("job_clears rows after the account left = (%d, %v), want 0", rows, err)
	}
}

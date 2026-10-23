package db

import (
	"context"
	"testing"
)

// What a job's end needs that the job does not keep rides its origin, to
// the claim, the read and the listing alike.
func TestJobOriginKeepsItsDetail(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	const detail = `{"name":"books","path":"/srv/books"}`
	if err := d.InsertJobOrigin(ctx, JobOrigin{PID: "jb-1", UserID: "us-1", Detail: detail, CreatedAtNS: 1}); err != nil {
		t.Fatal(err)
	}
	if o, err := d.JobOriginGet(ctx, "jb-1"); err != nil || o.Detail != detail {
		t.Fatalf("read = %+v (%v), want the detail", o, err)
	}
	if all, err := d.JobOrigins(ctx); err != nil || len(all) != 1 || all[0].Detail != detail {
		t.Fatalf("listing = %+v (%v), want the detail", all, err)
	}
	if o, err := d.ClaimJobOrigin(ctx, "jb-1", 10, 5); err != nil || o.Detail != detail {
		t.Fatalf("claim = %+v (%v), want the detail", o, err)
	}
}

package db

import (
	"context"
	"errors"
	"testing"
)

// A settled run's audit row lands with its origin's drop, in one
// transaction, so a settle repeated after it landed writes nothing.
func TestSettlingAnOriginRecordsItsAuditOnce(t *testing.T) {
	ctx := context.Background()
	d := openTest(t)
	for _, pid := range []string{"run", "scan"} {
		if err := d.InsertJobOrigin(ctx, JobOrigin{PID: pid, UserID: "u1", CreatedAtNS: 1}); err != nil {
			t.Fatal(err)
		}
	}
	e := AuditEvent{ActorID: "u1", ActorName: "admin", Action: "organize.apply", TargetKind: "job",
		TargetPID: "jb-run", Detail: `{"moved":3}`, CreatedAtNS: 2}
	if err := d.SettleJobOrigin(ctx, "run", &e); err != nil {
		t.Fatal(err)
	}
	if err := d.SettleJobOrigin(ctx, "run", &e); !errors.Is(err, ErrNotFound) {
		t.Fatalf("a second settle = %v, want ErrNotFound", err)
	}
	rows, err := d.ListAudit(ctx, AuditFilter{Action: "organize.apply"}, 0, 10)
	if err != nil || len(rows) != 1 || rows[0].TargetPID != "jb-run" || rows[0].Detail != `{"moved":3}` {
		t.Fatalf("audit = %+v (%v), want the one row", rows, err)
	}
	// Without a row to write it is the drop alone.
	if err := d.SettleJobOrigin(ctx, "scan", nil); err != nil {
		t.Fatal(err)
	}
	if left, err := d.JobOrigins(ctx); err != nil || len(left) != 0 {
		t.Fatalf("origins = %+v (%v), want none", left, err)
	}
	if rows, err := d.ListAudit(ctx, AuditFilter{}, 0, 10); err != nil || len(rows) != 1 {
		t.Fatalf("audit = %+v (%v), want the one row still", rows, err)
	}
}

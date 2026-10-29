package db

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"testing"
	"time"
)

// A lease keeps to the types its worker takes: those it names, or every
// type but those, oldest first.
func TestALeaseKeepsToItsTypes(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	now := time.Now().UnixNano()
	for i, typ := range []string{"health-fix", "book-merge", "catalog-repair", "acquire"} {
		tk := task(fmt.Sprintf("tk-%d", i), "")
		tk.Type, tk.CreatedAtNS = typ, now+int64(i)
		if err := d.InsertToolTask(ctx, tk); err != nil {
			t.Fatal(err)
		}
	}
	long := []string{"health-fix", "catalog-repair"}
	leased := func(types TaskTypes) []string {
		t.Helper()
		var out []string
		for {
			row, err := d.LeaseToolTask(ctx, now+10, int64(time.Minute), 3, types)
			if errors.Is(err, ErrNotFound) {
				return out
			}
			if err != nil {
				t.Fatal(err)
			}
			out = append(out, row.Type)
		}
	}
	if got := leased(TaskTypes{Except: long}); !slices.Equal(got, []string{"book-merge", "acquire"}) {
		t.Errorf("every type but the long ones leased %v, want the book merge, then the acquisition", got)
	}
	if got := leased(TaskTypes{Only: long}); !slices.Equal(got, []string{"health-fix", "catalog-repair"}) {
		t.Errorf("the long types leased %v, want the health fix, then the repair", got)
	}
}

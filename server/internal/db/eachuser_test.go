package db

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"strings"
	"testing"
)

// EachUser walks every account once, in username order, across the page
// boundary, and stops at the first error its callback returns.
func TestEachUserVisitsEveryAccountOnce(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	const n = eachUserPage + 1
	for i := range n {
		if err := d.CreateUser(ctx, mkUser(fmt.Sprintf("us-%04d", i), fmt.Sprintf("User%04d", n-i), nil), false); err != nil {
			t.Fatal(err)
		}
	}
	var seen []string
	if err := d.EachUser(ctx, func(u *User) error {
		seen = append(seen, strings.ToLower(u.Username))
		return nil
	}); err != nil {
		t.Fatal(err)
	}
	if len(seen) != n || len(slices.Compact(slices.Clone(seen))) != n || !slices.IsSorted(seen) {
		t.Errorf("walked %d accounts (%d distinct, sorted %v), want each of %d once in order",
			len(seen), len(slices.Compact(slices.Clone(seen))), slices.IsSorted(seen), n)
	}

	stop := errors.New("stop")
	visits := 0
	err := d.EachUser(ctx, func(*User) error {
		visits++
		return stop
	})
	if !errors.Is(err, stop) || visits != 1 {
		t.Errorf("a failing callback = %v after %d visits, want its error after 1", err, visits)
	}
}

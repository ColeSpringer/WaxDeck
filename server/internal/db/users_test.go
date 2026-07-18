package db

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"testing"
)

func mkUser(id, username string, roles []string) *User {
	return &User{
		ID:            id,
		Username:      username,
		Roles:         roles,
		LibraryAccess: "all",
		WaxbinUserPID: "01JZX5N8QW3F4V9T2B7KDEXAMPLE",
	}
}

func TestLastAdminGuardSequential(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	a := mkUser("us-A", "alice", []string{"admin"})
	b := mkUser("us-B", "bob", []string{"admin"})
	for _, u := range []*User{a, b} {
		if err := d.CreateUser(ctx, u, false); err != nil {
			t.Fatal(err)
		}
	}

	// Disabling one of two admins passes its guard.
	a.Disabled = true
	if err := d.UpdateUser(ctx, a, true); err != nil {
		t.Fatalf("first demotion: %v", err)
	}
	// The survivor's guard must now refuse both update and delete.
	b.Disabled = true
	if err := d.UpdateUser(ctx, b, true); !errors.Is(err, ErrConflict) {
		t.Fatalf("last-admin update = %v, want ErrConflict", err)
	}
	if err := d.DeleteUser(ctx, "us-B", true); !errors.Is(err, ErrConflict) {
		t.Fatalf("last-admin delete = %v, want ErrConflict", err)
	}
	// A missing row still reads as not found, guard or no guard.
	if err := d.DeleteUser(ctx, "us-missing", true); !errors.Is(err, ErrNotFound) {
		t.Fatalf("missing delete = %v, want ErrNotFound", err)
	}
}

func TestLastAdminGuardConcurrent(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	a := mkUser("us-A", "alice", []string{"admin"})
	b := mkUser("us-B", "bob", []string{"admin"})
	for _, u := range []*User{a, b} {
		if err := d.CreateUser(ctx, u, false); err != nil {
			t.Fatal(err)
		}
	}

	// Race a disable of A against a delete of B, repeatedly. Whatever
	// the interleaving, the guards must leave at least one enabled
	// administrator; a count-then-write would let both through.
	for round := 0; round < 25; round++ {
		var wg sync.WaitGroup
		wg.Add(2)
		go func() {
			defer wg.Done()
			u := mkUser("us-A", "alice", []string{"admin"})
			u.Disabled = true
			_ = d.UpdateUser(ctx, u, true)
		}()
		go func() {
			defer wg.Done()
			_ = d.DeleteUser(ctx, "us-B", true)
		}()
		wg.Wait()
		n, err := d.CountEnabledAdmins(ctx)
		if err != nil {
			t.Fatal(err)
		}
		if n == 0 {
			t.Fatalf("round %d: zero enabled administrators survived the race", round)
		}
		// Reset for the next round: re-enable A, recreate B if deleted.
		reset := mkUser("us-A", "alice", []string{"admin"})
		if err := d.UpdateUser(ctx, reset, false); err != nil {
			t.Fatal(err)
		}
		if _, err := d.UserByID(ctx, "us-B"); errors.Is(err, ErrNotFound) {
			if err := d.CreateUser(ctx, mkUser("us-B", "bob", []string{"admin"}), false); err != nil {
				t.Fatal(err)
			}
		}
	}
}

func TestBootstrapInsertGuard(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()

	// Concurrent bootstraps with DIFFERENT usernames: the uniqueness
	// constraint cannot save this; only the insert's own adminless
	// guard can. Exactly one may win.
	const racers = 8
	errs := make([]error, racers)
	var wg sync.WaitGroup
	for i := 0; i < racers; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			u := mkUser(fmt.Sprintf("us-%02d", i), fmt.Sprintf("admin%02d", i), []string{"admin"})
			errs[i] = d.CreateUser(ctx, u, true)
		}(i)
	}
	wg.Wait()
	winners := 0
	for _, err := range errs {
		switch {
		case err == nil:
			winners++
		case errors.Is(err, ErrConflict):
		default:
			t.Fatalf("unexpected error: %v", err)
		}
	}
	if winners != 1 {
		t.Fatalf("bootstrap winners = %d, want exactly 1", winners)
	}
	if n, err := d.CountEnabledAdmins(ctx); err != nil || n != 1 {
		t.Fatalf("enabled admins = %d (%v), want 1", n, err)
	}

	// The door stays closed afterwards, and unguarded creation of
	// ordinary accounts still works.
	if err := d.CreateUser(ctx, mkUser("us-late", "latecomer", []string{"admin"}), true); !errors.Is(err, ErrConflict) {
		t.Fatalf("post-admin guarded insert = %v, want ErrConflict", err)
	}
	if err := d.CreateUser(ctx, mkUser("us-plain", "plain", []string{"user"}), false); err != nil {
		t.Fatalf("plain create after bootstrap: %v", err)
	}
}

package service

import (
	"testing"
)

// The session carries the server-wide read-only flag, so the switch
// flipping has to reach every open client: each account's stream gets
// the pid-less account marker that makes it re-read the session. Saving
// a value the setting already holds, or any other setting, tells nobody.
func TestFlippingServerReadOnlyMarksEveryAccountChanged(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	acct, err := svc.CreateAccount(ctx, AccountCreate{Username: "listener", Password: "correct-horse"})
	if err != nil {
		t.Fatal(err)
	}
	listener, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	settings, err := svc.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}

	save := func(mutate func(*AdminSettings)) {
		t.Helper()
		next := settings
		mutate(&next)
		saved, err := svc.AdminSettingsPut(ctx, admin, next)
		if err != nil {
			t.Fatal(err)
		}
		settings = saved
	}
	// markers is how many account markers each account's stream gained
	// since the cursor, which then moves on.
	since, err := svc.MintServerCursor(ctx)
	if err != nil {
		t.Fatal(err)
	}
	markers := func(who *UserCtx) int {
		t.Helper()
		delta, err := svc.SyncServerDelta(ctx, who, since, 100)
		if err != nil {
			t.Fatal(err)
		}
		n := 0
		for _, e := range delta.Events {
			if e.Kind == eventAccount && e.PID == "" {
				n++
			}
		}
		return n
	}
	both := func(want int, what string) {
		t.Helper()
		for name, who := range map[string]*UserCtx{"administrator": admin, "member": listener} {
			if got := markers(who); got != want {
				t.Errorf("%s: the %s heard %d account markers, want %d", what, name, got, want)
			}
		}
		var err error
		if since, err = svc.MintServerCursor(ctx); err != nil {
			t.Fatal(err)
		}
	}

	save(func(s *AdminSettings) { s.SignupEnabled = true })
	both(0, "a setting that is not the read-only switch")

	save(func(s *AdminSettings) { s.ReadOnly = true })
	both(1, "turning read-only on")
	if !svc.ServerReadOnly() {
		t.Error("the server does not report read-only after the switch")
	}

	save(func(s *AdminSettings) { s.ReadOnly = true })
	both(0, "saving read-only while it is already on")

	save(func(s *AdminSettings) { s.ReadOnly = false })
	both(1, "turning read-only off")
	if svc.ServerReadOnly() {
		t.Error("the server still reports read-only after the switch went off")
	}
}

// The server-wide switch is refused in the server's words: the library
// is not what is read-only, and a refusal that says so sends the person
// looking in the wrong place.
func TestServerReadOnlyRefusesInTheServersWords(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	settings, err := svc.AdminSettingsGet(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.CheckWritable(ctx, ""); err != nil {
		t.Fatalf("a writable server refused: %v", err)
	}
	settings.ReadOnly = true
	if _, err := svc.AdminSettingsPut(ctx, admin, settings); err != nil {
		t.Fatal(err)
	}
	err = svc.CheckWritable(ctx, "")
	if KindOf(err) != KindReadOnly {
		t.Fatalf("CheckWritable = %v, want a read-only refusal", err)
	}
	if got, want := err.Error(), "the server is in read-only mode"; got != want {
		t.Errorf("refusal = %q, want %q", got, want)
	}
}

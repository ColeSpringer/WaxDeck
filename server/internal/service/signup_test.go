package service

import (
	"context"
	"io"
	"log/slog"
	"path/filepath"
	"strings"
	"testing"

	"github.com/colespringer/waxdeck/server/internal/auth"
	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/supervise"
)

// newAdminFixture is a Library over an empty catalog plus an admin
// context: enough for the account, signup, settings, and schedule
// surfaces, which never touch media.
func newAdminFixture(t *testing.T) (context.Context, *Library, *UserCtx) {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	store, err := wdb.Open(ctx, filepath.Join(t.TempDir(), "waxdeck.db"))
	if err != nil {
		t.Fatal(err)
	}
	sealer, err := auth.NewSealer([]byte("0123456789abcdef0123456789abcdef"), "waxdeck-app-password-v1")
	if err != nil {
		t.Fatal(err)
	}
	group := supervise.NewGroup(log)
	svc, err := Open(ctx, Config{
		DataDir: t.TempDir(),
		Roots:   []Root{{Name: "lib", Path: t.TempDir()}},
		Sealer:  sealer,
		Logger:  log,
	}, store, group)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cancel()
		group.Wait()
		svc.Close()
		store.Close()
	})
	acct, err := svc.CreateAccount(ctx, AccountCreate{
		Username: "admin", Password: "correct-horse", Roles: []string{"admin"},
	})
	if err != nil {
		t.Fatal(err)
	}
	uc, err := svc.UserCtx(ctx, acct.User)
	if err != nil {
		t.Fatal(err)
	}
	return ctx, svc, uc
}

func TestSignupPendingFlow(t *testing.T) {
	ctx, svc, admin := newAdminFixture(t)

	// Closed by default: no invite, no open signup.
	if _, _, err := svc.Signup(ctx, "sam", "password123", "", ""); KindOf(err) != KindForbidden {
		t.Fatalf("signup while disabled: got %v, want forbidden", err)
	}

	if _, err := svc.AdminSettingsPut(ctx, admin, AdminSettings{SignupEnabled: true}); err != nil {
		t.Fatal(err)
	}
	acct, state, err := svc.Signup(ctx, "sam", "password123", "Sam", "")
	if err != nil || state != SignupPending {
		t.Fatalf("open signup: state %v err %v", state, err)
	}
	if !acct.User.Pending {
		t.Fatal("account should be pending")
	}
	// Pending accounts cannot log in.
	if u, err := svc.VerifyLocalLogin(ctx, "sam", "password123"); err != nil || u != nil {
		t.Fatalf("pending login: got %v/%v, want nil/nil", u, err)
	}
	// The queue lists it; approval activates it with the given shape.
	page, err := svc.PendingAccounts(ctx, "", 10)
	if err != nil || len(page.Accounts) != 1 {
		t.Fatalf("pending queue: %v (%d)", err, len(page.Accounts))
	}
	perms := DefaultPermissions()
	perms.Delete = true
	approved, err := svc.ApproveSignup(ctx, admin, acct.User.ID, SignupApproval{Permissions: &perms})
	if err != nil {
		t.Fatal(err)
	}
	if approved.User.Pending || !approved.User.PermDelete {
		t.Fatalf("approval result: pending=%v delete=%v", approved.User.Pending, approved.User.PermDelete)
	}
	if u, err := svc.VerifyLocalLogin(ctx, "sam", "password123"); err != nil || u == nil {
		t.Fatalf("approved login failed: %v/%v", u, err)
	}
	// Re-approving conflicts; rejecting an active account conflicts.
	if _, err := svc.ApproveSignup(ctx, admin, acct.User.ID, SignupApproval{}); KindOf(err) != KindConflict {
		t.Fatalf("re-approve: got %v, want conflict", err)
	}
	if err := svc.RejectSignup(ctx, admin, acct.User.ID); KindOf(err) != KindConflict {
		t.Fatalf("reject active: got %v, want conflict", err)
	}
}

func TestSignupRejectFreesUsername(t *testing.T) {
	ctx, svc, admin := newAdminFixture(t)
	if _, err := svc.AdminSettingsPut(ctx, admin, AdminSettings{SignupEnabled: true}); err != nil {
		t.Fatal(err)
	}
	acct, _, err := svc.Signup(ctx, "sam", "password123", "", "")
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.RejectSignup(ctx, admin, acct.User.ID); err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.Signup(ctx, "sam", "password123", "", ""); err != nil {
		t.Fatalf("username should be free again: %v", err)
	}
}

func TestInviteLifecycle(t *testing.T) {
	ctx, svc, admin := newAdminFixture(t)

	iv, err := svc.CreateInvite(ctx, admin, InviteCreate{Note: "for grandma", MaxUses: 1})
	if err != nil {
		t.Fatal(err)
	}
	if iv.Token == "" {
		t.Fatal("create must return the token")
	}
	// The list never carries tokens.
	list, err := svc.Invites(ctx)
	if err != nil || len(list) != 1 || list[0].Token != "" {
		t.Fatalf("invite list: %v (%d, token %q)", err, len(list), list[0].Token)
	}

	// Invites work while open signup stays off, and admit active accounts.
	acct, state, err := svc.Signup(ctx, "grandma", "password123", "", iv.Token)
	if err != nil || state != SignupActive {
		t.Fatalf("invited signup: state %v err %v", state, err)
	}
	if acct.User.Pending {
		t.Fatal("invited account must not be pending")
	}
	// Single use: the second admission fails the same as a bad token.
	if _, _, err := svc.Signup(ctx, "grandpa", "password123", "", iv.Token); KindOf(err) != KindForbidden {
		t.Fatalf("exhausted invite: got %v, want forbidden", err)
	}

	// A failed signup returns the claimed use.
	iv2, err := svc.CreateInvite(ctx, admin, InviteCreate{MaxUses: 1})
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.Signup(ctx, "grandma", "password123", "", iv2.Token); KindOf(err) != KindConflict {
		t.Fatalf("taken username via invite: got %v, want conflict", err)
	}
	if _, _, err := svc.Signup(ctx, "auntie", "password123", "", iv2.Token); err != nil {
		t.Fatalf("returned use should admit: %v", err)
	}

	// Revocation stops a live token.
	iv3, err := svc.CreateInvite(ctx, admin, InviteCreate{MaxUses: 0})
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.RevokeInvite(ctx, admin, iv3.ID); err != nil {
		t.Fatal(err)
	}
	if _, _, err := svc.Signup(ctx, "uncle", "password123", "", iv3.Token); KindOf(err) != KindForbidden {
		t.Fatalf("revoked invite: got %v, want forbidden", err)
	}
}

func TestAuditRecordsAndFilters(t *testing.T) {
	ctx, svc, admin := newAdminFixture(t)
	if _, err := svc.AdminSettingsPut(ctx, admin, AdminSettings{SignupEnabled: true}); err != nil {
		t.Fatal(err)
	}
	if _, err := svc.CreateInvite(ctx, admin, InviteCreate{}); err != nil {
		t.Fatal(err)
	}
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{}, "", 10)
	if err != nil || len(page.Events) < 2 {
		t.Fatalf("audit list: %v (%d)", err, len(page.Events))
	}
	// Newest first, with the actor resolved.
	if page.Events[0].Action != "invite.create" || page.Events[0].ActorName != "admin" {
		t.Fatalf("head event: %+v", page.Events[0])
	}
	// Prefix filtering: `settings.` matches the settings write only.
	filtered, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "settings."}, "", 10)
	if err != nil || len(filtered.Events) != 1 || filtered.Events[0].Action != "settings.update" {
		t.Fatalf("filtered: %v %+v", err, filtered.Events)
	}
}

func TestSchedulesAndReadOnlyToggles(t *testing.T) {
	ctx, svc, admin := newAdminFixture(t)

	rows := svc.Schedules(ctx)
	if len(rows) != len(scheduleKinds) {
		t.Fatalf("schedule kinds: %d, want %d", len(rows), len(scheduleKinds))
	}
	enabled := map[string]bool{}
	for _, row := range rows {
		enabled[row.Kind] = row.Enabled
	}
	// Only prune ships on: it bounds tables that otherwise grow without
	// bound. Everything else costs enough that an administrator opts in,
	// analyze most of all.
	for kind, on := range enabled {
		if want := kind == "prune"; on != want {
			t.Errorf("%s ships enabled=%v, want %v", kind, on, want)
		}
	}
	if _, err := svc.PutSchedule(ctx, admin, "scan", "not a cron", true); KindOf(err) != KindInvalid {
		t.Fatalf("bad cron: got %v, want invalid", err)
	}
	row, err := svc.PutSchedule(ctx, admin, "scan", "0 3 * * *", true)
	if err != nil || !row.Enabled || row.NextRunNS == 0 {
		t.Fatalf("put schedule: %+v %v", row, err)
	}

	// Global read-only refuses the write surfaces via CheckWritable.
	if _, err := svc.AdminSettingsPut(ctx, admin, AdminSettings{ReadOnly: true}); err != nil {
		t.Fatal(err)
	}
	if err := svc.CheckWritable(ctx, ""); KindOf(err) != KindReadOnly {
		t.Fatalf("read-only check: got %v, want read-only", err)
	}
	if _, err := svc.AdminSettingsPut(ctx, admin, AdminSettings{}); err != nil {
		t.Fatal(err)
	}
	if err := svc.CheckWritable(ctx, ""); err != nil {
		t.Fatalf("writable again: %v", err)
	}
}

func TestLastfmRuntimeCredentials(t *testing.T) {
	ctx, svc, admin := newAdminFixture(t)

	// Unconfigured: the slot is unavailable and the state says none.
	cfg := svc.LastfmConfigGet(ctx)
	if cfg.Configured || cfg.Source != "none" {
		t.Fatalf("initial state: %+v", cfg)
	}
	slots, err := svc.ListScrobblers(ctx, admin)
	if err != nil || slots[0].Available {
		t.Fatalf("lastfm should be unavailable: %v %+v", err, slots[0])
	}

	// Half-set pairs are refused.
	if _, err := svc.LastfmConfigPut(ctx, admin, "key-only", ""); KindOf(err) != KindInvalid {
		t.Fatalf("half-set: got %v, want invalid", err)
	}

	// A stored pair takes effect immediately, without a restart.
	cfg, err = svc.LastfmConfigPut(ctx, admin, "the-api-key", "the-shared-secret")
	if err != nil || !cfg.Configured || cfg.Source != "settings" || cfg.APIKey != "the-api-key" || !cfg.SecretSet {
		t.Fatalf("after put: %+v %v", cfg, err)
	}
	slots, _ = svc.ListScrobblers(ctx, admin)
	if !slots[0].Available {
		t.Fatal("lastfm should be available after configuring")
	}

	// The secret never lands in settings as plaintext.
	raw, err := svc.db.SettingGet(ctx, "scrobble:lastfm-secret")
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(raw, "the-shared-secret") {
		t.Fatal("secret stored unsealed")
	}

	// Clearing falls back to nothing here (no environment pair).
	cfg, err = svc.LastfmConfigPut(ctx, admin, "", "")
	if err != nil || cfg.Configured {
		t.Fatalf("after clear: %+v %v", cfg, err)
	}
	slots, _ = svc.ListScrobblers(ctx, admin)
	if slots[0].Available {
		t.Fatal("lastfm should be unavailable after clearing")
	}
}

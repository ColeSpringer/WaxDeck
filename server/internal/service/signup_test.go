package service

import (
	"context"
	"fmt"
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
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)

	// Closed by default: no invite, no open signup.
	if _, _, err := svc.Signup(ctx, "sam", "password123", "", ""); KindOf(err) != KindForbidden {
		t.Fatalf("signup while disabled: got %v, want forbidden", err)
	}

	if _, err := svc.AdminSettingsPut(ctx, admin, everySetting(AdminSettings{SignupEnabled: true})); err != nil {
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
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	if _, err := svc.AdminSettingsPut(ctx, admin, everySetting(AdminSettings{SignupEnabled: true})); err != nil {
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
	t.Parallel()
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

// onlyAuditEntry is the one entry an action left in the log.
func onlyAuditEntry(t *testing.T, ctx context.Context, svc *Library, action string) AuditEventDTO {
	t.Helper()
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: action}, "", 10)
	if err != nil || len(page.Events) != 1 {
		t.Fatalf("%s audit = %+v (%v), want one entry", action, page.Events, err)
	}
	return page.Events[0]
}

// A revoked invite is recorded under its note, the one name an
// administrator knows it by; one made without a note has none, and one
// that is not there is revoked by no one.
func TestAnInviteRevokeNamesItsInvite(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	noted, err := svc.CreateInvite(ctx, admin, InviteCreate{Note: "for grandma"})
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.RevokeInvite(ctx, admin, noted.ID); err != nil {
		t.Fatal(err)
	}
	e := onlyAuditEntry(t, ctx, svc, "invite.revoke")
	if e.TargetPID != noted.ID || e.TargetName != "for grandma" || e.ActorID != admin.ID {
		t.Fatalf("invite.revoke = %+v, want %s named for grandma, revoked by %s", e, noted.ID, admin.ID)
	}

	bare, err := svc.CreateInvite(ctx, admin, InviteCreate{})
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.RevokeInvite(ctx, admin, bare.ID); err != nil {
		t.Fatal(err)
	}
	if err := svc.RevokeInvite(ctx, admin, PrefixInvite+"-nobody"); KindOf(err) != KindNotFound {
		t.Fatalf("revoking an absent invite: got %v, want not found", err)
	}
	page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "invite.revoke"}, "", 10)
	if err != nil || len(page.Events) != 2 || page.Events[0].TargetPID != bare.ID || page.Events[0].TargetName != "" {
		t.Fatalf("invite.revoke entries = %+v (%v), want the note-less invite's after the first, unnamed, and none for the absent one",
			page.Events, err)
	}
}

// An approval records everything it left the account holding, roles,
// library access, uploads and permissions alike, lists reading [] when
// empty, under the names an account edit lists them by.
func TestAnApprovalRecordsWhatItAssigned(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	if _, err := svc.AdminSettingsPut(ctx, admin, everySetting(AdminSettings{SignupEnabled: true})); err != nil {
		t.Fatal(err)
	}
	libs, err := svc.Libraries(ctx)
	if err != nil || len(libs) != 1 {
		t.Fatalf("libraries = %+v (%v), want the fixture's one", libs, err)
	}
	upload, quota := true, int64(1<<20)
	for _, c := range []struct {
		name     string
		approval SignupApproval
		want     map[string]string
	}{
		{"sam", SignupApproval{Roles: []string{"admin"}, AccessMode: "granted", LibraryPIDs: []string{libs[0].PID},
			Permissions:   &Permissions{Download: true, MaxTranscodeKbps: 192},
			UploadEnabled: &upload, UploadQuotaBytes: &quota}, map[string]string{
			"roles": "[admin]", "libraryAccess.mode": "granted", "libraryAccess.libraryPids": "[" + libs[0].PID + "]",
			"uploadEnabled": "true", "uploadQuotaBytes": "1.048576e+06",
			"permissions.download": "true", "permissions.delete": "false", "permissions.maxTranscodeKbps": "192",
			"permissions.tagDeny": "[]",
		}},
		{"kim", SignupApproval{}, map[string]string{
			"roles": "[user]", "libraryAccess.mode": "all", "libraryAccess.libraryPids": "[]", "uploadEnabled": "false",
		}},
	} {
		acct, _, err := svc.Signup(ctx, c.name, "password123", "", "")
		if err != nil {
			t.Fatal(err)
		}
		if _, err := svc.ApproveSignup(ctx, admin, acct.User.ID, c.approval); err != nil {
			t.Fatal(err)
		}
		page, err := svc.AuditEvents(ctx, wdb.AuditFilter{Action: "user.approve", TargetPID: acct.User.ID}, "", 10)
		if err != nil || len(page.Events) != 1 {
			t.Fatalf("%s: user.approve entries = %+v (%v), want one", c.name, page.Events, err)
		}
		d := page.Events[0].Detail
		for k, want := range c.want {
			if got := fmt.Sprint(d[k]); got != want {
				t.Errorf("%s: user.approve %s = %s, want %s (detail %v)", c.name, k, got, want, d)
			}
		}
		for _, k := range []string{"permissions.explicitContent", "permissions.sharedOutputs", "permissions.managePodcasts", "permissions.tagAllow"} {
			if _, ok := d[k]; !ok {
				t.Errorf("%s: user.approve detail %v names no %s", c.name, d, k)
			}
		}
	}
}

// An account that signed up with an invite is the actor of its own signup
// entry, which names the invite and the administrator who made it; the
// log does not credit the server.
func TestAnInvitedSignupIsTheNewAccountsOwnAct(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	iv, err := svc.CreateInvite(ctx, admin, InviteCreate{Note: "for grandma"})
	if err != nil {
		t.Fatal(err)
	}
	acct, _, err := svc.Signup(ctx, "grandma", "password123", "", iv.Token)
	if err != nil {
		t.Fatal(err)
	}
	e := onlyAuditEntry(t, ctx, svc, "user.signup")
	if e.ActorID != acct.User.ID || e.ActorName != "grandma" || e.TargetPID != acct.User.ID || e.TargetName != "grandma" {
		t.Errorf("user.signup = %+v, want grandma acting on her own account", e)
	}
	if e.Detail["invite"] != iv.ID || e.Detail["inviteNote"] != "for grandma" || e.Detail["invitedBy"] != "admin" {
		t.Errorf("user.signup detail = %v, want invite %s, note for grandma, invited by admin", e.Detail, iv.ID)
	}
}

// A request to join is the requester's own act as well, so the two ways
// to sign up read alike in the log.
func TestASignupRequestIsTheRequestersOwnAct(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	if _, err := svc.AdminSettingsPut(ctx, admin, everySetting(AdminSettings{SignupEnabled: true})); err != nil {
		t.Fatal(err)
	}
	acct, _, err := svc.Signup(ctx, "sam", "password123", "", "")
	if err != nil {
		t.Fatal(err)
	}
	e := onlyAuditEntry(t, ctx, svc, "user.request")
	if e.ActorID != acct.User.ID || e.ActorName != "sam" || e.TargetPID != acct.User.ID || e.TargetName != "sam" {
		t.Errorf("user.request = %+v, want sam acting on the request", e)
	}
}

func TestAuditRecordsAndFilters(t *testing.T) {
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)
	if _, err := svc.AdminSettingsPut(ctx, admin, everySetting(AdminSettings{SignupEnabled: true})); err != nil {
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
	t.Parallel()
	ctx, svc, admin := newAdminFixture(t)

	rows := svc.Schedules(ctx)
	if len(rows) != len(scheduleKinds) {
		t.Fatalf("schedule kinds: %d, want %d", len(rows), len(scheduleKinds))
	}
	enabled := map[string]bool{}
	for _, row := range rows {
		enabled[row.Kind] = row.Enabled
	}
	// Prune and enrich ship on: prune bounds tables that otherwise grow
	// without bound, and enrich is the only route to artwork and lyrics
	// nobody asked the server to skip. The rest cost enough that an
	// administrator opts in, analyze most of all.
	for kind, on := range enabled {
		if want := kind == "prune" || kind == "enrich"; on != want {
			t.Errorf("%s ships enabled=%v, want %v", kind, on, want)
		}
	}
	// The nightly enrichment lands after prune's window and the scan
	// slot, so a scan an administrator enabled feeds the same night.
	byKind := map[string]ScheduleDTO{}
	for _, row := range rows {
		byKind[row.Kind] = row
	}
	if got := byKind["enrich"].Cron; got != "45 3 * * *" {
		t.Errorf("enrich cron = %q, want the slot after prune and scan", got)
	}
	if _, err := svc.PutSchedule(ctx, admin, "scan", "not a cron", true); KindOf(err) != KindInvalid {
		t.Fatalf("bad cron: got %v, want invalid", err)
	}
	row, err := svc.PutSchedule(ctx, admin, "scan", "0 3 * * *", true)
	if err != nil || !row.Enabled || row.NextRunNS == 0 {
		t.Fatalf("put schedule: %+v %v", row, err)
	}

	// Global read-only refuses the write surfaces via CheckWritable.
	if _, err := svc.AdminSettingsPut(ctx, admin, everySetting(AdminSettings{ReadOnly: true})); err != nil {
		t.Fatal(err)
	}
	if err := svc.CheckWritable(ctx, ""); KindOf(err) != KindReadOnly {
		t.Fatalf("read-only check: got %v, want read-only", err)
	}
	if _, err := svc.AdminSettingsPut(ctx, admin, everySetting(AdminSettings{})); err != nil {
		t.Fatal(err)
	}
	if err := svc.CheckWritable(ctx, ""); err != nil {
		t.Fatalf("writable again: %v", err)
	}
}

func TestLastfmRuntimeCredentials(t *testing.T) {
	t.Parallel()
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

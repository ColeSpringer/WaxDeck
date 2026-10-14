package db

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

// The tables landed ahead of their code keep what a schema can promise:
// per-account rows go with the account, a gpodder session with its app
// password, and a compilation folder set empty differs from one never set.
func TestTheReservedTablesGoWithWhatOwnsThem(t *testing.T) {
	d := openTest(t)
	ctx := context.Background()
	exec := func(q string, args ...any) {
		t.Helper()
		if _, err := d.w.ExecContext(ctx, q, args...); err != nil {
			t.Fatalf("%s: %v", q, err)
		}
	}
	count := func(table string) int {
		t.Helper()
		var n int
		if err := d.r.QueryRowContext(ctx, "SELECT COUNT(*) FROM "+table).Scan(&n); err != nil {
			t.Fatalf("counting %s: %v", table, err)
		}
		return n
	}
	exec(`INSERT INTO users (id, username, username_ci, waxbin_user_pid, created_at_ns, updated_at_ns)
		VALUES ('us-a', 'alice', 'alice', 'U1', 1, 1)`)
	exec(`INSERT INTO app_passwords (id, user_id, label, secret_enc, secret_hash, created_at_ns)
		VALUES ('ap-1', 'us-a', 'phone', x'00', x'01', 1)`)
	exec(`INSERT INTO gpodder_sessions (id, user_id, app_password_id, token_hash, created_at_ns, expires_at_ns)
		VALUES ('gs-1', 'us-a', 'ap-1', x'02', 1, 2)`)
	exec(`INSERT INTO gpodder_holds (user_id, show_pid, holder) VALUES ('us-a', 'pc-1', ''), ('us-a', 'pc-1', 'phone')`)
	exec(`INSERT INTO gpodder_pending (user_id, feed_url, device_id, created_at_ns, next_try_ns)
		VALUES ('us-a', 'https://feeds.example/a.xml', 'phone', 1, 2)`)
	exec(`INSERT INTO subsonic_bookmarks (user_id, item_pid, position_ms, created_at_ns, updated_at_ns)
		VALUES ('us-a', 'tr-1', 5000, 1, 1)`)
	exec(`INSERT INTO subsonic_music_folders (library_pid) VALUES ('lb-1')`)

	exec(`DELETE FROM app_passwords WHERE id = 'ap-1'`)
	if n := count("gpodder_sessions"); n != 0 {
		t.Errorf("gpodder sessions after their app password went = %d, want 0", n)
	}
	exec(`DELETE FROM users WHERE id = 'us-a'`)
	for _, table := range []string{"gpodder_holds", "gpodder_pending", "subsonic_bookmarks"} {
		if n := count(table); n != 0 {
			t.Errorf("%s rows after their account went = %d, want 0", table, n)
		}
	}
	if n := count("subsonic_music_folders"); n != 1 {
		t.Errorf("music folders = %d, want the one, which no account owns", n)
	}

	exec(`INSERT INTO organize_profiles (name, updated_at_ns, compilation_folder) VALUES ('blank', 1, '')`)
	exec(`INSERT INTO organize_profiles (name, updated_at_ns) VALUES ('unset', 1)`)
	for name, want := range map[string]sql.NullString{"blank": {Valid: true}, "unset": {}} {
		var got sql.NullString
		if err := d.r.QueryRowContext(ctx, `SELECT compilation_folder FROM organize_profiles WHERE name = ?`, name).Scan(&got); err != nil {
			t.Fatal(err)
		}
		if got != want {
			t.Errorf("%s compilation_folder = %+v, want %+v", name, got, want)
		}
	}
}

// One verdict decides for Open and for a restore's preflight, so the two
// cannot drift; the newer-build rows need a second migration to reach.
func TestBaselineVerdict(t *testing.T) {
	fp := baselineFingerprint()
	for _, tc := range []struct {
		name       string
		migrations int
		s          stamps
		want       error
	}{
		{"a fresh file", 1, stamps{}, nil},
		{"this build's", 1, stamps{version: 1, syncState: true, stored: fp, found: true}, nil},
		{"no fingerprint yet", 1, stamps{version: 1, syncState: true}, nil},
		{"another baseline's", 1, stamps{version: 1, syncState: true, stored: "x", found: true}, ErrStaleBaseline},
		{"older than the fingerprint", 1, stamps{version: 1}, ErrStaleBaseline},
		{"the old migration chain", 1, stamps{version: 7}, ErrStaleBaseline},
		{"a newer build's", 2, stamps{version: 3}, ErrNewerSchema},
		{"an older build's, to migrate", 2, stamps{version: 1, syncState: true, stored: fp, found: true}, nil},
	} {
		t.Run(tc.name, func(t *testing.T) {
			got := baselineVerdict(tc.migrations, tc.s)
			if tc.want == nil && got != nil || !errors.Is(got, tc.want) {
				t.Errorf("verdict = %v, want %v", got, tc.want)
			}
		})
	}
}

// CheckBaseline refuses exactly what Open refuses, on a copy Open is
// free to adopt or migrate, and fails closed on what it cannot read.
func TestCheckBaselineAnswersWhatOpenDoes(t *testing.T) {
	ctx := context.Background()
	for _, tc := range []struct{ name, alter string }{
		{"this build's", ""},
		{"another baseline's", "UPDATE sync_state SET value = 'elsewhere' WHERE key = 'schema.baseline'"},
		{"no fingerprint yet", "DELETE FROM sync_state WHERE key = 'schema.baseline'"},
		{"the old migration chain", "PRAGMA user_version = 7"},
		{"older than the fingerprint", "DROP TABLE sync_state"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			path := filepath.Join(dir, "waxdeck.db")
			d, err := Open(ctx, path)
			if err != nil {
				t.Fatal(err)
			}
			if tc.alter != "" {
				if _, err := d.w.ExecContext(ctx, tc.alter); err != nil {
					t.Fatal(err)
				}
			}
			if err := d.Close(); err != nil {
				t.Fatal(err)
			}
			raw, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			copyPath := filepath.Join(dir, "copy.db")
			if err := os.WriteFile(copyPath, raw, 0o600); err != nil {
				t.Fatal(err)
			}
			checked := CheckBaseline(ctx, path)
			opened, openErr := Open(ctx, copyPath)
			if openErr == nil {
				opened.Close()
			}
			if (checked == nil) != (openErr == nil) || checked != nil && !errors.Is(openErr, ErrStaleBaseline) {
				t.Errorf("CheckBaseline = %v, Open = %v", checked, openErr)
			}
		})
	}
	dir := t.TempDir()
	junk := filepath.Join(dir, "junk.db")
	if err := os.WriteFile(junk, []byte("not a database at all, just bytes"), 0o600); err != nil {
		t.Fatal(err)
	}
	canceled, cancel := context.WithCancel(ctx)
	cancel()
	for name, run := range map[string]func() error{
		"a missing file":     func() error { return CheckBaseline(ctx, filepath.Join(dir, "absent.db")) },
		"a file not SQLite":  func() error { return CheckBaseline(ctx, junk) },
		"a canceled context": func() error { return CheckBaseline(canceled, filepath.Join(dir, "absent.db")) },
	} {
		if err := run(); err == nil {
			t.Errorf("%s: CheckBaseline passed it", name)
		}
	}
}

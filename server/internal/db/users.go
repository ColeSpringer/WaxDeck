package db

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"
)

// User is one account row. Roles is stored comma-separated and exposed
// as a slice; LibraryAccess is "all" or "granted" (grants live in
// library_grants). PasswordHash is empty for accounts without local
// login (OIDC-provisioned accounts that never set a password).
type User struct {
	ID            string
	Username      string
	DisplayName   string
	PasswordHash  string
	Roles         []string
	Disabled      bool
	LibraryAccess string
	WaxbinUserPID string
	CreatedAt     time.Time
	UpdatedAt     time.Time
}

// Identity is one linked OIDC identity.
type Identity struct {
	UserID   string
	Provider string
	Subject  string
	Email    string
}

// ErrNotFound reports a missing row. Callers translate it to their own
// error taxonomy.
var ErrNotFound = errors.New("db: not found")

// ErrConflict reports a uniqueness violation (taken username, replayed
// insert).
var ErrConflict = errors.New("db: conflict")

const userCols = "id, username, display_name, password_hash, roles, disabled, library_access, waxbin_user_pid, created_at_ns, updated_at_ns"

func scanUser(row interface{ Scan(...any) error }) (*User, error) {
	var u User
	var roles string
	var created, updated int64
	err := row.Scan(&u.ID, &u.Username, &u.DisplayName, &u.PasswordHash, &roles,
		&u.Disabled, &u.LibraryAccess, &u.WaxbinUserPID, &created, &updated)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	u.Roles = splitRoles(roles)
	u.CreatedAt = time.Unix(0, created).UTC()
	u.UpdatedAt = time.Unix(0, updated).UTC()
	return &u, nil
}

func splitRoles(s string) []string {
	if s == "" {
		return nil
	}
	return strings.Split(s, ",")
}

func joinRoles(roles []string) string { return strings.Join(roles, ",") }

// CreateUser inserts a new account. A case-insensitively taken username
// returns ErrConflict. When onlyIfNoAdmin is set (the bootstrap door),
// the insert carries its own guard and applies only while no enabled
// administrator exists: two concurrent bootstraps with different
// usernames would both pass a separate count, but only one guarded
// insert can succeed; the loser returns ErrConflict.
func (d *DB) CreateUser(ctx context.Context, u *User, onlyIfNoAdmin bool) error {
	now := time.Now().UnixNano()
	stmt := `INSERT INTO users (id, username, username_ci, display_name, password_hash, roles,
	                            disabled, library_access, waxbin_user_pid, created_at_ns, updated_at_ns)
	         SELECT ?,?,?,?,?,?,?,?,?,?,?`
	if onlyIfNoAdmin {
		stmt += ` WHERE NOT EXISTS (SELECT 1 FROM users WHERE ` + enabledAdminPredicate + `)`
	}
	res, err := d.w.ExecContext(ctx, stmt,
		u.ID, u.Username, strings.ToLower(u.Username), u.DisplayName, u.PasswordHash,
		joinRoles(u.Roles), u.Disabled, u.LibraryAccess, u.WaxbinUserPID, now, now)
	if err != nil {
		if isUniqueViolation(err) {
			return ErrConflict
		}
		return err
	}
	if n, err := res.RowsAffected(); err != nil {
		return err
	} else if n == 0 {
		return ErrConflict
	}
	u.CreatedAt = time.Unix(0, now).UTC()
	u.UpdatedAt = u.CreatedAt
	return nil
}

// UserByID fetches one account.
func (d *DB) UserByID(ctx context.Context, id string) (*User, error) {
	return scanUser(d.r.QueryRowContext(ctx, `SELECT `+userCols+` FROM users WHERE id = ?`, id))
}

// UserByUsername fetches one account by case-insensitive username.
func (d *DB) UserByUsername(ctx context.Context, username string) (*User, error) {
	return scanUser(d.r.QueryRowContext(ctx,
		`SELECT `+userCols+` FROM users WHERE username_ci = ?`, strings.ToLower(username)))
}

// enabledAdminPredicate matches enabled admin rows; the roles column is
// comma-separated.
const enabledAdminPredicate = `disabled = 0 AND (','||roles||',') LIKE '%,admin,%'`

// CountEnabledAdmins counts enabled admin accounts.
func (d *DB) CountEnabledAdmins(ctx context.Context) (int, error) {
	var n int
	err := d.r.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM users WHERE `+enabledAdminPredicate).Scan(&n)
	return n, err
}

// UpdateUser persists the mutable account fields. When
// requireOtherAdmin is set, the update carries its own guard: it
// applies only while another enabled administrator exists, in one
// atomic statement, so two concurrent demotions can never leave the
// server adminless (a separate count-then-write would race). A guard
// refusal returns ErrConflict.
func (d *DB) UpdateUser(ctx context.Context, u *User, requireOtherAdmin bool) error {
	guard := ""
	if requireOtherAdmin {
		guard = ` AND EXISTS (SELECT 1 FROM users other WHERE other.id != users.id AND other.` +
			`disabled = 0 AND (','||other.roles||',') LIKE '%,admin,%')`
	}
	res, err := d.w.ExecContext(ctx,
		`UPDATE users SET display_name = ?, password_hash = ?, roles = ?, disabled = ?,
		        library_access = ?, updated_at_ns = ?
		 WHERE id = ?`+guard,
		u.DisplayName, u.PasswordHash, joinRoles(u.Roles), u.Disabled,
		u.LibraryAccess, time.Now().UnixNano(), u.ID)
	if err != nil {
		return err
	}
	return d.classifyGuardedResult(ctx, res, u.ID, requireOtherAdmin)
}

// DeleteUser removes the account; sessions, grants, prefs, identities,
// and pending codes cascade. requireOtherAdmin guards exactly like
// UpdateUser's.
func (d *DB) DeleteUser(ctx context.Context, id string, requireOtherAdmin bool) error {
	guard := ""
	if requireOtherAdmin {
		guard = ` AND EXISTS (SELECT 1 FROM users other WHERE other.id != users.id AND other.` +
			`disabled = 0 AND (','||other.roles||',') LIKE '%,admin,%')`
	}
	res, err := d.w.ExecContext(ctx, `DELETE FROM users WHERE id = ?`+guard, id)
	if err != nil {
		return err
	}
	return d.classifyGuardedResult(ctx, res, id, requireOtherAdmin)
}

// classifyGuardedResult turns a zero-row guarded mutation into the
// right error: the row not existing is ErrNotFound, the guard refusing
// is ErrConflict. The existence probe runs after the fact, purely for
// classification; the atomicity lives in the guarded statement itself.
func (d *DB) classifyGuardedResult(ctx context.Context, res sql.Result, id string, guarded bool) error {
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n > 0 {
		return nil
	}
	if !guarded {
		return ErrNotFound
	}
	if _, err := d.UserByID(ctx, id); errors.Is(err, ErrNotFound) {
		return ErrNotFound
	}
	return ErrConflict
}

// ListUsers pages accounts by username. The cursor is the previous
// page's last username_ci; the empty cursor starts at the head.
func (d *DB) ListUsers(ctx context.Context, afterUsernameCI string, limit int) ([]*User, error) {
	rows, err := d.r.QueryContext(ctx,
		`SELECT `+userCols+` FROM users WHERE username_ci > ? ORDER BY username_ci LIMIT ?`,
		afterUsernameCI, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*User
	for rows.Next() {
		u, err := scanUser(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// SetLibraryGrants replaces the account's granted-library set.
func (d *DB) SetLibraryGrants(ctx context.Context, userID string, libraryPIDs []string) error {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `DELETE FROM library_grants WHERE user_id = ?`, userID); err != nil {
		return err
	}
	for _, pid := range libraryPIDs {
		if _, err := tx.ExecContext(ctx,
			`INSERT OR IGNORE INTO library_grants (user_id, library_pid) VALUES (?,?)`, userID, pid); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// LibraryGrants returns the account's granted library PIDs.
func (d *DB) LibraryGrants(ctx context.Context, userID string) ([]string, error) {
	rows, err := d.r.QueryContext(ctx,
		`SELECT library_pid FROM library_grants WHERE user_id = ? ORDER BY library_pid`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var pid string
		if err := rows.Scan(&pid); err != nil {
			return nil, err
		}
		out = append(out, pid)
	}
	return out, rows.Err()
}

// LinkIdentity records an OIDC identity for the account, updating the
// stored email on re-link. A subject already linked to a different
// account returns ErrConflict.
func (d *DB) LinkIdentity(ctx context.Context, ident Identity) error {
	res, err := d.w.ExecContext(ctx,
		`INSERT INTO identities (user_id, provider, subject, email, created_at_ns)
		 VALUES (?,?,?,?,?)
		 ON CONFLICT (provider, subject) DO UPDATE SET email = excluded.email
		 WHERE identities.user_id = excluded.user_id`,
		ident.UserID, ident.Provider, ident.Subject, ident.Email, time.Now().UnixNano())
	if err != nil {
		return err
	}
	// A conflicting row owned by another user matches neither the insert
	// nor the guarded update: zero rows affected.
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrConflict
	}
	return nil
}

// IdentityBySubject resolves a provider identity to its account.
func (d *DB) IdentityBySubject(ctx context.Context, provider, subject string) (*Identity, error) {
	var ident Identity
	err := d.r.QueryRowContext(ctx,
		`SELECT user_id, provider, subject, email FROM identities WHERE provider = ? AND subject = ?`,
		provider, subject).Scan(&ident.UserID, &ident.Provider, &ident.Subject, &ident.Email)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &ident, nil
}

// IdentitiesByUser lists the account's linked identities.
func (d *DB) IdentitiesByUser(ctx context.Context, userID string) ([]Identity, error) {
	rows, err := d.r.QueryContext(ctx,
		`SELECT user_id, provider, subject, email FROM identities WHERE user_id = ? ORDER BY provider`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Identity
	for rows.Next() {
		var ident Identity
		if err := rows.Scan(&ident.UserID, &ident.Provider, &ident.Subject, &ident.Email); err != nil {
			return nil, err
		}
		out = append(out, ident)
	}
	return out, rows.Err()
}

func isUniqueViolation(err error) bool {
	return err != nil && strings.Contains(err.Error(), "UNIQUE")
}

func requireRow(res sql.Result) error {
	n, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

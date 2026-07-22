package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"
)

// Invite is one invite link's record. Only the token's hash is stored;
// the token itself is shown once, at creation. Perms is the permission
// preset as raw JSON (empty means registration defaults), LibraryGrants
// the granted-library pids as a JSON array; both shapes belong to the
// service layer.
type Invite struct {
	ID               string
	TokenHash        []byte
	Note             string
	Roles            []string
	LibraryAccess    string
	LibraryGrants    string
	Perms            string
	UploadEnabled    bool
	UploadQuotaBytes int64
	MaxUses          int
	UsedCount        int
	Revoked          bool
	ExpiresAtNS      int64
	CreatedBy        string
	CreatedAtNS      int64
}

const inviteCols = `id, token_hash, note, roles, library_access, library_grants, perms,
	upload_enabled, upload_quota_bytes, max_uses, used_count, revoked,
	expires_at_ns, created_by, created_at_ns`

func scanInvite(row interface{ Scan(...any) error }) (Invite, error) {
	var iv Invite
	var roles string
	err := row.Scan(&iv.ID, &iv.TokenHash, &iv.Note, &roles, &iv.LibraryAccess,
		&iv.LibraryGrants, &iv.Perms, &iv.UploadEnabled, &iv.UploadQuotaBytes,
		&iv.MaxUses, &iv.UsedCount, &iv.Revoked, &iv.ExpiresAtNS, &iv.CreatedBy, &iv.CreatedAtNS)
	if err != nil {
		return Invite{}, err
	}
	iv.Roles = splitRoles(roles)
	return iv, nil
}

// InsertInvite stores a new invite.
func (d *DB) InsertInvite(ctx context.Context, iv Invite) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO invites (`+inviteCols+`)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		iv.ID, iv.TokenHash, iv.Note, joinRoles(iv.Roles), iv.LibraryAccess,
		iv.LibraryGrants, iv.Perms, iv.UploadEnabled, iv.UploadQuotaBytes,
		iv.MaxUses, iv.UsedCount, iv.Revoked, iv.ExpiresAtNS, iv.CreatedBy, iv.CreatedAtNS)
	if err != nil {
		return fmt.Errorf("db: inserting invite: %w", err)
	}
	return nil
}

// ListInvites returns every invite, newest first.
func (d *DB) ListInvites(ctx context.Context) ([]Invite, error) {
	rows, err := d.r.QueryContext(ctx,
		`SELECT `+inviteCols+` FROM invites ORDER BY created_at_ns DESC, id DESC`)
	if err != nil {
		return nil, fmt.Errorf("db: listing invites: %w", err)
	}
	defer rows.Close()
	var out []Invite
	for rows.Next() {
		iv, err := scanInvite(rows)
		if err != nil {
			return nil, fmt.Errorf("db: scanning invite: %w", err)
		}
		out = append(out, iv)
	}
	return out, rows.Err()
}

// RevokeInvite marks the invite revoked; ErrNotFound when absent.
func (d *DB) RevokeInvite(ctx context.Context, id string) error {
	res, err := d.w.ExecContext(ctx, `UPDATE invites SET revoked = 1 WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("db: revoking invite: %w", err)
	}
	return requireRow(res)
}

// ConsumeInvite claims one use of a live invite by token hash, in a
// single guarded statement so two concurrent signups cannot both take
// the last use. ErrNotFound covers every refusal (absent, revoked,
// expired, exhausted): the caller must not tell an attacker which.
func (d *DB) ConsumeInvite(ctx context.Context, tokenHash []byte) (Invite, error) {
	row := d.w.QueryRowContext(ctx, `
		UPDATE invites SET used_count = used_count + 1
		WHERE token_hash = ? AND revoked = 0
		  AND (expires_at_ns = 0 OR expires_at_ns > ?)
		  AND (max_uses = 0 OR used_count < max_uses)
		RETURNING `+inviteCols,
		tokenHash, time.Now().UnixNano())
	iv, err := scanInvite(row)
	if errors.Is(err, sql.ErrNoRows) {
		return Invite{}, ErrNotFound
	}
	if err != nil {
		return Invite{}, fmt.Errorf("db: consuming invite: %w", err)
	}
	return iv, nil
}

// UnconsumeInvite returns a use claimed by ConsumeInvite, for when the
// signup it admitted failed after the claim (taken username).
func (d *DB) UnconsumeInvite(ctx context.Context, id string) error {
	_, err := d.w.ExecContext(ctx,
		`UPDATE invites SET used_count = used_count - 1 WHERE id = ? AND used_count > 0`, id)
	if err != nil {
		return fmt.Errorf("db: unconsuming invite: %w", err)
	}
	return nil
}

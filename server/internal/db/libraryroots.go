package db

import (
	"context"
	"fmt"
)

// LibraryRoot is the name of a library root added at runtime.
type LibraryRoot struct {
	Path        string
	Name        string
	CreatedAtNS int64
}

// LibraryRootsList reads every stored root, by path.
func (d *DB) LibraryRootsList(ctx context.Context) ([]LibraryRoot, error) {
	rows, err := d.r.QueryContext(ctx, `SELECT path, name, created_at_ns FROM library_roots ORDER BY path`)
	if err != nil {
		return nil, fmt.Errorf("db: listing library roots: %w", err)
	}
	defer rows.Close()
	var out []LibraryRoot
	for rows.Next() {
		var r LibraryRoot
		if err := rows.Scan(&r.Path, &r.Name, &r.CreatedAtNS); err != nil {
			return nil, fmt.Errorf("db: scanning library root: %w", err)
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// LibraryRootsUpsert stores a root's name; a renamed root keeps its
// creation time.
func (d *DB) LibraryRootsUpsert(ctx context.Context, r LibraryRoot) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO library_roots (path, name, created_at_ns) VALUES (?, ?, ?)
		ON CONFLICT (path) DO UPDATE SET name = excluded.name`,
		r.Path, r.Name, r.CreatedAtNS)
	if err != nil {
		return fmt.Errorf("db: storing library root: %w", err)
	}
	return nil
}

// LibraryRootsDelete drops the name stored for path; an unknown path is
// not an error.
func (d *DB) LibraryRootsDelete(ctx context.Context, path string) error {
	if _, err := d.w.ExecContext(ctx, `DELETE FROM library_roots WHERE path = ?`, path); err != nil {
		return fmt.Errorf("db: dropping library root: %w", err)
	}
	return nil
}

// PruneLibraryGrants takes a removed library's pid out of every account's
// granted libraries and every invite's.
func (d *DB) PruneLibraryGrants(ctx context.Context, libraryPID string) error {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: pruning library grants: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `DELETE FROM library_grants WHERE library_pid = ?`, libraryPID); err != nil {
		return fmt.Errorf("db: pruning library grants: %w", err)
	}
	if _, err := tx.ExecContext(ctx, `
		UPDATE invites SET library_grants = (
			SELECT json_group_array(value) FROM json_each(invites.library_grants) WHERE value <> ?)
		WHERE EXISTS (SELECT 1 FROM json_each(invites.library_grants) WHERE value = ?)`,
		libraryPID, libraryPID); err != nil {
		return fmt.Errorf("db: pruning invite grants: %w", err)
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("db: pruning library grants: %w", err)
	}
	return nil
}

// GrantedLibraryPIDs lists every library pid an account's or an invite's
// grants name, once each.
func (d *DB) GrantedLibraryPIDs(ctx context.Context) ([]string, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT library_pid FROM library_grants
		UNION
		SELECT value FROM invites, json_each(invites.library_grants)
		ORDER BY 1`)
	if err != nil {
		return nil, fmt.Errorf("db: listing granted libraries: %w", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var pid string
		if err := rows.Scan(&pid); err != nil {
			return nil, fmt.Errorf("db: scanning a granted library: %w", err)
		}
		out = append(out, pid)
	}
	return out, rows.Err()
}

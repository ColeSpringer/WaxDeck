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

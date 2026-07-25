package db

import (
	"context"
	"encoding/json"
	"fmt"
)

// GenreNode is one row of the instance's canonical genre vocabulary:
// the display spelling, the top-level genre it groups under (empty for
// one of those), and the synonyms that resolve to it.
type GenreNode struct {
	Name    string
	Parent  string
	Aliases []string
}

// GenreTree reads the stored vocabulary. An empty result is the normal
// state and means the instance runs on the shipped default; the caller
// decides what to substitute, since this package holds no vocabulary of
// its own.
func (d *DB) GenreTree(ctx context.Context) ([]GenreNode, error) {
	rows, err := d.r.QueryContext(ctx,
		`SELECT name, parent, aliases FROM genre_tree ORDER BY name`)
	if err != nil {
		return nil, fmt.Errorf("db: reading the genre tree: %w", err)
	}
	defer rows.Close()
	var out []GenreNode
	for rows.Next() {
		var n GenreNode
		var aliases string
		if err := rows.Scan(&n.Name, &n.Parent, &aliases); err != nil {
			return nil, fmt.Errorf("db: reading the genre tree: %w", err)
		}
		if aliases != "" {
			if err := json.Unmarshal([]byte(aliases), &n.Aliases); err != nil {
				return nil, fmt.Errorf("db: reading genre %q aliases: %w", n.Name, err)
			}
		}
		out = append(out, n)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("db: reading the genre tree: %w", err)
	}
	return out, nil
}

// ReplaceGenreTree stores the vocabulary as a whole, in one transaction:
// a genre browse must never read a half-applied tree, where an alias
// still points at a name the same edit removed. Passing no nodes clears
// the override and returns the instance to the shipped default.
func (d *DB) ReplaceGenreTree(ctx context.Context, nodes []GenreNode) error {
	tx, err := d.w.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("db: writing the genre tree: %w", err)
	}
	defer tx.Rollback()
	if _, err := tx.ExecContext(ctx, `DELETE FROM genre_tree`); err != nil {
		return fmt.Errorf("db: writing the genre tree: %w", err)
	}
	for _, n := range nodes {
		aliases, err := json.Marshal(n.Aliases)
		if err != nil {
			return fmt.Errorf("db: writing genre %q aliases: %w", n.Name, err)
		}
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO genre_tree (name, parent, aliases) VALUES (?, ?, ?)`,
			n.Name, n.Parent, string(aliases)); err != nil {
			return fmt.Errorf("db: writing genre %q: %w", n.Name, err)
		}
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("db: writing the genre tree: %w", err)
	}
	return nil
}

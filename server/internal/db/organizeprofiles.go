package db

import (
	"context"
	"database/sql"
	"fmt"
)

// OrganizeProfile is an admin-defined layout profile. A name matching a
// built-in overrides it, and an empty template inherits.
type OrganizeProfile struct {
	Name      string
	Music     string
	Audiobook string
	Podcast   string
	TagWrite  bool
	// CompilationFolder is where compilations file: nil takes the
	// catalog's default, empty their own tagged album artist.
	CompilationFolder *string
	UpdatedAtNS       int64
}

// OrganizeProfilesList reads every stored profile, by name.
func (d *DB) OrganizeProfilesList(ctx context.Context) ([]OrganizeProfile, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT name, music, audiobook, podcast, tag_write, compilation_folder, updated_at_ns
		FROM organize_profiles ORDER BY name`)
	if err != nil {
		return nil, fmt.Errorf("db: listing organize profiles: %w", err)
	}
	defer rows.Close()
	var out []OrganizeProfile
	for rows.Next() {
		var p OrganizeProfile
		var folder sql.NullString
		if err := rows.Scan(&p.Name, &p.Music, &p.Audiobook, &p.Podcast, &p.TagWrite, &folder, &p.UpdatedAtNS); err != nil {
			return nil, fmt.Errorf("db: scanning organize profile: %w", err)
		}
		if folder.Valid {
			p.CompilationFolder = &folder.String
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// OrganizeProfilesUpsert stores a profile, replacing one of the same name.
func (d *DB) OrganizeProfilesUpsert(ctx context.Context, p OrganizeProfile) error {
	var folder sql.NullString
	if p.CompilationFolder != nil {
		folder = sql.NullString{String: *p.CompilationFolder, Valid: true}
	}
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO organize_profiles (name, music, audiobook, podcast, tag_write, compilation_folder, updated_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (name) DO UPDATE SET music = excluded.music, audiobook = excluded.audiobook,
			podcast = excluded.podcast, tag_write = excluded.tag_write,
			compilation_folder = excluded.compilation_folder,
			updated_at_ns = excluded.updated_at_ns`,
		p.Name, p.Music, p.Audiobook, p.Podcast, p.TagWrite, folder, p.UpdatedAtNS)
	if err != nil {
		return fmt.Errorf("db: storing organize profile: %w", err)
	}
	return nil
}

// OrganizeProfilesDelete removes a profile; an absent one is not an error.
func (d *DB) OrganizeProfilesDelete(ctx context.Context, name string) error {
	if _, err := d.w.ExecContext(ctx, `DELETE FROM organize_profiles WHERE name = ?`, name); err != nil {
		return fmt.Errorf("db: deleting organize profile: %w", err)
	}
	return nil
}

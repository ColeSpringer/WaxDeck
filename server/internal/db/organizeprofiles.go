package db

import (
	"context"
	"fmt"
)

// OrganizeProfile is an admin-defined layout profile. A name matching a
// built-in overrides it, and an empty template inherits.
type OrganizeProfile struct {
	Name        string
	Music       string
	Audiobook   string
	Podcast     string
	TagWrite    bool
	UpdatedAtNS int64
}

// OrganizeProfilesList reads every stored profile, by name.
func (d *DB) OrganizeProfilesList(ctx context.Context) ([]OrganizeProfile, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT name, music, audiobook, podcast, tag_write, updated_at_ns
		FROM organize_profiles ORDER BY name`)
	if err != nil {
		return nil, fmt.Errorf("db: listing organize profiles: %w", err)
	}
	defer rows.Close()
	var out []OrganizeProfile
	for rows.Next() {
		var p OrganizeProfile
		if err := rows.Scan(&p.Name, &p.Music, &p.Audiobook, &p.Podcast, &p.TagWrite, &p.UpdatedAtNS); err != nil {
			return nil, fmt.Errorf("db: scanning organize profile: %w", err)
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

// OrganizeProfilesUpsert stores a profile, replacing one of the same name.
func (d *DB) OrganizeProfilesUpsert(ctx context.Context, p OrganizeProfile) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO organize_profiles (name, music, audiobook, podcast, tag_write, updated_at_ns)
		VALUES (?, ?, ?, ?, ?, ?)
		ON CONFLICT (name) DO UPDATE SET music = excluded.music, audiobook = excluded.audiobook,
			podcast = excluded.podcast, tag_write = excluded.tag_write,
			updated_at_ns = excluded.updated_at_ns`,
		p.Name, p.Music, p.Audiobook, p.Podcast, p.TagWrite, p.UpdatedAtNS)
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

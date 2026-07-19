package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// radioStationCap bounds the shared station library. Radio stations are a
// curated household list, not a growing collection; the cap keeps the
// unpaginated listing honest.
const radioStationCap = 500

// RadioStation is one entry in the shared internet radio library.
type RadioStation struct {
	ID          string
	Name        string
	StreamURL   string
	HomepageURL string
	LogoURL     string
	CreatedBy   string
	CreatedAtNS int64
}

// ListRadioStations returns the whole station library ordered by name.
func (d *DB) ListRadioStations(ctx context.Context) ([]RadioStation, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT id, name, stream_url, homepage_url, logo_url, created_by, created_at_ns
		FROM radio_stations ORDER BY name COLLATE NOCASE, id`)
	if err != nil {
		return nil, fmt.Errorf("db: listing radio stations: %w", err)
	}
	defer rows.Close()
	var out []RadioStation
	for rows.Next() {
		var s RadioStation
		if err := rows.Scan(&s.ID, &s.Name, &s.StreamURL, &s.HomepageURL, &s.LogoURL, &s.CreatedBy, &s.CreatedAtNS); err != nil {
			return nil, fmt.Errorf("db: scanning radio station: %w", err)
		}
		out = append(out, s)
	}
	return out, rows.Err()
}

// RadioStationByID reads one station; ErrNotFound when absent.
func (d *DB) RadioStationByID(ctx context.Context, id string) (RadioStation, error) {
	var s RadioStation
	err := d.r.QueryRowContext(ctx, `
		SELECT id, name, stream_url, homepage_url, logo_url, created_by, created_at_ns
		FROM radio_stations WHERE id = ?`, id).
		Scan(&s.ID, &s.Name, &s.StreamURL, &s.HomepageURL, &s.LogoURL, &s.CreatedBy, &s.CreatedAtNS)
	if errors.Is(err, sql.ErrNoRows) {
		return RadioStation{}, ErrNotFound
	}
	if err != nil {
		return RadioStation{}, fmt.Errorf("db: reading radio station: %w", err)
	}
	return s, nil
}

// CreateRadioStation inserts a station, guarding the stream URL's
// uniqueness and the library cap inside the statement so concurrent
// creates cannot slip past either. ErrConflict covers both refusals;
// the caller disambiguates if it needs a precise message.
func (d *DB) CreateRadioStation(ctx context.Context, s RadioStation) error {
	res, err := d.w.ExecContext(ctx, `
		INSERT INTO radio_stations (id, name, stream_url, homepage_url, logo_url, created_by, created_at_ns)
		SELECT ?, ?, ?, ?, ?, ?, ?
		WHERE (SELECT COUNT(*) FROM radio_stations) < ?
		ON CONFLICT (stream_url) DO NOTHING`,
		s.ID, s.Name, s.StreamURL, s.HomepageURL, s.LogoURL, s.CreatedBy, s.CreatedAtNS,
		radioStationCap)
	if err != nil {
		return fmt.Errorf("db: creating radio station: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("db: creating radio station: %w", err)
	}
	if n == 0 {
		return ErrConflict
	}
	return nil
}

// UpdateRadioStation replaces a station's fields. The stream URL
// uniqueness guard lives in the statement; zero rows means the station
// is missing or the new URL belongs to another station, disambiguated
// with a follow-up read.
func (d *DB) UpdateRadioStation(ctx context.Context, s RadioStation) error {
	res, err := d.w.ExecContext(ctx, `
		UPDATE radio_stations SET name = ?, stream_url = ?, homepage_url = ?, logo_url = ?
		WHERE id = ?
		AND NOT EXISTS (SELECT 1 FROM radio_stations o WHERE o.stream_url = ? AND o.id <> ?)`,
		s.Name, s.StreamURL, s.HomepageURL, s.LogoURL, s.ID, s.StreamURL, s.ID)
	if err != nil {
		return fmt.Errorf("db: updating radio station: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("db: updating radio station: %w", err)
	}
	if n == 0 {
		if _, err := d.radioStationWrite(ctx, s.ID); errors.Is(err, ErrNotFound) {
			return ErrNotFound
		} else if err != nil {
			return err
		}
		return ErrConflict
	}
	return nil
}

// radioStationWrite reads through the write connection, so the row a
// guard statement just examined is visible regardless of read-pool
// snapshot timing.
func (d *DB) radioStationWrite(ctx context.Context, id string) (RadioStation, error) {
	var s RadioStation
	err := d.w.QueryRowContext(ctx, `
		SELECT id, name, stream_url, homepage_url, logo_url, created_by, created_at_ns
		FROM radio_stations WHERE id = ?`, id).
		Scan(&s.ID, &s.Name, &s.StreamURL, &s.HomepageURL, &s.LogoURL, &s.CreatedBy, &s.CreatedAtNS)
	if errors.Is(err, sql.ErrNoRows) {
		return RadioStation{}, ErrNotFound
	}
	if err != nil {
		return RadioStation{}, fmt.Errorf("db: reading radio station: %w", err)
	}
	return s, nil
}

// DeleteRadioStation removes a station; ErrNotFound when absent.
func (d *DB) DeleteRadioStation(ctx context.Context, id string) error {
	res, err := d.w.ExecContext(ctx, `DELETE FROM radio_stations WHERE id = ?`, id)
	if err != nil {
		return fmt.Errorf("db: deleting radio station: %w", err)
	}
	n, err := res.RowsAffected()
	if err != nil {
		return fmt.Errorf("db: deleting radio station: %w", err)
	}
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

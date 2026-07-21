package db

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
)

// PlayerEndpointRow is one persisted device endpoint (cast, DLNA,
// jukebox). Client endpoints are never persisted: they exist while
// their WebSocket connection does.
type PlayerEndpointRow struct {
	ID          string
	Kind        string
	DeviceKey   string
	Name        string
	Address     string
	Details     string
	Shared      bool
	LastSeenNS  int64
	CreatedAtNS int64
}

// UpsertPlayerEndpoint records a discovered device endpoint, keyed by
// its stable device identity, and returns the row (the existing id
// wins on rediscovery, so a device keeps its endpoint pid across
// address changes and restarts).
func (d *DB) UpsertPlayerEndpoint(ctx context.Context, row PlayerEndpointRow) (PlayerEndpointRow, error) {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO player_endpoints (id, kind, device_key, name, address, details, shared, last_seen_ns, created_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (kind, device_key) DO UPDATE SET
			name = excluded.name,
			address = excluded.address,
			details = excluded.details,
			last_seen_ns = excluded.last_seen_ns`,
		row.ID, row.Kind, row.DeviceKey, row.Name, row.Address, row.Details,
		boolInt(row.Shared), row.LastSeenNS, row.CreatedAtNS)
	if err != nil {
		return PlayerEndpointRow{}, fmt.Errorf("db: upserting player endpoint: %w", err)
	}
	return d.playerEndpointByKey(ctx, row.Kind, row.DeviceKey)
}

func (d *DB) playerEndpointByKey(ctx context.Context, kind, deviceKey string) (PlayerEndpointRow, error) {
	var row PlayerEndpointRow
	var shared int
	err := d.r.QueryRowContext(ctx, `
		SELECT id, kind, device_key, name, address, details, shared, last_seen_ns, created_at_ns
		FROM player_endpoints WHERE kind = ? AND device_key = ?`, kind, deviceKey).
		Scan(&row.ID, &row.Kind, &row.DeviceKey, &row.Name, &row.Address, &row.Details,
			&shared, &row.LastSeenNS, &row.CreatedAtNS)
	if errors.Is(err, sql.ErrNoRows) {
		return PlayerEndpointRow{}, ErrNotFound
	}
	if err != nil {
		return PlayerEndpointRow{}, fmt.Errorf("db: reading player endpoint: %w", err)
	}
	row.Shared = shared != 0
	return row, nil
}

// ListPlayerEndpoints returns every persisted device endpoint.
func (d *DB) ListPlayerEndpoints(ctx context.Context) ([]PlayerEndpointRow, error) {
	rows, err := d.r.QueryContext(ctx, `
		SELECT id, kind, device_key, name, address, details, shared, last_seen_ns, created_at_ns
		FROM player_endpoints ORDER BY name COLLATE NOCASE, id`)
	if err != nil {
		return nil, fmt.Errorf("db: listing player endpoints: %w", err)
	}
	defer rows.Close()
	var out []PlayerEndpointRow
	for rows.Next() {
		var row PlayerEndpointRow
		var shared int
		if err := rows.Scan(&row.ID, &row.Kind, &row.DeviceKey, &row.Name, &row.Address,
			&row.Details, &shared, &row.LastSeenNS, &row.CreatedAtNS); err != nil {
			return nil, fmt.Errorf("db: scanning player endpoint: %w", err)
		}
		row.Shared = shared != 0
		out = append(out, row)
	}
	return out, rows.Err()
}

// PlaybackSessionRow is the checkpointed state of one playback
// session. State is the session manager's JSON snapshot; the schema is
// owned by the connect package.
type PlaybackSessionRow struct {
	ID          string
	UserID      string
	EndpointID  string
	Authority   string
	State       string
	Active      bool
	CreatedAtNS int64
	UpdatedAtNS int64
}

// SavePlaybackSession upserts a session checkpoint.
func (d *DB) SavePlaybackSession(ctx context.Context, row PlaybackSessionRow) error {
	_, err := d.w.ExecContext(ctx, `
		INSERT INTO playback_sessions (id, user_id, endpoint_id, authority, state, active, created_at_ns, updated_at_ns)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT (id) DO UPDATE SET
			endpoint_id = excluded.endpoint_id,
			authority = excluded.authority,
			state = excluded.state,
			active = excluded.active,
			updated_at_ns = excluded.updated_at_ns`,
		row.ID, row.UserID, row.EndpointID, row.Authority, row.State,
		boolInt(row.Active), row.CreatedAtNS, row.UpdatedAtNS)
	if err != nil {
		return fmt.Errorf("db: saving playback session: %w", err)
	}
	return nil
}

// DeactivatePlaybackSessions marks every active session row inactive.
// Called at boot: a crash or restart never resumes remote playback by
// itself, but the final state stays readable as restore history.
func (d *DB) DeactivatePlaybackSessions(ctx context.Context) error {
	if _, err := d.w.ExecContext(ctx,
		`UPDATE playback_sessions SET active = 0 WHERE active = 1`); err != nil {
		return fmt.Errorf("db: deactivating playback sessions: %w", err)
	}
	return nil
}

// PrunePlaybackSessions keeps the newest keepPerUser inactive rows per
// user and deletes the rest.
func (d *DB) PrunePlaybackSessions(ctx context.Context, keepPerUser int) error {
	_, err := d.w.ExecContext(ctx, `
		DELETE FROM playback_sessions WHERE active = 0 AND id NOT IN (
			SELECT id FROM playback_sessions ps
			WHERE ps.active = 0 AND ps.id IN (
				SELECT id FROM playback_sessions inner_ps
				WHERE inner_ps.user_id = ps.user_id AND inner_ps.active = 0
				ORDER BY inner_ps.updated_at_ns DESC LIMIT ?
			)
		)`, keepPerUser)
	if err != nil {
		return fmt.Errorf("db: pruning playback sessions: %w", err)
	}
	return nil
}

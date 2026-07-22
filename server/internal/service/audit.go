package service

import (
	"context"
	"encoding/json"
	"strconv"
	"time"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// AuditTarget names what an audited action acted on. Name is captured
// at write time so the entry outlives the target.
type AuditTarget struct {
	Kind string
	PID  string
	Name string
}

// AuditEventDTO is one audit entry for the admin surface.
type AuditEventDTO struct {
	ID          string
	ActorID     string
	ActorName   string
	Action      string
	TargetKind  string
	TargetPID   string
	TargetName  string
	Detail      map[string]any
	CreatedAtNS int64
}

// AuditPage is one keyset page of audit events.
type AuditPage struct {
	Events []AuditEventDTO
	Next   string
}

// Audit records an administrative or destructive action. A nil actor
// means the server itself (scheduled jobs, startup restore, signup
// self-service). Recording is deliberately best-effort: the action
// already happened, and failing it over its record would trade a
// consistent audit trail for an inconsistent system.
func (l *Library) Audit(ctx context.Context, actor *UserCtx, action string, target AuditTarget, detail map[string]any) {
	e := wdb.AuditEvent{
		Action:      action,
		TargetKind:  target.Kind,
		TargetPID:   target.PID,
		TargetName:  target.Name,
		Detail:      "{}",
		CreatedAtNS: time.Now().UnixNano(),
	}
	if actor != nil {
		e.ActorID = actor.ID
		e.ActorName = l.usernameOf(ctx, actor.ID)
	}
	if len(detail) > 0 {
		if raw, err := json.Marshal(detail); err == nil {
			e.Detail = string(raw)
		}
	}
	if err := l.db.AppendAudit(ctx, e); err != nil {
		l.log.Warn("recording audit event", "action", action, "err", err)
	}
}

// actorName renders an actor for denormalized storage fields.
func actorName(actor *UserCtx) string {
	if actor == nil {
		return ""
	}
	return actor.ID
}

// usernameOf resolves a user id to its username, falling back to the
// id itself (better an id in the log than nothing).
func (l *Library) usernameOf(ctx context.Context, userID string) string {
	u, err := l.db.UserByID(ctx, userID)
	if err != nil {
		return userID
	}
	return u.Username
}

// AuditEvents pages the audit log newest first, with optional filters.
// The cursor is the previous page's last event id.
func (l *Library) AuditEvents(ctx context.Context, filter wdb.AuditFilter, cursor string, limit int) (AuditPage, error) {
	var before int64
	if cursor != "" {
		n, err := strconv.ParseInt(cursor, 10, 64)
		if err != nil || n <= 0 {
			return AuditPage{}, errInvalid("bad cursor")
		}
		before = n
	}
	rows, err := l.db.ListAudit(ctx, filter, before, limit+1)
	if err != nil {
		return AuditPage{}, &Error{Kind: KindInternal, Err: err}
	}
	page := AuditPage{}
	more := len(rows) > limit
	if more {
		rows = rows[:limit]
	}
	for _, e := range rows {
		dto := AuditEventDTO{
			ID:          strconv.FormatInt(e.ID, 10),
			ActorID:     e.ActorID,
			ActorName:   e.ActorName,
			Action:      e.Action,
			TargetKind:  e.TargetKind,
			TargetPID:   e.TargetPID,
			TargetName:  e.TargetName,
			CreatedAtNS: e.CreatedAtNS,
		}
		if e.Detail != "" && e.Detail != "{}" {
			var m map[string]any
			if err := json.Unmarshal([]byte(e.Detail), &m); err == nil {
				dto.Detail = m
			}
		}
		page.Events = append(page.Events, dto)
	}
	if more && len(rows) > 0 {
		page.Next = strconv.FormatInt(rows[len(rows)-1].ID, 10)
	}
	return page, nil
}

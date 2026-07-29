package service

import (
	"context"
	"encoding/json"
	"time"

	"github.com/colespringer/waxdeck/server/internal/cron"
)

// ScheduleDTO is one scheduled job's configuration and history.
type ScheduleDTO struct {
	Kind       string
	Cron       string
	Enabled    bool
	LastRunNS  int64
	LastStatus string
	LastError  string
	NextRunNS  int64
}

// scheduleKinds is the closed schedule set: each kind exists exactly
// once. Scan, backup, and analyze ship disabled until an administrator
// opts in; prune ships enabled because the event log and stamp tables
// otherwise grow without bound.
var scheduleKinds = []string{"scan", "backup", "prune", "analyze"}

// Analyze defaults to a weekly small-hours window rather than a nightly
// one. It is the only pass that decodes audio, so it is priced in hours
// on a large library and there is nothing to re-analyze until new files
// arrive; a nightly firing would mostly wake up to find nothing to do.
var scheduleDefaults = map[string]scheduleState{
	"scan":    {Cron: "0 3 * * *"},
	"backup":  {Cron: "0 4 * * 0"},
	"prune":   {Cron: "30 3 * * *", Enabled: true},
	"analyze": {Cron: "0 2 * * 0"},
}

// scheduleState is the persisted per-kind document (settings KV).
type scheduleState struct {
	Cron       string `json:"cron"`
	Enabled    bool   `json:"enabled"`
	LastRunNS  int64  `json:"lastRunNs,omitempty"`
	LastStatus string `json:"lastStatus,omitempty"`
	LastError  string `json:"lastError,omitempty"`
}

func scheduleKey(kind string) string { return "schedule:" + kind }

func validScheduleKind(kind string) bool {
	for _, k := range scheduleKinds {
		if k == kind {
			return true
		}
	}
	return false
}

func (l *Library) scheduleState(ctx context.Context, kind string) scheduleState {
	st := scheduleDefaults[kind]
	if raw, err := l.db.SettingGet(ctx, scheduleKey(kind)); err == nil {
		var loaded scheduleState
		if err := json.Unmarshal([]byte(raw), &loaded); err == nil {
			st = loaded
		}
	}
	return st
}

func (l *Library) writeScheduleState(ctx context.Context, kind string, st scheduleState) error {
	raw, err := json.Marshal(st)
	if err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.SettingSet(ctx, scheduleKey(kind), string(raw), time.Now().UnixNano()); err != nil {
		return &Error{Kind: KindInternal, Err: err}
	}
	return nil
}

func scheduleDTO(kind string, st scheduleState) ScheduleDTO {
	out := ScheduleDTO{
		Kind:       kind,
		Cron:       st.Cron,
		Enabled:    st.Enabled,
		LastRunNS:  st.LastRunNS,
		LastStatus: st.LastStatus,
		LastError:  st.LastError,
	}
	if st.Enabled {
		if sched, err := cron.Parse(st.Cron); err == nil {
			if next := sched.Next(time.Now()); !next.IsZero() {
				out.NextRunNS = next.UnixNano()
			}
		}
	}
	return out
}

// Schedules lists every schedule kind with its state.
func (l *Library) Schedules(ctx context.Context) []ScheduleDTO {
	out := make([]ScheduleDTO, 0, len(scheduleKinds))
	for _, kind := range scheduleKinds {
		out = append(out, scheduleDTO(kind, l.scheduleState(ctx, kind)))
	}
	return out
}

// PutSchedule replaces one schedule's cron and enabled state, keeping
// its run history.
func (l *Library) PutSchedule(ctx context.Context, actor *UserCtx, kind, cronSpec string, enabled bool) (ScheduleDTO, error) {
	if !validScheduleKind(kind) {
		return ScheduleDTO{}, errInvalid("unknown schedule kind " + kind)
	}
	if _, err := cron.Parse(cronSpec); err != nil {
		return ScheduleDTO{}, errInvalid(err.Error())
	}
	st := l.scheduleState(ctx, kind)
	st.Cron, st.Enabled = cronSpec, enabled
	if err := l.writeScheduleState(ctx, kind, st); err != nil {
		return ScheduleDTO{}, err
	}
	l.Audit(ctx, actor, "schedule.update", AuditTarget{Kind: "schedule", Name: kind},
		map[string]any{"cron": cronSpec, "enabled": enabled})
	return scheduleDTO(kind, st), nil
}

// DueSchedule reports whether the kind is enabled and due at now: its
// cron has a firing time after the last run (or the last check) and at
// or before now. lastCheck bounds the window for schedules that were
// never run, so enabling one does not fire it retroactively.
func (l *Library) DueSchedule(ctx context.Context, kind string, lastCheck, now time.Time) bool {
	st := l.scheduleState(ctx, kind)
	if !st.Enabled {
		return false
	}
	sched, err := cron.Parse(st.Cron)
	if err != nil {
		return false
	}
	after := lastCheck
	if st.LastRunNS > 0 {
		if t := time.Unix(0, st.LastRunNS); t.After(after) {
			after = t
		}
	}
	next := sched.Next(after)
	return !next.IsZero() && !next.After(now)
}

// MarkScheduleRun records a run's outcome.
func (l *Library) MarkScheduleRun(ctx context.Context, kind string, runErr error) {
	st := l.scheduleState(ctx, kind)
	st.LastRunNS = time.Now().UnixNano()
	if runErr != nil {
		st.LastStatus, st.LastError = "failed", runErr.Error()
	} else {
		st.LastStatus, st.LastError = "ok", ""
	}
	if err := l.writeScheduleState(ctx, kind, st); err != nil {
		l.log.Warn("recording schedule run", "kind", kind, "err", err)
	}
}

// RunPrune is the scheduled prune pass: event log, mutation stamps,
// audit log, and ended playback sessions. Horizons are deliberately
// server-owned constants; sync consumers whose cursor falls below the
// surviving event floor get a clean resync by design.
func (l *Library) RunPrune(ctx context.Context) error {
	const (
		keepEvents      = 100_000
		keepAudit       = 50_000
		stampRetention  = 365 * 24 * time.Hour
		keepSessionsPer = 5
	)
	var firstErr error
	record := func(what string, err error) {
		if err != nil {
			l.log.Warn("scheduled prune", "what", what, "err", err)
			if firstErr == nil {
				firstErr = err
			}
		}
	}
	n, err := l.PruneServerEvents(ctx, keepEvents)
	record("event log", err)
	if n > 0 {
		l.log.Info("pruned event log", "rows", n)
	}
	sn, err := l.db.PruneStamps(ctx, time.Now().Add(-stampRetention).UnixNano())
	record("play stamps", err)
	if sn > 0 {
		l.log.Info("pruned play stamps", "rows", sn)
	}
	an, err := l.db.PruneAudit(ctx, keepAudit)
	record("audit log", err)
	if an > 0 {
		l.log.Info("pruned audit log", "rows", an)
	}
	record("playback sessions", l.db.PrunePlaybackSessions(ctx, keepSessionsPer))
	return firstErr
}

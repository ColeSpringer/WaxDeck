package service

import (
	"context"
	"encoding/json"
	"strconv"
	"time"
)

// AdminSettings are the runtime-editable server settings.
type AdminSettings struct {
	SignupEnabled   bool
	ReadOnly        bool
	BackupKeepCount int
	BackupKeepBytes int64
}

// TranscodingLimits cap transcode sessions at the media proxy; zero
// values mean unlimited.
type TranscodingLimits struct {
	MaxConcurrent         int
	MaxConcurrentPerUser  int
	DefaultMaxBitrateKbps int
}

const (
	settingReadOnly        = "server:read-only"
	settingBackupKeep      = "backup:keep-count"
	settingBackupKeepBytes = "backup:keep-bytes"
	settingTranscodeLimits = "transcode:limits"
	readOnlyLibPrefix      = "read-only:"
)

// runtimeToggles is the hot-path cache of settings consulted per
// request (read-only checks on every write surface, transcode limits on
// every stream). Loaded at Open, swapped whole on every settings write.
type runtimeToggles struct {
	readOnly     bool
	readOnlyLibs map[string]bool // bare library pid -> read-only
	limits       TranscodingLimits
}

// loadRuntimeToggles primes the settings cache; called at Open and
// after every settings mutation.
func (l *Library) loadRuntimeToggles(ctx context.Context) {
	t := &runtimeToggles{readOnlyLibs: map[string]bool{}}
	if v, err := l.db.SettingGet(ctx, settingReadOnly); err == nil {
		t.readOnly = v == "true"
	}
	if raw, err := l.db.SettingGet(ctx, settingTranscodeLimits); err == nil {
		var lim TranscodingLimits
		if err := json.Unmarshal([]byte(raw), &lim); err == nil {
			t.limits = lim
		}
	}
	if pids, err := l.db.SettingsWithPrefix(ctx, readOnlyLibPrefix); err == nil {
		for key, v := range pids {
			if v == "true" {
				t.readOnlyLibs[key[len(readOnlyLibPrefix):]] = true
			}
		}
	}
	l.toggles.Store(t)
}

// currentToggles never returns nil; before the first load everything is
// permissive-off, matching a fresh database.
func (l *Library) currentToggles() *runtimeToggles {
	if t, ok := l.toggles.Load().(*runtimeToggles); ok && t != nil {
		return t
	}
	return &runtimeToggles{readOnlyLibs: map[string]bool{}}
}

// AdminSettingsGet reads the runtime settings.
func (l *Library) AdminSettingsGet(ctx context.Context) (AdminSettings, error) {
	out := AdminSettings{SignupEnabled: l.SignupEnabled(ctx), ReadOnly: l.currentToggles().readOnly}
	if v, err := l.db.SettingGet(ctx, settingBackupKeep); err == nil {
		out.BackupKeepCount, _ = strconv.Atoi(v)
	}
	if v, err := l.db.SettingGet(ctx, settingBackupKeepBytes); err == nil {
		out.BackupKeepBytes, _ = strconv.ParseInt(v, 10, 64)
	}
	return out, nil
}

// AdminSettingsPut replaces the runtime settings; they apply
// immediately.
func (l *Library) AdminSettingsPut(ctx context.Context, actor *UserCtx, s AdminSettings) (AdminSettings, error) {
	if s.BackupKeepCount < 0 || s.BackupKeepBytes < 0 {
		return AdminSettings{}, errInvalid("backup retention must not be negative")
	}
	now := time.Now().UnixNano()
	writes := map[string]string{
		settingSignupEnabled:   strconv.FormatBool(s.SignupEnabled),
		settingReadOnly:        strconv.FormatBool(s.ReadOnly),
		settingBackupKeep:      strconv.Itoa(s.BackupKeepCount),
		settingBackupKeepBytes: strconv.FormatInt(s.BackupKeepBytes, 10),
	}
	for k, v := range writes {
		if err := l.db.SettingSet(ctx, k, v, now); err != nil {
			return AdminSettings{}, &Error{Kind: KindInternal, Err: err}
		}
	}
	l.loadRuntimeToggles(ctx)
	l.Audit(ctx, actor, "settings.update", AuditTarget{Kind: "settings"},
		map[string]any{"signupEnabled": s.SignupEnabled, "readOnly": s.ReadOnly,
			"backupKeepCount": s.BackupKeepCount, "backupKeepBytes": s.BackupKeepBytes})
	return l.AdminSettingsGet(ctx)
}

// TranscodingLimitsGet reads the transcode limits.
func (l *Library) TranscodingLimitsGet(ctx context.Context) TranscodingLimits {
	return l.currentToggles().limits
}

// TranscodingLimitsPut replaces the transcode limits.
func (l *Library) TranscodingLimitsPut(ctx context.Context, actor *UserCtx, lim TranscodingLimits) (TranscodingLimits, error) {
	if lim.MaxConcurrent < 0 || lim.MaxConcurrentPerUser < 0 || lim.DefaultMaxBitrateKbps < 0 {
		return TranscodingLimits{}, errInvalid("limits must not be negative")
	}
	raw, err := json.Marshal(lim)
	if err != nil {
		return TranscodingLimits{}, &Error{Kind: KindInternal, Err: err}
	}
	if err := l.db.SettingSet(ctx, settingTranscodeLimits, string(raw), time.Now().UnixNano()); err != nil {
		return TranscodingLimits{}, &Error{Kind: KindInternal, Err: err}
	}
	l.loadRuntimeToggles(ctx)
	l.Audit(ctx, actor, "transcoding.update", AuditTarget{Kind: "settings"},
		map[string]any{"maxConcurrent": lim.MaxConcurrent,
			"maxConcurrentPerUser":  lim.MaxConcurrentPerUser,
			"defaultMaxBitrateKbps": lim.DefaultMaxBitrateKbps})
	return lim, nil
}

// LibraryReadOnlyGet reads one library's read-only flag; the library
// must exist.
func (l *Library) LibraryReadOnlyGet(ctx context.Context, apiLibraryPID string) (bool, error) {
	pid, err := l.libraryPIDOf(ctx, apiLibraryPID)
	if err != nil {
		return false, err
	}
	return l.currentToggles().readOnlyLibs[pid], nil
}

// LibraryReadOnlySet flips one library's read-only flag.
func (l *Library) LibraryReadOnlySet(ctx context.Context, actor *UserCtx, apiLibraryPID string, readOnly bool) error {
	pid, err := l.libraryPIDOf(ctx, apiLibraryPID)
	if err != nil {
		return err
	}
	if readOnly {
		if err := l.db.SettingSet(ctx, readOnlyLibPrefix+pid, "true", time.Now().UnixNano()); err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
	} else {
		if err := l.db.SettingDelete(ctx, readOnlyLibPrefix+pid); err != nil {
			return &Error{Kind: KindInternal, Err: err}
		}
	}
	l.loadRuntimeToggles(ctx)
	l.Audit(ctx, actor, "library.read-only",
		AuditTarget{Kind: "library", PID: apiLibraryPID},
		map[string]any{"readOnly": readOnly})
	return nil
}

// libraryPIDOf validates an API library pid against the catalog and
// returns the bare pid.
func (l *Library) libraryPIDOf(ctx context.Context, apiLibraryPID string) (string, error) {
	prefix, pid, ok := parseAPIPID(apiLibraryPID)
	if !ok || prefix != PrefixLibrary {
		return "", errInvalid("bad library pid " + apiLibraryPID)
	}
	libs, err := l.lib.Libraries(ctx)
	if err != nil {
		return "", classify(err)
	}
	for _, lib := range libs {
		if string(lib.PID) == string(pid) {
			return string(pid), nil
		}
	}
	return "", errNotFound("no library with pid " + apiLibraryPID)
}

// errReadOnly is the uniform refusal for writes into read-only scope.
func errReadOnly(what string) error {
	return &Error{Kind: KindReadOnly, Msg: what + " is read-only on this server"}
}

// CheckWritable refuses when the whole server, or the named library, is
// read-only. An empty library pid checks only the global flag (staging
// surfaces that have no target library yet).
func (l *Library) CheckWritable(ctx context.Context, bareLibraryPID string) error {
	t := l.currentToggles()
	if t.readOnly {
		return errReadOnly("the library")
	}
	if bareLibraryPID != "" && t.readOnlyLibs[bareLibraryPID] {
		return errReadOnly("this library")
	}
	return nil
}

// checkPathWritable is CheckWritable keyed by a file path, for
// surfaces that know the file before the library.
func (l *Library) checkPathWritable(ctx context.Context, path string) error {
	if err := l.CheckWritable(ctx, ""); err != nil {
		return err
	}
	pid, err := l.libraryForPath(ctx, path)
	if err != nil {
		return err
	}
	if pid == "" {
		return nil
	}
	return l.CheckWritable(ctx, pid)
}

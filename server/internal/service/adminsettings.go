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
	SonicAnalysis   bool
	BackupKeepCount int
	BackupKeepBytes int64
	// TrashRetentionDays purges trashed files older than this many days on
	// a periodic sweep; 0 disables retention (the trash keeps entries until
	// emptied by hand).
	TrashRetentionDays int
	// TaskRetentionDays clears terminal tool tasks older than this many
	// days on the scheduled prune; 0 keeps them, unset answers
	// defaultTaskRetentionDays.
	TaskRetentionDays int
	// EnrichmentWriteTags makes the whole-library enrichment pass write
	// what it filled back into the files, which is what makes enrichment
	// survive a rescan. Off by default: the catalog is authoritative and
	// this touches the listener's own files.
	EnrichmentWriteTags bool
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
	settingSonicAnalysis   = "similarity:analysis"
	settingBackupKeep      = "backup:keep-count"
	settingBackupKeepBytes = "backup:keep-bytes"
	settingTranscodeLimits = "transcode:limits"
	settingTrashRetention  = "trash:retention-days"
	settingEnrichWriteTags = "enrichment:write-tags"
	settingTaskRetention   = "tasks:retention-days"
	readOnlyLibPrefix      = "read-only:"

	// maxRetentionDays bounds both retention windows at 100 years, far
	// under the ~106752 days where days*24h overflows time.Duration.
	maxRetentionDays = 36500

	// defaultTaskRetentionDays is what the prune ran on before the knob.
	// Unset rather than zero, unlike trash retention: an unconfigured
	// task list was already being swept.
	defaultTaskRetentionDays = 30
)

// runtimeToggles is the hot-path cache of settings consulted per
// request (read-only checks on every write surface, transcode limits on
// every stream). Loaded at Open, swapped whole on every settings write.
type runtimeToggles struct {
	readOnly     bool
	readOnlyLibs map[string]bool // bare library pid -> read-only
	limits       TranscodingLimits
	// sonicAnalysis is nil until an administrator has saved the
	// setting; the boot default (WAXDECK_SONIC_ANALYSIS) applies then.
	sonicAnalysis *bool
	// enrichWriteTags rides the enrichment pass as EnrichOptions.WriteTags
	// rather than as catalog config, which is what lets it be a runtime
	// toggle at all: the library-level option is fixed at open, and the
	// catalog ORs the two.
	enrichWriteTags bool
}

// loadRuntimeToggles primes the settings cache; called at Open and
// after every settings mutation.
func (l *Library) loadRuntimeToggles(ctx context.Context) {
	t := &runtimeToggles{readOnlyLibs: map[string]bool{}}
	if v, err := l.db.SettingGet(ctx, settingReadOnly); err == nil {
		t.readOnly = v == "true"
	}
	if v, err := l.db.SettingGet(ctx, settingSonicAnalysis); err == nil {
		on := v == "true"
		t.sonicAnalysis = &on
	}
	if v, err := l.db.SettingGet(ctx, settingEnrichWriteTags); err == nil {
		t.enrichWriteTags = v == "true"
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
	out := AdminSettings{
		SignupEnabled:       l.SignupEnabled(ctx),
		ReadOnly:            l.currentToggles().readOnly,
		SonicAnalysis:       l.SonicAnalysisEnabled(),
		EnrichmentWriteTags: l.currentToggles().enrichWriteTags,
	}
	if v, err := l.db.SettingGet(ctx, settingBackupKeep); err == nil {
		out.BackupKeepCount, _ = strconv.Atoi(v)
	}
	if v, err := l.db.SettingGet(ctx, settingBackupKeepBytes); err == nil {
		out.BackupKeepBytes, _ = strconv.ParseInt(v, 10, 64)
	}
	out.TrashRetentionDays = l.TrashRetentionDays(ctx)
	out.TaskRetentionDays = l.TaskRetentionDays(ctx)
	return out, nil
}

// TrashRetentionDays reads the configured trash retention window in days;
// 0 (the default and the value on a parse error) disables retention.
func (l *Library) TrashRetentionDays(ctx context.Context) int {
	v, err := l.db.SettingGet(ctx, settingTrashRetention)
	if err != nil {
		return 0
	}
	days, err := strconv.Atoi(v)
	if err != nil || days < 0 {
		return 0
	}
	// Clamp at read too: a value stored before the cap existed (or set
	// out-of-band) must never reach the sweep's day-to-duration conversion
	// large enough to overflow.
	if days > maxRetentionDays {
		return maxRetentionDays
	}
	return days
}

// TaskRetentionDays reads the tool-task retention window. Unset answers
// the default; a stored 0 is "keep them", so the two are told apart.
func (l *Library) TaskRetentionDays(ctx context.Context) int {
	v, err := l.db.SettingGet(ctx, settingTaskRetention)
	if err != nil {
		return defaultTaskRetentionDays
	}
	days, err := strconv.Atoi(v)
	if err != nil || days < 0 {
		return defaultTaskRetentionDays
	}
	if days > maxRetentionDays {
		return maxRetentionDays
	}
	return days
}

// AdminSettingsPut replaces the runtime settings; they apply
// immediately.
func (l *Library) AdminSettingsPut(ctx context.Context, actor *UserCtx, s AdminSettings) (AdminSettings, error) {
	if s.BackupKeepCount < 0 || s.BackupKeepBytes < 0 {
		return AdminSettings{}, errInvalid("backup retention must not be negative")
	}
	// Cap well under the point where days*24h overflows time.Duration's
	// int64 nanoseconds (~106752 days): a wrapped negative would silently
	// disable the sweep and a wrapped-positive-small could over-purge.
	if s.TrashRetentionDays < 0 || s.TrashRetentionDays > maxRetentionDays {
		return AdminSettings{}, errInvalid("trash retention must be between 0 and 36500 days")
	}
	if s.TaskRetentionDays < 0 || s.TaskRetentionDays > maxRetentionDays {
		return AdminSettings{}, errInvalid("task retention must be between 0 and 36500 days")
	}
	now := time.Now().UnixNano()
	writes := map[string]string{
		settingSignupEnabled:   strconv.FormatBool(s.SignupEnabled),
		settingReadOnly:        strconv.FormatBool(s.ReadOnly),
		settingSonicAnalysis:   strconv.FormatBool(s.SonicAnalysis),
		settingBackupKeep:      strconv.Itoa(s.BackupKeepCount),
		settingBackupKeepBytes: strconv.FormatInt(s.BackupKeepBytes, 10),
		settingTrashRetention:  strconv.Itoa(s.TrashRetentionDays),
		settingTaskRetention:   strconv.Itoa(s.TaskRetentionDays),
		settingEnrichWriteTags: strconv.FormatBool(s.EnrichmentWriteTags),
	}
	for k, v := range writes {
		if err := l.db.SettingSet(ctx, k, v, now); err != nil {
			return AdminSettings{}, &Error{Kind: KindInternal, Err: err}
		}
	}
	l.loadRuntimeToggles(ctx)
	l.Audit(ctx, actor, "settings.update", AuditTarget{Kind: "settings"},
		map[string]any{"signupEnabled": s.SignupEnabled, "readOnly": s.ReadOnly,
			"sonicAnalysis":   s.SonicAnalysis,
			"backupKeepCount": s.BackupKeepCount, "backupKeepBytes": s.BackupKeepBytes,
			"trashRetentionDays":  s.TrashRetentionDays,
			"taskRetentionDays":   s.TaskRetentionDays,
			"enrichmentWriteTags": s.EnrichmentWriteTags})
	return l.AdminSettingsGet(ctx)
}

// EnrichmentWriteTagsEnabled reports whether an enrichment pass should
// write what it filled back into the files. Cached, so the settings PUT
// reads it without a round trip.
func (l *Library) EnrichmentWriteTagsEnabled() bool {
	return l.currentToggles().enrichWriteTags
}

// SonicAnalysisEnabled reports whether the embedded analyzer should
// run: the saved runtime setting when an administrator has touched it,
// the boot default otherwise.
func (l *Library) SonicAnalysisEnabled() bool {
	if v := l.currentToggles().sonicAnalysis; v != nil {
		return *v
	}
	return l.sonicAnalysisDefault
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

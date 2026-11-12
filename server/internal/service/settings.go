package service

import (
	"context"
	"encoding/json"
	"strconv"
	"sync"
	"sync/atomic"
	"time"

	"github.com/colespringer/waxbin/model"
)

// Settings is the admin settings and the runtime toggles they drive.
type Settings struct {
	*core
	// toggles is the hot-path settings cache (the server's read-only flag,
	// transcode limits), swapped whole on every write.
	toggles atomic.Value
	// adminSettingsMu keeps one write to the runtime settings at a time,
	// so no two reloads of the toggles cache race.
	adminSettingsMu sync.Mutex
	// sonicAnalysisDefault mirrors Config.SonicAnalysisDefault.
	sonicAnalysisDefault bool
}

func newSettings(c *core, cfg Config) *Settings {
	return &Settings{core: c, sonicAnalysisDefault: cfg.SonicAnalysisDefault}
}

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
	// RadioExternalArt lets radio look a station's announced title up
	// against MusicBrainz and the Cover Art Archive when nothing in this
	// library matches it. On by default.
	RadioExternalArt bool
}

// AdminSettingsChange is a write of some settings: a nil field keeps its
// stored value.
type AdminSettingsChange struct {
	SignupEnabled       *bool
	ReadOnly            *bool
	SonicAnalysis       *bool
	BackupKeepCount     *int
	BackupKeepBytes     *int64
	TrashRetentionDays  *int
	TaskRetentionDays   *int
	EnrichmentWriteTags *bool
	RadioExternalArt    *bool
}

// TranscodingLimits cap transcode sessions at the media proxy; zero
// values mean unlimited.
type TranscodingLimits struct {
	MaxConcurrent         int
	MaxConcurrentPerUser  int
	DefaultMaxBitrateKbps int
}

const (
	settingReadOnly         = "server:read-only"
	settingSonicAnalysis    = "similarity:analysis"
	settingBackupKeep       = "backup:keep-count"
	settingBackupKeepBytes  = "backup:keep-bytes"
	settingTranscodeLimits  = "transcode:limits"
	settingTrashRetention   = "trash:retention-days"
	settingEnrichWriteTags  = "enrichment:write-tags"
	settingRadioExternalArt = "radio:external-art"
	settingTaskRetention    = "tasks:retention-days"

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
	readOnly bool
	limits   TranscodingLimits
	// sonicAnalysis is nil until an administrator has saved the
	// setting; the boot default (WAXDECK_SONIC_ANALYSIS) applies then.
	sonicAnalysis *bool
	// enrichWriteTags rides the enrichment pass as EnrichOptions.WriteTags
	// rather than as catalog config, which is what lets it be a runtime
	// toggle at all: the library-level option is fixed at open, and the
	// catalog ORs the two.
	enrichWriteTags bool
	// radioExternalArt gates the outbound half of radio artwork.
	radioExternalArt bool
}

// enrichWritesTags is whether an enrichment pass writes into files; the
// catalog leaves a read-only library's files out itself.
func (l *Settings) enrichWritesTags(context.Context) bool {
	t := l.currentToggles()
	return t.enrichWriteTags && !t.readOnly
}

// loadRuntimeToggles primes the settings cache; called at Open and
// after every settings mutation.
func (l *Settings) loadRuntimeToggles(ctx context.Context) {
	t := &runtimeToggles{}
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
	// On unless an operator has said otherwise.
	t.radioExternalArt = true
	if v, err := l.db.SettingGet(ctx, settingRadioExternalArt); err == nil {
		t.radioExternalArt = v == "true"
	}
	if raw, err := l.db.SettingGet(ctx, settingTranscodeLimits); err == nil {
		var lim TranscodingLimits
		if err := json.Unmarshal([]byte(raw), &lim); err == nil {
			t.limits = lim
		}
	}
	l.toggles.Store(t)
	l.Enrichment.loadEnrichSources(ctx)
}

// currentToggles never returns nil; before the first load everything is
// permissive-off, matching a fresh database.
func (l *Settings) currentToggles() *runtimeToggles {
	if t, ok := l.toggles.Load().(*runtimeToggles); ok && t != nil {
		return t
	}
	return &runtimeToggles{}
}

// AdminSettingsGet reads the runtime settings.
func (l *Settings) AdminSettingsGet(ctx context.Context) (AdminSettings, error) {
	out := AdminSettings{
		SignupEnabled:       l.Identity.SignupEnabled(ctx),
		ReadOnly:            l.currentToggles().readOnly,
		SonicAnalysis:       l.SonicAnalysisEnabled(),
		EnrichmentWriteTags: l.currentToggles().enrichWriteTags,
		RadioExternalArt:    l.RadioExternalArtEnabled(),
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
func (l *Settings) TrashRetentionDays(ctx context.Context) int {
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
func (l *Settings) TaskRetentionDays(ctx context.Context) int {
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

// AdminSettingsPut stores the settings c names and keeps the rest as
// stored; they apply immediately. A refused field stores none of them.
func (l *Settings) AdminSettingsPut(ctx context.Context, actor *UserCtx, c AdminSettingsChange) (AdminSettings, error) {
	if c.BackupKeepCount != nil && *c.BackupKeepCount < 0 || c.BackupKeepBytes != nil && *c.BackupKeepBytes < 0 {
		return AdminSettings{}, errInvalid("backup retention must not be negative")
	}
	// Cap well under the point where days*24h overflows time.Duration's
	// int64 nanoseconds (~106752 days): a wrapped negative would silently
	// disable the sweep and a wrapped-positive-small could over-purge.
	if d := c.TrashRetentionDays; d != nil && (*d < 0 || *d > maxRetentionDays) {
		return AdminSettings{}, errInvalid("trash retention must be between 0 and 36500 days")
	}
	if d := c.TaskRetentionDays; d != nil && (*d < 0 || *d > maxRetentionDays) {
		return AdminSettings{}, errInvalid("task retention must be between 0 and 36500 days")
	}
	writes := map[string]string{}
	detail := map[string]any{}
	set := func(key, field, value string, shown any) {
		writes[key] = value
		detail[field] = shown
	}
	if v := c.SignupEnabled; v != nil {
		set(settingSignupEnabled, "signupEnabled", strconv.FormatBool(*v), *v)
	}
	if v := c.ReadOnly; v != nil {
		set(settingReadOnly, "readOnly", strconv.FormatBool(*v), *v)
	}
	if v := c.SonicAnalysis; v != nil {
		set(settingSonicAnalysis, "sonicAnalysis", strconv.FormatBool(*v), *v)
	}
	if v := c.BackupKeepCount; v != nil {
		set(settingBackupKeep, "backupKeepCount", strconv.Itoa(*v), *v)
	}
	if v := c.BackupKeepBytes; v != nil {
		set(settingBackupKeepBytes, "backupKeepBytes", strconv.FormatInt(*v, 10), *v)
	}
	if v := c.TrashRetentionDays; v != nil {
		set(settingTrashRetention, "trashRetentionDays", strconv.Itoa(*v), *v)
	}
	if v := c.TaskRetentionDays; v != nil {
		set(settingTaskRetention, "taskRetentionDays", strconv.Itoa(*v), *v)
	}
	if v := c.EnrichmentWriteTags; v != nil {
		set(settingEnrichWriteTags, "enrichmentWriteTags", strconv.FormatBool(*v), *v)
	}
	if v := c.RadioExternalArt; v != nil {
		set(settingRadioExternalArt, "radioExternalArt", strconv.FormatBool(*v), *v)
	}
	if len(writes) == 0 {
		return l.AdminSettingsGet(ctx)
	}

	// One write at a time, so the toggles cache reloaded after one cannot
	// land over the reload of the next.
	l.adminSettingsMu.Lock()
	defer l.adminSettingsMu.Unlock()
	now := time.Now().UnixNano()
	wasRadioArt := l.RadioExternalArtEnabled()
	wasReadOnly := l.ServerReadOnly()
	wasSonic := l.SonicAnalysisEnabled()
	for k, v := range writes {
		if err := l.db.SettingSet(ctx, k, v, now); err != nil {
			return AdminSettings{}, &Error{Kind: KindInternal, Err: err}
		}
	}
	l.loadRuntimeToggles(ctx)
	if isReadOnly := l.ServerReadOnly(); wasReadOnly != isReadOnly {
		// The session carries the flag, and the account marker is what
		// makes an open client read it again.
		l.Jobs.emitEveryoneEvent(ctx, eventAccount)
		if wasReadOnly {
			// No managed root was probed while the server was read-only.
			l.Roots.probeRoots()
		}
	}
	if !wasSonic && l.SonicAnalysisEnabled() {
		// A library scanned while analysis was off joins the queue now,
		// not at the sweep's backstop.
		l.Similarity.wakeup()
	}
	if wasRadioArt && !l.RadioExternalArtEnabled() {
		// Switching the rung off drops what it fetched. The read path
		// refuses while it is off regardless, so this is about not
		// holding a third party's bytes after the decision to stop
		// asking for them rather than about correctness.
		l.Radio.forgetRadioArt()
	}
	l.Audit.Record(ctx, actor, "settings.update", AuditTarget{Kind: "settings"}, detail)
	return l.AdminSettingsGet(ctx)
}

// RadioExternalArtEnabled reports whether radio may look an announced
// title up against MusicBrainz and the Cover Art Archive. Cached, like
// every other runtime toggle, so the play-info poll reads it without a
// round trip.
func (l *Settings) RadioExternalArtEnabled() bool {
	return l.currentToggles().radioExternalArt
}

// SonicAnalysisEnabled reports whether the embedded analyzer should
// run: the saved runtime setting when an administrator has touched it,
// the boot default otherwise.
func (l *Settings) SonicAnalysisEnabled() bool {
	if v := l.currentToggles().sonicAnalysis; v != nil {
		return *v
	}
	return l.sonicAnalysisDefault
}

// TranscodingLimitsGet reads the transcode limits.
func (l *Settings) TranscodingLimitsGet(ctx context.Context) TranscodingLimits {
	return l.currentToggles().limits
}

// TranscodingLimitsPut replaces the transcode limits.
func (l *Settings) TranscodingLimitsPut(ctx context.Context, actor *UserCtx, lim TranscodingLimits) (TranscodingLimits, error) {
	if lim.MaxConcurrent < 0 || lim.MaxConcurrentPerUser < 0 || lim.DefaultMaxBitrateKbps < 0 {
		return TranscodingLimits{}, errInvalid("limits must not be negative")
	}
	raw, err := json.Marshal(lim)
	if err != nil {
		return TranscodingLimits{}, &Error{Kind: KindInternal, Err: err}
	}
	// The reload below rebuilds the cache a settings write reloads too.
	l.adminSettingsMu.Lock()
	defer l.adminSettingsMu.Unlock()
	if err := l.db.SettingSet(ctx, settingTranscodeLimits, string(raw), time.Now().UnixNano()); err != nil {
		return TranscodingLimits{}, &Error{Kind: KindInternal, Err: err}
	}
	l.loadRuntimeToggles(ctx)
	l.Audit.Record(ctx, actor, "transcoding.update", AuditTarget{Kind: "settings"},
		map[string]any{"maxConcurrent": lim.MaxConcurrent,
			"maxConcurrentPerUser":  lim.MaxConcurrentPerUser,
			"defaultMaxBitrateKbps": lim.DefaultMaxBitrateKbps})
	return lim, nil
}

// libraryAuditTarget names a library action's target by pid and by the
// name the library goes by, which the entry keeps once the library is
// gone.
func (l *Settings) libraryAuditTarget(ctx context.Context, apiLibraryPID string, pid model.PID) AuditTarget {
	return AuditTarget{Kind: "library", PID: apiLibraryPID, Name: l.Roots.libraryName(ctx, pid)}
}

// LibraryReadOnlySet flips one library's read-only flag, which the
// catalog keeps and enforces file by file.
func (l *Settings) LibraryReadOnlySet(ctx context.Context, actor *UserCtx, apiLibraryPID string, readOnly bool) error {
	prefix, pid, ok := parseAPIPID(apiLibraryPID)
	if !ok || prefix != PrefixLibrary {
		return errInvalid("bad library pid " + apiLibraryPID)
	}
	if _, err := l.lib.SetLibraryReadOnly(ctx, pid, readOnly); err != nil {
		if KindOf(err) == KindNotFound {
			return errNotFound("no library with pid " + apiLibraryPID)
		}
		return classify(err)
	}
	l.Roots.refreshLibraryState(ctx)
	l.Audit.Record(ctx, actor, "library.read-only", l.libraryAuditTarget(ctx, apiLibraryPID, pid),
		map[string]any{"readOnly": readOnly})
	return nil
}

// LibraryFolderFallbackSet lets a scan name a library's untagged files
// from their folders, or stops it. Only an in-place library takes it.
func (l *Settings) LibraryFolderFallbackSet(ctx context.Context, actor *UserCtx, apiLibraryPID string, on bool) error {
	prefix, pid, ok := parseAPIPID(apiLibraryPID)
	if !ok || prefix != PrefixLibrary {
		return errInvalid("bad library pid " + apiLibraryPID)
	}
	if on {
		lib, err := l.Roots.libraryByPID(ctx, pid)
		if err != nil {
			if KindOf(err) == KindNotFound {
				return errNotFound("no library with pid " + apiLibraryPID)
			}
			return err
		}
		var why string
		switch lib.Mode {
		case model.ModeManaged:
			why = "a managed library names its folders itself"
		case model.ModePodcast:
			why = "a podcast library's names come from its feeds"
		}
		if why != "" {
			return errInvalid("only a library that keeps its files in place takes a folder fallback; " + why)
		}
	}
	if _, err := l.lib.SetLibraryFolderFallback(ctx, pid, on); err != nil {
		if KindOf(err) == KindNotFound {
			return errNotFound("no library with pid " + apiLibraryPID)
		}
		return classify(err)
	}
	l.Roots.refreshLibraryState(ctx)
	l.Audit.Record(ctx, actor, "library.folder-fallback", l.libraryAuditTarget(ctx, apiLibraryPID, pid),
		map[string]any{"folderFallback": on})
	return nil
}

// errReadOnly is the refusal for writes into a read-only library.
func errReadOnly(what string) error {
	return &Error{Kind: KindReadOnly, Msg: what + " is read-only on this server"}
}

// errServerReadOnly is the refusal while the server-wide switch is on.
func errServerReadOnly() error {
	return &Error{Kind: KindReadOnly, Msg: "the server is in read-only mode"}
}

// ServerReadOnly reports the server-wide read-only switch, the flag the
// session carries to every signed-in client.
func (l *Settings) ServerReadOnly() bool { return l.currentToggles().readOnly }

// CheckWritable refuses when the whole server, or the named library, is
// read-only. An empty library pid checks only the global flag (staging
// surfaces that have no target library yet).
func (l *Settings) CheckWritable(ctx context.Context, bareLibraryPID string) error {
	if l.ServerReadOnly() {
		return errServerReadOnly()
	}
	if bareLibraryPID != "" && l.Roots.libraryReadOnly(bareLibraryPID) {
		return errReadOnly("this library")
	}
	return nil
}

// checkPathWritable is CheckWritable keyed by a file path, for
// surfaces that know the file before the library.
func (l *Settings) checkPathWritable(ctx context.Context, path string) error {
	if err := l.CheckWritable(ctx, ""); err != nil {
		return err
	}
	pid, err := l.Grants.libraryForPath(ctx, path)
	if err != nil {
		return err
	}
	if pid == "" {
		return nil
	}
	return l.CheckWritable(ctx, pid)
}

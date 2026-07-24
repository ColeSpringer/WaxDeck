package service

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
)

// Migration assistant: pull a household's accumulated play state out of
// the server they are leaving (Navidrome or any Subsonic server for
// music, Audiobookshelf for books) and replay it into WaxDeck. Each
// import runs as a tool task on the drain worker; source items match
// local ones through the catalog's resolve ladder, and every write goes
// through the same service paths the API uses, so visibility rules and
// play-state stamps apply unchanged. History synthesizes listen
// sessions under deterministic idempotency ids, which makes a re-import
// a no-op rather than a double count.

const (
	migrateSourceNavidrome      = "navidrome"
	migrateSourceSubsonic       = "subsonic"
	migrateSourceAudiobookshelf = "audiobookshelf"

	// taskTypeMigratePrefix + source is the tool task type; the drain
	// worker's dispatch routes every "import-*" type here.
	taskTypeMigratePrefix = "import-"

	// migrateListenCap bounds the history synthesized for one item: a
	// five-digit play counter is a counter, not five thousand sessions
	// worth storing. Capped items are counted in the summary.
	migrateListenCap = 500
	// migrateUnmatchedSamples caps the unmatched examples the summary
	// carries; the counts stay exact.
	migrateUnmatchedSamples = 20
	// migrateClientName identifies this importer to the source server
	// and on the synthesized listens.
	migrateClientName = "waxdeck-migrate"
	// migrateHistoryStep spaces synthesized sessions: the newest lands
	// at the source's last-played time and each earlier one steps back
	// this far, so charts spread the history instead of stacking it.
	migrateHistoryStep = 7 * 24 * time.Hour
)

// MigrationRequest is one import order as the handler passes it down;
// the toggle booleans are explicit here (the handler applies the
// default-true semantics).
type MigrationRequest struct {
	Source    string
	ServerURL string
	Username  string
	Password  string
	Token     string
	Stars     bool
	Ratings   bool
	History   bool
	Progress  bool
	DryRun    bool
}

// migrationParams is the persisted work order riding the tool task's
// params column. The credential never lands in plaintext: it is sealed
// with the same key that protects app passwords and stored base64.
type migrationParams struct {
	Source       string `json:"source"`
	ServerURL    string `json:"serverUrl"`
	Username     string `json:"username,omitempty"`
	SecretSealed string `json:"secretSealed"`
	Stars        bool   `json:"stars"`
	Ratings      bool   `json:"ratings"`
	History      bool   `json:"history"`
	Progress     bool   `json:"progress"`
	DryRun       bool   `json:"dryRun"`
}

// migrationSummary is the finished task's report, stored as the task's
// summary document. A dry run counts what would be written; a re-import
// counts only what was new (duplicates are the idempotency working).
type migrationSummary struct {
	Source        string `json:"source"`
	DryRun        bool   `json:"dryRun"`
	Matched       int    `json:"matched"`
	Unmatched     int    `json:"unmatched"`
	Stars         int    `json:"stars"`
	AlbumStars    int    `json:"albumStars,omitempty"`
	ArtistStars   int    `json:"artistStars,omitempty"`
	Ratings       int    `json:"ratings"`
	Listens       int    `json:"listens"`
	Progress      int    `json:"progress"`
	ListensCapped int    `json:"listensCapped,omitempty"`
	// UnmatchedEntities counts starred albums and artists that reached
	// no local entity, kept apart from the per-song Unmatched count: a
	// report that conflated them would read as missing tracks.
	UnmatchedEntities int              `json:"unmatchedEntities,omitempty"`
	Samples           migrationSamples `json:"samples"`
}

// migrationSamples carries a bounded set of examples for the report.
type migrationSamples struct {
	Unmatched []string `json:"unmatched"`
	// UnmatchedEntities samples starred albums and artists that missed,
	// which are a different failure from a song that missed: the group
	// may be absent, or present under a spelling the ladder did not
	// reach through any of its members.
	UnmatchedEntities []string `json:"unmatchedEntities,omitempty"`
}

// noteUnmatched counts a miss and keeps a bounded sample of it.
func (s *migrationSummary) noteUnmatched(artist, title string) {
	s.Unmatched++
	if len(s.Samples.Unmatched) >= migrateUnmatchedSamples {
		return
	}
	label := title
	if artist != "" {
		label = artist + " - " + title
	}
	s.Samples.Unmatched = append(s.Samples.Unmatched, label)
}

// noteUnmatchedEntity is noteUnmatched's entity twin: a starred album or
// artist no member song could resolve.
func (s *migrationSummary) noteUnmatchedEntity(label string) {
	s.UnmatchedEntities++
	if len(s.Samples.UnmatchedEntities) >= migrateUnmatchedSamples {
		return
	}
	s.Samples.UnmatchedEntities = append(s.Samples.UnmatchedEntities, label)
}

// StartMigration queues an import from another server. Administrators
// only: the credential reaches out to an arbitrary host and the writes
// land on the caller's own account.
func (l *Library) StartMigration(ctx context.Context, uc *UserCtx, req MigrationRequest) (ToolTaskDTO, error) {
	if !uc.Admin {
		return ToolTaskDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	source := strings.ToLower(strings.TrimSpace(req.Source))
	switch source {
	case migrateSourceNavidrome, migrateSourceSubsonic, migrateSourceAudiobookshelf:
	default:
		return ToolTaskDTO{}, errInvalid("source must be one of navidrome, subsonic, audiobookshelf")
	}
	parsed, err := url.Parse(strings.TrimSpace(req.ServerURL))
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return ToolTaskDTO{}, errInvalid("serverUrl must be an http or https URL")
	}
	// The same private-address posture every user-pointed fetch takes;
	// the private-feed-hosts flag opts LAN servers back in, which is
	// exactly where a household's old server usually lives.
	if err := l.guardAcquireHost(ctx, parsed.Hostname()); err != nil {
		return ToolTaskDTO{}, err
	}
	secret := ""
	switch source {
	case migrateSourceAudiobookshelf:
		if strings.TrimSpace(req.Token) == "" {
			return ToolTaskDTO{}, errInvalid("audiobookshelf needs an API token")
		}
		secret = req.Token
	default:
		if strings.TrimSpace(req.Username) == "" || req.Password == "" {
			return ToolTaskDTO{}, errInvalid(source + " needs a username and password")
		}
		secret = req.Password
	}
	if l.sealer == nil {
		return ToolTaskDTO{}, &Error{Kind: KindInternal, Msg: "no sealing key is configured"}
	}
	sealed, err := l.sealer.Seal([]byte(secret))
	if err != nil {
		return ToolTaskDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	p := migrationParams{
		Source:       source,
		ServerURL:    strings.TrimRight(parsed.String(), "/"),
		Username:     strings.TrimSpace(req.Username),
		SecretSealed: base64.StdEncoding.EncodeToString(sealed),
		Stars:        req.Stars,
		Ratings:      req.Ratings,
		History:      req.History,
		Progress:     req.Progress,
		DryRun:       req.DryRun,
	}
	t := wdb.ToolTask{
		ID:          "tk-" + ulid.Make().String(),
		Type:        taskTypeMigratePrefix + source,
		State:       taskStateQueued,
		UserID:      uc.ID,
		Params:      marshalJSON(p),
		ResultPIDs:  "[]",
		CreatedAtNS: time.Now().UnixNano(),
	}
	if err := l.db.InsertToolTask(ctx, t); err != nil {
		return ToolTaskDTO{}, &Error{Kind: KindInternal, Err: err}
	}
	l.notifyToolTask(ctx, t.ID)
	return toolTaskDTO(t), nil
}

// runMigrationTask executes one leased migration task. It is the
// dispatch target for every "import-*" task type: runToolTask routes
// them here and its shared completion tail records the done state, so
// on success this only fills in t.Summary. Failures return through the
// drain machinery like every other runner: permanent ones retire the
// task, transport trouble re-runs under the lease and idempotent
// history makes the re-run safe.
func (l *Library) runMigrationTask(ctx context.Context, t *wdb.ToolTask) error {
	var p migrationParams
	if err := json.Unmarshal([]byte(t.Params), &p); err != nil {
		return fmt.Errorf("%w: bad task params: %v", errToolPermanent, err)
	}
	user, err := l.db.UserByID(ctx, t.UserID)
	if err != nil {
		return fmt.Errorf("%w: the importing account is gone", errToolPermanent)
	}
	if user.Disabled || !hasRole(user.Roles, "admin") {
		return fmt.Errorf("%w: administrator rights were revoked", errToolPermanent)
	}
	uc, err := l.UserCtx(ctx, user)
	if err != nil {
		return err
	}
	secret, err := l.openMigrationSecret(p.SecretSealed)
	if err != nil {
		return fmt.Errorf("%w: %v", errToolPermanent, err)
	}
	var sum migrationSummary
	switch p.Source {
	case migrateSourceNavidrome, migrateSourceSubsonic:
		sum, err = l.runSubsonicImport(ctx, t, uc, p, secret)
	case migrateSourceAudiobookshelf:
		sum, err = l.runABSImport(ctx, t, uc, p, secret)
	default:
		return fmt.Errorf("%w: unknown migration source %q", errToolPermanent, p.Source)
	}
	if err != nil {
		return err
	}
	t.Summary = marshalJSON(sum)
	l.Audit(ctx, uc, "migration.run", AuditTarget{Kind: "migration", Name: p.Source}, map[string]any{
		"source": p.Source, "dryRun": p.DryRun,
		"matched": sum.Matched, "unmatched": sum.Unmatched,
		"stars": sum.Stars, "ratings": sum.Ratings,
		"listens": sum.Listens, "progress": sum.Progress,
	})
	return nil
}

// openMigrationSecret recovers the credential sealed at creation.
func (l *Library) openMigrationSecret(sealedB64 string) (string, error) {
	if l.sealer == nil {
		return "", errors.New("no sealing key is configured")
	}
	raw, err := base64.StdEncoding.DecodeString(sealedB64)
	if err != nil {
		return "", fmt.Errorf("bad sealed credential: %v", err)
	}
	pt, err := l.sealer.Open(raw)
	if err != nil {
		return "", fmt.Errorf("the sealed credential does not open: %v", err)
	}
	return string(pt), nil
}

// resolveMigrationRef walks the catalog's resolve ladder for one source
// item. Any rung is accepted; only a clean miss counts unmatched.
func (l *Library) resolveMigrationRef(ctx context.Context, ref model.PortableRef) (*model.ItemView, model.MatchRung, error) {
	return l.lib.ResolveRef(ctx, ref)
}

// migrateSessionID is the deterministic idempotency key for one
// synthesized listen: listen_sessions is unique per (user, session), so
// re-importing the same source can only ever no-op. An overlong source
// id folds through a hash to fit the 64-character session contract
// while staying deterministic.
func migrateSessionID(source, sourceID string, n int) string {
	id := fmt.Sprintf("import:%s:%s:%d", source, sourceID, n)
	if len(id) <= 64 {
		return id
	}
	sum := sha256.Sum256([]byte(sourceID))
	return fmt.Sprintf("import:%s:%x:%d", source, sum[:12], n)
}

// migrateListens synthesizes count finished sessions for one matched
// item and ingests them through the same path clients report listens
// on, so played marks and play counts derive exactly as live listens
// do. The newest session lands at lastPlayed (a recent hour ago when
// the source gave none) and earlier ones step back a week each. The
// returned count is new rows only: a re-import's duplicates are the
// idempotency at work.
func (l *Library) migrateListens(ctx context.Context, uc *UserCtx, source, sourceID, apiItemPID string, durationMS int64, count int, lastPlayed time.Time) (int, error) {
	if lastPlayed.IsZero() {
		lastPlayed = time.Now().Add(-time.Hour)
	}
	accepted := 0
	const batch = 100
	sessions := make([]ListenSession, 0, batch)
	flush := func() error {
		if len(sessions) == 0 {
			return nil
		}
		res, err := l.IngestListens(ctx, uc, sessions)
		accepted += res.Accepted
		sessions = sessions[:0]
		return err
	}
	for n := 0; n < count; n++ {
		sessions = append(sessions, ListenSession{
			SessionID: migrateSessionID(source, sourceID, n),
			PID:       apiItemPID,
			StartedAt: lastPlayed.Add(-time.Duration(count-1-n) * migrateHistoryStep),
			MsPlayed:  durationMS,
			Finished:  true,
			Client:    migrateClientName,
			Source:    "import",
		})
		if len(sessions) == batch {
			if err := flush(); err != nil {
				return accepted, err
			}
		}
	}
	if err := flush(); err != nil {
		return accepted, err
	}
	return accepted, nil
}

// migrateWriteSkippable reports whether a per-item write failure should
// skip the item rather than fail the run: the matched item vanished
// mid-import or refused the value. Anything else fails the task.
func migrateWriteSkippable(err error) bool {
	switch KindOf(err) {
	case KindNotFound, KindInvalid:
		return true
	}
	return false
}

// migrateHTTPError is a non-2xx answer from the source server.
type migrateHTTPError struct {
	Status int
	URL    string
}

func (e *migrateHTTPError) Error() string {
	return fmt.Sprintf("the source server answered %d for %s", e.Status, e.URL)
}

// migrateClientErr classifies a source-client failure for the task
// machinery: a coherent API refusal or a 4xx is permanent, transport
// trouble stays transient so the lease machinery retries (which the
// deterministic history ids make safe).
func migrateClientErr(err error) error {
	if err == nil {
		return nil
	}
	var api *subsonicAPIError
	if errors.As(err, &api) {
		return fmt.Errorf("%w: %v", errToolPermanent, err)
	}
	var hs *migrateHTTPError
	if errors.As(err, &hs) && hs.Status >= 400 && hs.Status < 500 {
		return fmt.Errorf("%w: %v", errToolPermanent, err)
	}
	return err
}

// migrateHTTPClient is the client both importers dial the source with:
// bounded, context-threaded, and redirect-free (a redirect could walk
// past the start-time SSRF check into a private range).
func migrateHTTPClient() *http.Client {
	return &http.Client{
		Timeout: time.Minute,
		CheckRedirect: func(*http.Request, []*http.Request) error {
			return errors.New("the source server redirected; redirects are not followed")
		},
	}
}

// migrateProgress mirrors task progress to the store in coarse steps
// and keeps the lease alive across a long walk of the source server.
type migrateProgress struct {
	l         *Library
	t         *wdb.ToolTask
	lastPct   float64
	lastRenew time.Time
}

func newMigrateProgress(l *Library, t *wdb.ToolTask) *migrateProgress {
	return &migrateProgress{l: l, t: t, lastRenew: time.Now()}
}

func (mp *migrateProgress) report(ctx context.Context, pct float64) {
	if pct-mp.lastPct >= 5 {
		mp.lastPct = pct
		mp.t.ProgressPct = pct
		if err := mp.l.db.UpdateToolTask(ctx, *mp.t); err != nil {
			mp.l.log.Warn("recording migration progress", "task", mp.t.ID, "err", err)
		} else {
			mp.l.notifyToolTask(ctx, mp.t.ID)
		}
	}
	if time.Since(mp.lastRenew) >= toolLeaseRenew {
		mp.lastRenew = time.Now()
		until := time.Now().Add(toolTaskLease).UnixNano()
		if err := mp.l.db.RenewToolTaskLease(ctx, mp.t.ID, until); err != nil {
			mp.l.log.Warn("renewing migration lease", "task", mp.t.ID, "err", err)
		}
	}
}

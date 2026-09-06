package service

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"sort"
	"strings"
	"time"

	"github.com/oklog/ulid/v2"

	"github.com/colespringer/waxbin/model"

	wdb "github.com/colespringer/waxdeck/server/internal/db"
	"github.com/colespringer/waxdeck/server/internal/scrobble"
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
	migrateSourceJellyfin       = "jellyfin"
	migrateSourceLastfm         = "lastfm"
	migrateSourceListenBrainz   = "listenbrainz"
	migrateSourceSpotify        = "spotify"

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
	// AccountID is the account the imported state lands on; empty means
	// the caller's own.
	AccountID string
	// ExportID names a staged account export, for a source that reads a
	// file rather than a server.
	ExportID string
	Stars    bool
	Ratings  bool
	History  bool
	Progress bool
	DryRun   bool
}

// migrationParams is the persisted work order riding the tool task's
// params column. The credential never lands in plaintext: it is sealed
// with the same key that protects app passwords and stored base64.
type migrationParams struct {
	Source    string `json:"source"`
	ServerURL string `json:"serverUrl"`
	Username  string `json:"username,omitempty"`
	// AccountID is the account the writes land on, which is not always
	// the account that ordered them: an administrator moves the rest of
	// the household without knowing their passwords.
	AccountID    string `json:"accountId,omitempty"`
	ExportID     string `json:"exportId,omitempty"`
	SecretSealed string `json:"secretSealed,omitempty"`
	// TokenAuth says the sealed secret is an API token rather than a
	// password, for the one source that takes either: nothing at run
	// time can tell a Jellyfin key from a Jellyfin password.
	TokenAuth bool `json:"tokenAuth,omitempty"`
	Stars     bool `json:"stars"`
	Ratings   bool `json:"ratings"`
	History   bool `json:"history"`
	Progress  bool `json:"progress"`
	DryRun    bool `json:"dryRun"`
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
	// HistoryTruncated marks a real-timestamp source whose history ran
	// past the page cap: what landed is the most recent of it, and the
	// report has to say so rather than reading as the whole thing.
	HistoryTruncated bool `json:"historyTruncated,omitempty"`
	// Files counts the files inside an uploaded export this run read.
	Files int `json:"files,omitempty"`
	// ExportConsumed says this run read the whole of the uploaded
	// export, which is what decides whether the upload is deleted once
	// the task settles. A dry run reads it all and keeps it - running
	// the real import afterwards is the point of one - and a run with a
	// switch turned off leaves part of it unread and keeps it too.
	ExportConsumed bool `json:"exportConsumed,omitempty"`
	// Refused counts plays the ingest would not record: the target
	// account is not allowed the item - a library it is not on, or a
	// content rule that hides it - or the session the source described
	// was not one a listen can be. Kept apart from Unmatched, which is
	// the catalog not holding the recording at all: an administrator
	// importing onto a restricted member would otherwise read thousands
	// matched, nothing written, and nothing saying why.
	Refused int `json:"refused,omitempty"`
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

// noteRefusedListens counts the sessions an ingest permanently refused.
// Mostly the target account not being allowed the item - the importer
// resolved it against the catalog and the ingest resolves it again
// against that account - and sometimes a play the source described in a
// way no listen can be recorded from, a timestamp years ahead of the
// server being the one that actually happens.
func (s *migrationSummary) noteRefusedListens(rejected []RejectedListen) {
	s.Refused += len(rejected)
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

// migrateSourceSpec says what one source needs. A source is not a
// switch arm any more because the sources stopped agreeing: some pull
// from a server, one reads a file already uploaded, and two need only
// an account name on a public service.
type migrateSourceSpec struct {
	// urlRequired means the request must carry a serverUrl. A source
	// that does not require one still takes one when it has a default
	// to replace (a compatible host in place of the public instance),
	// which is what takesURL derives rather than a second flag: the two
	// spelled separately let a row require a URL and refuse every one
	// that arrived.
	urlRequired bool
	defaultURL  string
	// needsUser means a username identifies whose state to read.
	needsUser bool
	// needsPassword and needsToken say which secret the source takes;
	// with both set either one will do. tokenOptional marks a source
	// that serves public history and only widens what it answers with a
	// token.
	needsPassword bool
	needsToken    bool
	tokenOptional bool
	// needsExport means the source reads a staged account export.
	needsExport bool
}

// takesURL reports whether a serverUrl may be given at all.
func (sp migrateSourceSpec) takesURL() bool {
	return sp.urlRequired || sp.defaultURL != ""
}

var migrateSources = map[string]migrateSourceSpec{
	migrateSourceNavidrome:      {urlRequired: true, needsUser: true, needsPassword: true},
	migrateSourceSubsonic:       {urlRequired: true, needsUser: true, needsPassword: true},
	migrateSourceAudiobookshelf: {urlRequired: true, needsToken: true},
	// Either a login or an API key, and with an API key the username is
	// still needed: a key is the server's, not a person's, so nothing
	// says whose play state to read.
	migrateSourceJellyfin: {urlRequired: true, needsUser: true, needsPassword: true, needsToken: true},
	migrateSourceLastfm:   {needsUser: true},
	migrateSourceListenBrainz: {
		defaultURL: scrobble.DefaultListenBrainzAPI,
		needsUser:  true, needsToken: true, tokenOptional: true,
	},
	migrateSourceSpotify: {needsExport: true},
}

// migrateSourceNames lists the sources for a refusal, in a stable
// order so the sentence does not shuffle between requests.
func migrateSourceNames() string {
	names := make([]string, 0, len(migrateSources))
	for name := range migrateSources {
		names = append(names, name)
	}
	sort.Strings(names)
	return strings.Join(names, ", ")
}

// StartMigration queues an import from another server. Administrators
// only: the credential reaches out to an arbitrary host and the writes
// land on an account the caller names.
func (l *Library) StartMigration(ctx context.Context, uc *UserCtx, req MigrationRequest) (ToolTaskDTO, error) {
	if !uc.Admin {
		return ToolTaskDTO{}, &Error{Kind: KindForbidden, Msg: "administrators only"}
	}
	source := strings.ToLower(strings.TrimSpace(req.Source))
	spec, known := migrateSources[source]
	if !known {
		return ToolTaskDTO{}, errInvalid("source must be one of " + migrateSourceNames())
	}
	// Last.fm is read with this server's own API credentials, so an
	// install that has none cannot import at all - said here, where
	// somebody is looking at the form, rather than in a task report.
	if source == migrateSourceLastfm && l.lastfmClient() == nil {
		return ToolTaskDTO{}, errInvalid("configure the server's Last.fm API key first")
	}
	target, err := l.migrationTarget(ctx, uc, req.AccountID)
	if err != nil {
		return ToolTaskDTO{}, err
	}
	base, err := l.migrationBase(ctx, source, spec, req.ServerURL)
	if err != nil {
		return ToolTaskDTO{}, err
	}
	if spec.needsUser && strings.TrimSpace(req.Username) == "" {
		return ToolTaskDTO{}, errInvalid(source + " needs a username")
	}
	secret := ""
	tokenAuth := false
	switch {
	case spec.needsPassword && spec.needsToken:
		secret = firstNonEmpty(req.Password, strings.TrimSpace(req.Token))
		if secret == "" {
			return ToolTaskDTO{}, errInvalid(source + " needs a password or an API token")
		}
		tokenAuth = req.Password == ""
	case spec.needsPassword:
		if req.Password == "" {
			return ToolTaskDTO{}, errInvalid(source + " needs a password")
		}
		secret = req.Password
	case spec.needsToken:
		secret = strings.TrimSpace(req.Token)
		if secret == "" && !spec.tokenOptional {
			return ToolTaskDTO{}, errInvalid(source + " needs an API token")
		}
		tokenAuth = true
	}
	exportID := strings.TrimSpace(req.ExportID)
	if spec.needsExport {
		if exportID == "" {
			return ToolTaskDTO{}, errInvalid(source + " needs an uploaded export")
		}
		// Resolved here, not at run time: the caller has to be the
		// administrator who uploaded it, it has to still be live, and it
		// has to be an export of the service this order names.
		row, exportErr := l.ownedMigrationExport(ctx, uc, exportID)
		if exportErr != nil {
			if KindOf(exportErr) != KindNotFound {
				// A read that failed rather than an upload that is not
				// there. Flattening it into a bad request would answer
				// 400 with the driver's own sentence in the message and
				// leave nothing for anyone to be paged about.
				return ToolTaskDTO{}, exportErr
			}
			// The export is a field of the order, and this endpoint's own
			// resource is the task, so a missing one is an invalid field
			// rather than a missing resource.
			return ToolTaskDTO{}, errInvalid(exportErr.Error())
		}
		if row.Source != source {
			return ToolTaskDTO{}, errInvalid("that upload is a " + row.Source + " export")
		}
	} else if exportID != "" {
		return ToolTaskDTO{}, errInvalid(source + " reads a server, not an uploaded export")
	}
	sealedB64 := ""
	if secret != "" {
		if l.sealer == nil {
			return ToolTaskDTO{}, &Error{Kind: KindInternal, Msg: "no sealing key is configured"}
		}
		sealed, err := l.sealer.Seal([]byte(secret))
		if err != nil {
			return ToolTaskDTO{}, &Error{Kind: KindInternal, Err: err}
		}
		sealedB64 = base64.StdEncoding.EncodeToString(sealed)
	}
	p := migrationParams{
		Source:       source,
		ServerURL:    base,
		Username:     strings.TrimSpace(req.Username),
		AccountID:    target,
		ExportID:     exportID,
		SecretSealed: sealedB64,
		TokenAuth:    tokenAuth,
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

// migrationTarget resolves the account the writes land on. Empty means
// the caller, which is the household administrator moving their own
// library; anything else has to be an account that can actually hold
// play state, so a disabled one and a signup nobody approved are
// refused here rather than at run time.
func (l *Library) migrationTarget(ctx context.Context, uc *UserCtx, accountID string) (string, error) {
	id := strings.TrimSpace(accountID)
	if id == "" || id == uc.ID {
		return uc.ID, nil
	}
	u, err := l.db.UserByID(ctx, id)
	if err != nil || u == nil {
		// Invalid rather than not-found: the account is a field of the
		// order, and this endpoint's own resource is the task.
		return "", errInvalid("no account with id " + id)
	}
	if u.Disabled {
		return "", errInvalid("that account is disabled")
	}
	if u.Pending {
		return "", errInvalid("that signup has not been approved yet")
	}
	return u.ID, nil
}

// migrationBase validates the source server URL against what the source
// needs. The guard runs only where there is a URL to guard: a source
// this server reaches on a fixed public host, or none at all, has no
// address the caller could point anywhere.
func (l *Library) migrationBase(ctx context.Context, source string, spec migrateSourceSpec, raw string) (string, error) {
	given := strings.TrimSpace(raw)
	if given == "" {
		if spec.urlRequired {
			return "", errInvalid(source + " needs the source server's URL")
		}
		return spec.defaultURL, nil
	}
	if !spec.takesURL() {
		return "", errInvalid(source + " takes no server URL")
	}
	parsed, err := url.Parse(given)
	if err != nil || (parsed.Scheme != "http" && parsed.Scheme != "https") || parsed.Host == "" {
		return "", errInvalid("serverUrl must be an http or https URL")
	}
	// The same private-address posture every user-pointed fetch takes;
	// the private-feed-hosts flag opts LAN servers back in, which is
	// exactly where a household's old server usually lives.
	if err := l.guardAcquireHost(ctx, parsed.Hostname()); err != nil {
		return "", err
	}
	return strings.TrimRight(parsed.String(), "/"), nil
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
	actor, err := l.db.UserByID(ctx, t.UserID)
	if err != nil || actor == nil {
		return fmt.Errorf("%w: the importing account is gone", errToolPermanent)
	}
	if actor.Disabled || !hasRole(actor.Roles, "admin") {
		return fmt.Errorf("%w: administrator rights were revoked", errToolPermanent)
	}
	// The writes land on the target, which is usually the actor and
	// sometimes another member of the household. Re-read here rather
	// than carried from the start: a task can sit queued, and an account
	// disabled in between must not have state written onto it.
	targetID := p.AccountID
	if targetID == "" {
		targetID = actor.ID
	}
	target := actor
	if targetID != actor.ID {
		target, err = l.db.UserByID(ctx, targetID)
		if err != nil || target == nil {
			return fmt.Errorf("%w: the target account is gone", errToolPermanent)
		}
	}
	if target.Disabled {
		return fmt.Errorf("%w: the target account is disabled", errToolPermanent)
	}
	if target.Pending {
		// The same refusal the start makes, for the same reason it is
		// re-read at all: an approval can be revoked while a task waits.
		return fmt.Errorf("%w: the target signup is not approved", errToolPermanent)
	}
	uc, err := l.UserCtx(ctx, target)
	if err != nil {
		return err
	}
	secret := ""
	if p.SecretSealed != "" {
		secret, err = l.openMigrationSecret(p.SecretSealed)
		if err != nil {
			return fmt.Errorf("%w: %v", errToolPermanent, err)
		}
	}
	// The upload is this run's for as long as it lasts. Two tasks
	// naming one export - a dry run queued beside the real import, or
	// the same order submitted twice - would otherwise both open the
	// archive, and the first to finish would take it away from the
	// other.
	if p.ExportID != "" {
		held, claimErr := l.db.ClaimMigrationExport(ctx, p.ExportID, t.ID)
		if claimErr != nil {
			return claimErr
		}
		if !held {
			// A claim matches no row for either of two reasons, and they
			// are not the same news: the upload is gone - swept at its
			// expiry, or discarded after this was ordered - or a live
			// import of somebody else's is reading it.
			if _, rowErr := l.db.MigrationExportByID(ctx, p.ExportID); errors.Is(rowErr, wdb.ErrNotFound) {
				return fmt.Errorf("%w: the uploaded export is gone", errToolPermanent)
			}
			return fmt.Errorf("%w: another import is reading that upload", errToolPermanent)
		}
	}
	var sum migrationSummary
	switch p.Source {
	case migrateSourceNavidrome, migrateSourceSubsonic:
		sum, err = l.runSubsonicImport(ctx, t, uc, p, secret)
	case migrateSourceAudiobookshelf:
		sum, err = l.runABSImport(ctx, t, uc, p, secret)
	case migrateSourceJellyfin:
		sum, err = l.runJellyfinImport(ctx, t, uc, p, secret)
	case migrateSourceLastfm:
		sum, err = l.runLastfmImport(ctx, t, uc, p)
	case migrateSourceListenBrainz:
		sum, err = l.runListenBrainzImport(ctx, t, uc, p, secret)
	case migrateSourceSpotify:
		sum, err = l.runSpotifyImport(ctx, t, uc, p)
	default:
		return fmt.Errorf("%w: unknown migration source %q", errToolPermanent, p.Source)
	}
	if err != nil {
		return err
	}
	t.Summary = marshalJSON(sum)
	// Audited under the actor, naming the target: the entry answers "who
	// ordered this", and an import onto somebody else's account is
	// exactly the entry that has to say whose.
	actorCtx := uc
	if target.ID != actor.ID {
		// Read rather than fallen back to: this entry is the only record
		// that an administrator wrote onto somebody else's account, and
		// attributing it to the person written to would say the opposite
		// of what happened.
		ac, ctxErr := l.UserCtx(ctx, actor)
		if ctxErr != nil {
			return &Error{Kind: KindInternal, Err: ctxErr}
		}
		actorCtx = ac
	}
	l.Audit(ctx, actorCtx, "migration.run", AuditTarget{Kind: "migration", Name: p.Source}, map[string]any{
		"source": p.Source, "dryRun": p.DryRun,
		"account": target.Username,
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
func (l *Library) migrateListens(ctx context.Context, uc *UserCtx, sum *migrationSummary, source, sourceID, apiItemPID string, durationMS int64, count int, lastPlayed time.Time) (int, error) {
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
		res, err := l.ingestListens(ctx, uc, sessions, listenIngestOptions{announcedByCaller: true})
		accepted += res.Accepted
		sum.noteRefusedListens(res.Rejected)
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
	// One event for the item, rather than one per synthesized session:
	// the ingest leaves the announcement to the importer precisely so a
	// five-digit play counter is not five hundred device wakes.
	if accepted > 0 {
		l.emitUserEvent(ctx, uc.ID, eventPlayState, catalogPIDOf(apiItemPID))
	}
	return accepted, nil
}

// settleMigrationExport disposes of the upload an import was reading,
// once that task's terminal state is on disk.
//
// After the completion write, not as the importer's last act. The
// completion write can fail - it is a warning, not an error - and a
// restart can land between the two, and either used to leave the next
// attempt reading a row that was already gone: a successful import
// reported as permanently failed, with the household's history deleted
// behind it. Settling here means the worst a crash in this window can
// do is leave the upload standing, which the expiry sweep answers in a
// day.
//
// The task is re-read rather than taken from the caller for the same
// reason: what is on disk is what a retry will see, so a completion
// that did not land must not destroy anything.
func (l *Library) settleMigrationExport(ctx context.Context, taskID string) {
	t, err := l.db.ToolTaskByID(ctx, taskID)
	if err != nil || !strings.HasPrefix(t.Type, taskTypeMigratePrefix) {
		return
	}
	var p migrationParams
	if err := json.Unmarshal([]byte(t.Params), &p); err != nil || p.ExportID == "" {
		return
	}
	row, err := l.db.MigrationExportByID(ctx, p.ExportID)
	if err != nil {
		return
	}
	if row.ClaimedBy != t.ID {
		// Somebody else's now: this task's claim went stale and was
		// replaced, so the archive is not ours to settle.
		return
	}
	if t.State != taskStateDone && t.State != taskStateFailed {
		// The completion write did not land, so this task is not over:
		// it will be re-leased and re-run, and its claim is what keeps
		// the archive its own until then.
		return
	}
	var sum migrationSummary
	_ = json.Unmarshal([]byte(t.Summary), &sum)
	if t.State == taskStateDone && sum.ExportConsumed {
		// Read in full and written in full, so the household's
		// listening history stops sitting on the server. A delete that
		// failed is already logged and the row stays; the expiry sweep
		// comes back to it.
		_ = l.dropMigrationExport(ctx, row)
		return
	}
	if err := l.db.ReleaseMigrationExport(ctx, row.ID, t.ID); err != nil {
		l.log.Warn("releasing a staged export", "task", t.ID, "export", row.ID, "err", err)
	}
}

// catalogPIDOf strips the API prefix an event carries the bare pid for.
func catalogPIDOf(apiItemPID string) string {
	_, pid, ok := parseAPIPID(apiItemPID)
	if !ok {
		return apiItemPID
	}
	return string(pid)
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
		// Except the two that mean "not now". A rate limit is the source
		// server asking for a pause, and retiring an import over one
		// throws away a history that was going to land in full.
		if hs.Status == http.StatusTooManyRequests || hs.Status == http.StatusRequestTimeout {
			return err
		}
		return fmt.Errorf("%w: %v", errToolPermanent, err)
	}
	return err
}

// migrateScrobbleErr maps a scrobble client's failure onto the task
// machinery's taxonomy: what that package already calls permanent
// retires the task, and everything else is transport worth retrying.
func migrateScrobbleErr(err error) error {
	if err == nil {
		return nil
	}
	if scrobble.IsPermanent(err) {
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

// migrateArtistEntity names the artist a starred song belongs to. The
// protocol's starred artist is an album artist, and the catalog's own
// album-artist handle does not fall back to the track artist, so this
// mirrors the fallback the rest of the surface applies. Shared because
// every importer that stars an artist has to answer it the same way.
func migrateArtistEntity(it *model.ItemView) model.PID {
	if it.AlbumArtistPID != "" {
		return it.AlbumArtistPID
	}
	return it.ArtistPID
}

// migrateSource is the half of a source-server client that every source
// shares: the transport, the base address, and the read that turns one
// request into a decoded answer. Shared rather than copied because the
// parts that matter are not the interesting ones - the read bound is a
// denial-of-service control against a source server answering with
// something enormous, and the error shape is what the retry taxonomy
// keys on, so three spellings of them means three places to miss.
//
// What each source keeps for itself is what authorizes it: a bearer
// token, a scheme header, a query parameter. That rides in on the
// header the caller hands over.
type migrateSource struct {
	// name is what this source calls itself in a parse failure, which is
	// the one message that reaches an administrator as prose.
	name string
	base string
	hc   *http.Client
}

// migrateSourceReadMax bounds one answer from a source server. Large
// enough for a page of a very big library, small enough that a source
// answering with a stream of nonsense cannot be read into memory
// forever.
const migrateSourceReadMax = 64 << 20

// fetch performs one request and decodes the answer into out, which may
// be nil for a call whose body says nothing.
func (c migrateSource) fetch(ctx context.Context, method, path string, body []byte, header http.Header, out any) error {
	var rdr io.Reader
	if body != nil {
		rdr = bytes.NewReader(body)
	}
	req, err := http.NewRequestWithContext(ctx, method, c.base+path, rdr)
	if err != nil {
		return err
	}
	for k, vs := range header {
		for _, v := range vs {
			req.Header.Add(k, v)
		}
	}
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.hc.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		return &migrateHTTPError{Status: resp.StatusCode, URL: c.base + path}
	}
	// Cap plus one, so an answer at the bound is refused rather than
	// truncated: a short read reaches the decoder as malformed JSON and
	// the import retires itself blaming the shape of an answer that was
	// fine.
	raw, err := io.ReadAll(io.LimitReader(resp.Body, migrateSourceReadMax+1))
	if err != nil {
		return err
	}
	if int64(len(raw)) > migrateSourceReadMax {
		return fmt.Errorf("%s %s: the answer is larger than this import reads", c.name, path)
	}
	if out == nil {
		return nil
	}
	if err := json.Unmarshal(raw, out); err != nil {
		return fmt.Errorf("%s %s: unparseable answer: %w", c.name, path, err)
	}
	return nil
}

// get is fetch's read-only shape, which is all most calls need.
func (c migrateSource) get(ctx context.Context, path string, header http.Header, out any) error {
	return c.fetch(ctx, http.MethodGet, path, nil, header, out)
}

// newMigrateSource builds one against a base address, trimming the
// trailing slash so a path always joins cleanly.
func newMigrateSource(name, base string) migrateSource {
	return migrateSource{name: name, base: strings.TrimRight(base, "/"), hc: migrateHTTPClient()}
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

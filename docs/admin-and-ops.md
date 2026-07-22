# Admin and ops

Running WaxDeck for a household means letting people in, keeping the
server healthy, and being able to undo mistakes. This page covers the
administration surface: accounts and permissions, signup requests and
invites, the audit log, backups and restore, scheduled jobs, the
trash, read-only mode, transcoding limits, Prometheus metrics, and
moving in from another server.

## Accounts, roles, and permissions

Accounts are managed under the library's curation menu (Users) or over
the API. Every account has a role (`admin` or `user`), library
visibility (every library, or an explicit set), and a set of
permission toggles:

- **Download** — fetch original files for offline use.
- **Delete** — delete visible library items to the trash. Permanent
  deletion is always admin-only.
- **Explicit content** — see and play content flagged explicit.
  Podcasts carry the feed's own flag; turning this off hides flagged
  shows and episodes. Music mostly has no canonical explicit flag, so
  the honest music-side control is a tag rule (below).
- **Shared outputs** — control shared device endpoints (cast targets,
  DLNA renderers, the jukebox). A user's own devices are always
  theirs to control.
- **Manage podcasts** — subscribe, unsubscribe, and trigger episode
  fetches. Off leaves existing subscriptions playable but frozen.
- **Tag allow / deny lists** — visibility rules over custom tags.
  A deny rule hides items matching it; an allow list, when set, shows
  only items matching every rule. An item without the rule's tag
  passes a deny rule, which is exactly how a deny list should read.
  Together with the explicit toggle this is the parental-controls
  mechanism: a kids account with an allow list on `KIDS=yes` sees
  nothing else.
- **Max transcode bitrate** — a per-account ceiling on transcoded
  streams, overriding the server default.

Administrators hold every permission implicitly. Changing a user's
content rules retires their sync cursors, so offline clients re-mirror
under the new rules instead of keeping stale content.

## Signup requests and invites

Out of the box, accounts are admin-created. Two self-serve doors can
be opened:

- **Open signup** (Settings → Server): registrations land as pending
  requests. A pending account cannot log in until an administrator
  approves it — approval assigns the role, library access, and
  permissions in the same step. Rejection deletes the request and
  frees the username. New requests raise a `signup-requested`
  notification.
- **Invites** (Users → Invites): an invite link token pre-approves
  signup with a chosen shape. The token is shown exactly once at
  creation; invites can be single- or multi-use, can expire, and can
  be revoked. Invites work whether or not open signup is enabled.

## The audit log

Every administrative and destructive action is recorded: who did it,
to what, and the detail of the change — account edits, permission
changes, playlist deletions, entity merges, item deletions, trash
operations, backups and restores, settings changes, migration runs.
Names are captured at write time, so "who deleted this playlist" has
an answer even after the playlist, or the actor, is gone. The log is
admin-only, filterable by action prefix (`playlist.` matches every
playlist action), actor, and target.

## Backups and restore

A backup is one zip archive holding both databases (the catalog via
its own backup facility, the server database as a consistent
snapshot). Media files are never included. The encryption keyfile is
excluded by design: an archive holding both the database and the key
would be plaintext-equivalent for stored credentials, so keep the
keyfile safe separately.

Back up on demand (Backups → Back up now) or on a schedule. Retention
keeps the newest N archives and a total byte budget, both editable in
settings; imported archives are exempt. Archives can be downloaded
from the UI and uploaded to another server.

**Restore is staged, then applied at the next server start.** Staging
validates the archive and answers with the plan: whether this server's
key opens the archive's sealed credentials, and exactly which
credentials break when it does not (they are marked pending re-auth
instead of surfacing as scattered errors). At the next start the
current databases are set aside — not deleted — the archive's
databases move into place, and every client's sync cursor resets
cleanly. A staged restore can be cancelled any time before the
restart.

Restoring onto a new host: upload the archive (Backups → import), stage
it, restart. Without the old keyfile everything restores except sealed
credentials (app passwords, scrobbling connections, private feed
logins), which need re-entering.

## Scheduled jobs

Three schedules, each a five-field cron expression in server-local
time: **scan** (a full library scan), **backup**, and **prune** (event
log, replay-guard stamps, audit history, ended playback sessions).
Prune ships enabled at 03:30 nightly; scan and backup ship disabled
until configured. Each schedule shows its last run, last error, and
next firing time.

## The trash

Deletions go to the catalog's reversible trash — a same-volume
`.waxbin-trash` directory the scanner skips. The admin trash surface
lists every trashed file with where it lived, restores files back into
the catalog (re-scanned and un-archived), and empties the trash
permanently, reporting the space reclaimed. Deleting items from the
item page previews what will be deleted (files, bytes) before anything
moves.

## Read-only mode

For media mounted read-only on principle: per library, or server-wide
(Settings → Server). A read-only library refuses uploads, organizing,
file write-back, deletion, and the file tools with the `read-only`
error code, while playback, browsing, and per-user state (stars,
progress, playlists) keep working. Podcast libraries need a writable
root for episode fetching; the flag refuses fetches too.

## Transcoding limits

Transcode sessions are limited at the media proxy, where the server
knows the user: a server-wide concurrent cap, a per-account cap
(administrators exempt), and a default bitrate ceiling for accounts
without their own. Direct-played originals never count. An over-limit
stream answers `transcode-limited` (HTTP 429); the streaming engine's
own admission control remains the hard backstop.

## Prometheus metrics

Set `WAXDECK_METRICS_TOKEN` to enable `GET /metrics` (Prometheus text
format), authenticated by that bearer token; without the token the
endpoint stays disabled. Metrics cover Go runtime health, accounts and
sessions, pending signup requests, listen sessions, active background
tasks, outbox depths, and in-flight transcode sessions.

```yaml
scrape_configs:
  - job_name: waxdeck
    authorization: { credentials: <token> }
    static_configs: [{ targets: ["waxdeck:4420"] }]
```

## Moving in from another server

The migration assistant (curation menu → Import from another server)
pulls listening state from a running server and matches it onto your
library through the same identifier-first resolve ladder the rest of
WaxDeck uses (MusicBrainz IDs, then fingerprints, then descriptive
metadata):

- **Navidrome / any Subsonic server** — starred songs, ratings, play
  counts, and bookmark positions, over the server's own Subsonic API.
- **Audiobookshelf** — book progress and finished flags, over its
  REST API with an API token.
- **Podcast apps** — subscriptions migrate via OPML import on the
  podcasts screen (Pocket Casts, AntennaPod, and friends all export
  it).

Play history lands as backdated import-source listen sessions with
deterministic ids, so re-running an import never double-counts.
A dry run matches and reports without writing anything; the finished
task's summary shows what matched, what did not, and what was
written. Credentials for the source server are used for the run and
sealed at rest.

## Catalog jobs and tasks

The tasks screen shows background work: file tooling, acquisitions,
migration imports (with their reports), and the catalog's own jobs
(scans, enrichment, organize runs). Task progress streams live over
the WebSocket channel; `GET /api/v1/tools/tasks/{id}/events` serves
the same lifecycle as server-sent events for anything that prefers a
plain HTTP stream.

# Admin and ops

Running WaxDeck for a household means letting people in, keeping the
server healthy, and being able to undo mistakes. This page covers the
administration surface: accounts and permissions, signup requests and
invites, the audit log, backups and restore, scheduled jobs, the
trash, upload oversight, read-only mode, transcoding limits,
Prometheus metrics, and moving in from another server.

Everything here lives in the **admin console** at `/admin`, reached from
the Admin console row in the sidebar or from Settings > Server. The
console has a dashboard (health, the review queue's depth, jobs in
flight, the last backup, and the two long operations you start by hand)
and a section per area, each with a location of its own so "it is under
Backups" is a link rather than a set of directions. On a phone the
console is a list of those sections. An account without the
administrator role that opens a console location gets a page saying so
rather than the console: the link keeps its meaning, and nobody is left
pressing controls that all refuse.

The **review queue** is not in the console. It has its own row and its
own location at `/review`: it is the surface an administrator opens
daily, and an uploader sees their own entries there.

## Accounts, roles, and permissions

Accounts are managed in the admin console (Users) or over the API. The
editor also carries a **Child account preset**: one press sets no
explicit content, no deleting, downloading, or uploading, and a deny
rule for advisory-tagged tracks, and everything it set stays editable.
Kids mode is administrator-configured - there is no separate kid-facing
app. Every account has a role (`admin` or `user`), library
visibility (every library, or an explicit set), and a set of
permission toggles:

- **Upload** - bring audio into the library: chunked uploads from
  any client, and URL acquisitions, both staged for a review
  decision instead of landing directly. The grant carries
  item-scoped metadata editing over what the account's uploads
  bring in, and an optional **pending upload limit** caps how much
  the account may hold in staging at once (acquired bytes count
  against it too). It is a limit on the queue, not on what the
  account has contributed: importing a staged upload into the
  library frees the room it held, and nothing here bounds how much
  somebody adds to the library over time.
- **Download** - fetch original files for offline use.
- **Delete** - delete visible library items to the trash. Permanent
  deletion is always admin-only.
- **Explicit content** - see and play content flagged explicit.
  Podcasts carry the feed's own flag; turning this off hides flagged
  shows and episodes. Music mostly has no canonical explicit flag, so
  the honest music-side control is a tag rule (below).
- **Shared outputs** - control shared device endpoints (cast targets,
  DLNA renderers, the jukebox). A user's own devices are always
  theirs to control.
- **Manage podcasts** - subscribe, unsubscribe, and trigger episode
  fetches. Off leaves existing subscriptions playable but frozen.
- **Tag allow / deny lists** - visibility rules over custom tags.
  A deny rule hides items matching it; an allow list, when set, shows
  only items matching every rule. An item without the rule's tag
  passes a deny rule, which is exactly how a deny list should read.
  Together with the explicit toggle this is the parental-controls
  mechanism: a kids account with an allow list on `KIDS=yes` sees
  nothing else.
- **Max transcode bitrate** - a per-account ceiling on transcoded
  streams, overriding the server default.

Administrators hold every permission implicitly. A new account starts
with everything granted except delete and upload, and no tag rules.
Changing a user's content rules retires their sync cursors, so offline
clients re-mirror under the new rules instead of keeping stale
content.

## Signup requests and invites

Out of the box, accounts are admin-created. Two self-serve doors can
be opened:

- **Open signup** (Settings > Server): registrations land as pending
  requests. A pending account cannot log in until an administrator
  approves it - approval assigns the role, library access, and
  permissions in the same step. Rejection deletes the request and
  frees the username. New requests raise a `signup-requested`
  notification.
- **Invites** (Users > Invites): an invite link token pre-approves
  signup with a chosen shape. The token is shown exactly once at
  creation; invites can be single- or multi-use, can expire, and can
  be revoked. Invites work whether or not open signup is enabled.

## The audit log

Every administrative and destructive action is recorded: who did it,
to what, and the detail of the change - account edits, permission
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

Back up on demand (Backups > Back up now) or on a schedule. Retention
keeps the newest N archives and a total byte budget, both editable in
settings; imported archives are exempt. Archives can be downloaded
from the UI and uploaded to another server. Outcomes raise the
`backup-completed` and `backup-failed` server notification events, so
a schedule that quietly stops producing archives is a notification,
not a surprise during a restore.

**Restore is staged, then applied at the next server start.** Staging
validates the archive and answers with the plan: whether this server's
key opens the archive's sealed credentials, and exactly which
credentials break when it does not (they are marked pending re-auth
instead of surfacing as scattered errors). At the next start the
current databases are set aside - not deleted - the archive's
databases move into place, and every client's sync cursor resets
cleanly. A staged restore can be cancelled any time before the
restart.

Restoring onto a new host: upload the archive (Backups > import), stage
it, restart. Without the old keyfile everything restores except sealed
credentials (app passwords, scrobbling connections, private feed
logins, notification target configurations), which need re-entering.

## Scheduled jobs

Three schedules, each a five-field cron expression in server-local
time: **scan** (a full library scan), **backup**, and **prune** (event
log, replay-guard stamps, audit history, ended playback sessions).
Prune ships enabled at 03:30 nightly; scan and backup ship disabled
until configured. Each schedule shows its last run, last error, and
next firing time.

## The trash

Deletions go to the catalog's reversible trash - a same-volume
`.waxbin-trash` directory the scanner skips. The admin trash surface
lists every trashed file with where it lived, restores files back into
the catalog (re-scanned and un-archived), and empties the trash
permanently, reporting the space reclaimed. Deleting items from the
item page previews what will be deleted (files, bytes) before anything
moves.

## Upload oversight

Uploaded and acquired files stage under the data directory, never in
a library root, until a review decision imports them; staged bytes
live on the data volume and are not part of backups (which hold only
the databases). The uploads screen lists an uploader's own sessions;
administrators see every account's, with who owns each. Any
unfinished or undecided session can be deleted there, freeing
its staged bytes and closing its pending review entry; a file that
already entered the library is deleted in the library instead, like
any other item, and it stopped counting against the pending upload
limit the moment it was imported. Staging never needs manual sweeping: stalled
transfers and staged files nobody decides on are reclaimed a week
after the session opened, their pending review entries closed with
them. Granting upload rights and setting quotas is covered above;
the upload flow itself, grouping, and the review pipeline are in the
[curation guide](curation-and-metadata.md).

Three bounds apply whatever the per-account quota says, and none of
them is configurable: one upload may declare at most 16 GiB, one
request may carry at most 32 MiB of it, and a session is refused with
`storage-full` when the staging volume cannot hold what it declared
alongside what the transfers already running were promised, keeping
512 MiB spare for the databases and the backup archive that is written
beside them. A session's unwritten bytes stop being counted an hour
after it opened, so a transfer somebody abandoned reserves the volume
for an hour rather than for the retention window. That bound is the
server's disk rather than anybody's allowance, so it is yours: free
space on the data volume, or decide what is staged.

Opening a session, sealing one, opening or finalizing a batch and
starting an acquisition are paced per account - a burst of 600
refilling at 60 a second, which no real transfer approaches. Sending
bytes and abandoning a session are deliberately not: a transfer is
many chunks, so pacing those would be a throughput ceiling rather than
a pace, and pacing the discard would stop a client releasing the very
staging its failures reserved.

## Read-only mode

For media mounted read-only on principle: per library, or server-wide
(the console's Server settings). A read-only library refuses uploads, organizing,
file write-back, deletion, and the file tools with the `read-only`
error code, while playback, browsing, and per-user state (stars,
progress, playlists) keep working. Podcast libraries need a writable
root for episode fetching; the flag refuses fetches too.

## Adding a library at runtime

The console's Libraries section lists every root with its path, what it
holds, how many items the catalog has under it, its read-only flag, and
its matching mode (automatic, ask me, or leave alone). Adding one there
creates a library root without restarting the server: the path is validated (absolute, not overlapping an existing
root, the inbox, or the podcast download dir), cataloged, and scanned in
the background. Browsing and downloading its files work as soon as the
scan indexes them. The library name doubles as the streaming engine's
root name, so it also has to be free there - including the podcast root
name, which the engine mounts but the library list never shows.

Streaming needs the engine to mount the same root, which it can learn at
runtime. Point both sides at one JSON config file - `WAXDECK_FLOW_CONFIG`
for the server, `WAXFLOW_CONFIG` for the engine - and creating a library
rewrites the file's `roots` array and asks the engine to reconcile.
`make up` wires this and seeds the file; the compose service mounts the
directory read-write into WaxDeck and read-only into the engine, and
both containers run as the same UID (as they already must for the shared
catalog volume). Under compose the file holds roots only:
`WAXFLOW_API_KEYS` and `WAXFLOW_CATALOG_DB` stay environment variables,
and the engine reapplies environment precedence on every reload, so they
keep working untouched.

Two limits are worth knowing. The engine advertises whether it reloads
at all (`delivery.rootsReload`), and it only does so when its roots come
from a config file - pinning them with `WAXFLOW_ROOTS` disables the
endpoint, since that variable is read once at process start. And a
runtime-added root only streams if its path is already inside a volume
the engine mounts; the reload reconciles names and paths, it cannot
mount a filesystem. The engine opens each root while reconciling, so a
path it cannot see fails the reload with a plain error rather than half
working. Either way the library is created and keeps browsing and
downloading; the reason streaming has to wait for an engine restart
comes back on the create response, stays on the Libraries screen until
the next one, and is recorded on the `library.create` audit entry.

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

The migration assistant (Admin console > Import from another server)
pulls listening state from a running server and matches it onto your
library through the same identifier-first resolve ladder the rest of
WaxDeck uses (MusicBrainz IDs, then fingerprints, then descriptive
metadata):

- **Navidrome / any Subsonic server** - starred songs, ratings, play
  counts, and bookmark positions, over the server's own Subsonic API.
- **Audiobookshelf** - book progress and finished flags, over its
  REST API with an API token.
- **Podcast apps** - subscriptions migrate via OPML import on the
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

A finished task is a receipt, and receipts pile up on an account that
never opens this screen. The scheduled prune clears terminal rows past
`taskRetentionDays` (Settings > Server); the default is 30 days, and 0
keeps them indefinitely. Only terminal rows go - a task still running or
still waiting to be claimed is work in progress whatever its age - and
the setting is re-read on every pass, so a change takes effect at the
next run rather than at the next restart. Clearing by hand, per row or
all-finished-at-once, still works and is unaffected.

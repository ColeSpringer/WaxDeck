# 11. Notification providers and two-scope targets

Date: 2026-07-22

## Status

Accepted

## Context

Notification delivery was a hardcoded two-armed switch: one
admin-configured Apprise relay (a settings blob holding a URL, a
target string, and an enabled-event list) plus per-user UnifiedPush
registrations. That shape carried three problems. First, everything
that was not UnifiedPush had to route through a separately hosted
Apprise container, when the events people actually want (a Pushover
ping, an ntfy topic, a Discord webhook) are one small HTTP call each.
Second, the model had no notion of whose notification an event is:
the single enabled-event list gated only the Apprise arm, push
delivery was unconditional, and a server-operations event
(signup-requested, which the catalog did not even list) and a
personal event (episode-downloaded) were configured in the same
place by the same person. Third, per-destination health was
invisible: a revoked token failed silently in the log.

## Decision

### One table of targets, two scopes

A `notification_targets` row is one delivery destination: a kind
(pushover, ntfy, gotify, discord, webhook, apprise, unifiedpush), a
scope, an owner, a sealed config document, a per-target enabled-event
list, and the delivery-health triple (last success, last error, last
error time) that scrobble connections already carry. The settings-blob
Apprise config and the push_registrations table are both replaced.

Scope `server` rows (owner NULL, administrator-managed) receive
server-operations events. Scope `user` rows belong to one user, who
picks which user-scope events reach each target; administrators may
additionally opt personal targets into server events, which preserves
the signup-request-to-admin-phone flow. Event gating is enforced
structurally in the emit paths, one filter for every kind, which
retires both latent bugs (unconditional push, the missing
signup-requested catalog entry) by construction.

Events carry a scope in the catalog (`GET /notifications/events`), and
the emit API splits accordingly: user-scope events fan out to the
named users' targets, server-scope events to server targets plus
opted-in admin-owned personal targets, re-filtered against the current
admin set so a demoted administrator's targets deliver nothing.
Unknown event names are refused at target write time; the catalog
endpoint gives clients forward compatibility. The `test` event is
reserved: a per-target test enqueues one delivery directly, bypassing
event gating by construction, and the old blanket admin test (deliver
to everything at once) is gone.

UnifiedPush registrations become kind `unifiedpush` targets, deduped
per owner on the endpoint URL. The push-registration endpoints stay
wire compatible on top (only the pid prefix changes): a genuinely new
registration defaults to the full user-scope event set, matching what
unconditional push delivered before, while a routine re-register of a
known endpoint (UnifiedPush clients re-POST at every app start)
refreshes endpoint and label only and preserves the enabled-event
selection made in the targets UI.

### Providers as a package

`server/internal/notify` holds one file per provider behind a small
interface: validate-and-normalize config at write time, deliver one
message at drain time. Registration is an explicit map, no init magic.
Providers classify definite rejections (a revoked token, a 4xx that
cannot heal) as permanent so the outbox fast-exhausts instead of
retrying ten times; the scrobble package set the precedent. Payloads
follow each service's documented shape: Pushover form-posts with its
250/1024 truncation and priority range, ntfy uses JSON-publish mode
(topic-in-body avoids the non-ASCII header trap) with optional Bearer
auth, Gotify sends the token in a header so it never lands in URLs or
logs, Discord uses embeds with the service's length caps and a
webhook-host allowlist, the generic webhook posts a documented
`{event, title, body, timestamp}` JSON body, the Apprise arm carries
over verbatim including its notify-path derivation, and UnifiedPush
keeps the 3500-byte UTF-8 payload budget.

### Delivery, secrets, and the outbox

The outbox row now references its target by id (cascade on delete)
and the config is read at delivery time, so an edit or a revocation
between enqueue and drain wins, and a delivery whose target vanished
completes silently. Config documents are sealed whole with the server
key: backup archives carry waxdeck.db, and tokens must not be
readable out of an archive. Unlike scrobble secrets (never returned),
a target's config round-trips verbatim to its owner on GET, the same
documented decision the admin Apprise config made, now owner-scoped.
The restore preflight enumerates notification targets alongside the
other sealed tables and reports them as casualties of a key mismatch;
this matters doubly because UnifiedPush endpoints used to be plaintext
rows and become key-sensitive only now.

Delivery outcomes land on the target's health fields, and how much of
a failure they carry is a per-kind decision: the pinned-host kinds
(Pushover, Discord) include the service's own error text, because the
response can only come from the service itself and a bare 400 leaves
the owner guessing which credential is wrong. Every other kind
reports the status alone. User-pointed destinations, UnifiedPush
especially, must not become a response-content oracle for whatever
host a user aims them at: delivery reachability is granted, response
read-back is not.

### Outbound-fetch guarding

The SSRF stance is per kind and per scope, reusing the radio and
scrobble guards verbatim. User-scope ntfy, Gotify, webhook, and
Apprise targets are guarded at write time (friendly error) and dial
time (the boundary): those are user-pointed URLs. Pushover needs no
guard (fixed host) and Discord's allowlist pins its two webhook
domains. UnifiedPush stays deliberately unguarded at both scopes,
the documented spec stance: self-hosted LAN distributors are
legitimate, bodies carry only notification text, and responses are
never surfaced. Server-scope targets are unguarded, today's stance
for admin-configured destinations. LAN deployments opt user targets
in with `WAXDECK_ALLOW_PRIVATE_NOTIFY_HOSTS`, shaped like the radio
and scrobble escape hatches.

## Consequences

- The `/admin/notifications` endpoints and the NotificationConfig
  schemas are removed, a breaking spec change made deliberately
  pre-release; the PR carries a temporary oasdiff allowance that is
  deleted once the base ref contains the removal.
- Every new provider is one file, one registry entry, one config
  description block in the spec, and a test suite against a local
  HTTP sink; nothing else changes.
- Notification failures are visible where they are actionable: on
  the target row, in the owner's own settings surface.
- Conscious cuts are recorded in deferred work: webhook custom
  headers and HMAC signing, Retry-After honoring, a per-target mute
  flag, Discord rich embeds, ntfy attachments and action buttons,
  per-target rate limiting, and an import-completed user event (a
  fully automatic import is silent today; review-ready deliberately
  skips entries that auto-apply).

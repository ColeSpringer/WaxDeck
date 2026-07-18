# 4. Identity: opaque sessions, synchronizer CSRF, brokered OIDC

Date: 2026-07-18

## Status

Accepted

## Context

WaxDeck is multi-user from day one: local accounts, per-device
sessions, roles, per-library visibility, and OIDC single sign-on, all
serving web (cookie) and native (bearer token) clients from one API.
Several of these decisions are the kind a future change would quietly
re-litigate, so they are recorded here.

## Decision

### Sessions and tokens

Credentials are opaque 32-byte random tokens, stored only as SHA-256
hashes in waxdeck.db. There are no JWTs: one revocable store, no key
ceremony, and a database lookup per request is free at self-host
scale. One session row backs both transports; the same token value
rides the HttpOnly `waxdeck_session` cookie for web and the
Authorization bearer header for native clients. A login that supplies
`deviceName` is listed as a device, anything else as a web session;
the distinction is cosmetic (the device list), not semantic.

Sessions slide: web sessions expire after 14 idle days, device
sessions after 90, and any touched request renews the window (touches
are coalesced to one write per five minutes). Native clients rotate
their token via the refresh endpoint; the old token stays valid for a
30 second overlap so requests already in flight never fail. Revocation
is row deletion and is immediate.

### CSRF: synchronizer token, not double-submit

Mutations authenticated by the cookie must echo the session's CSRF
token in the `X-CSRF-Token` header. The token is returned by login and
session inspection and compared against the session row: a
synchronizer token. The double-submit cookie variant was rejected
because it is strictly weaker (any subdomain or header-writing vector
that can set cookies forges it) and because the generated response
types carry exactly one Set-Cookie header, so a second CSRF cookie
would need hand-rolled header plumbing for no security gain.
Bearer-authenticated requests are exempt: cross-site pages cannot set
the Authorization header. The model depends on the API origin never
enabling credentialed CORS, which the spec states as a convention.

### Passwords and rate limiting

Local passwords hash with argon2id (64 MiB, t=3, p=1: RFC 9106's
second recommendation, sized for Pi-class hosts under concurrent
logins). Login failures burn a dummy verification when the account
cannot match, keeping unknown-user and wrong-password timing alike,
and the response never distinguishes the two. Failures rate-limit in
memory per source address and per account with exponential backoff;
every failure logs one stable line (`auth failure`, user, ip) for
fail2ban jails. Limiter state resets on restart by design: the argon2
work factor is the floor, the limiter is a ceiling.

### Bootstrap

A fresh server has no accounts and exposes a one-shot bootstrap
endpoint that creates the first administrator and closes forever
(checked on the single write connection, so concurrent attempts
serialize). No seeded default credentials exist in any form.

### Catalog mapping and library visibility

Each account owns a WaxBin playback user created at provisioning. The
WaxBin user is named by the WaxDeck user id, never the username:
WaxBin user names are unique forever, and usernames can be deleted and
recreated. Deleting an account orphans its catalog history rather than
destroying it. Roles are `admin` and `user`; per-library visibility
grants live in waxdeck.db and are enforced by attributing each item's
file path to a library root. An item outside the caller's scope
behaves exactly as if it did not exist, list pages simply omit it, and
restricted callers get no artist or album search groups at all
(entities have no cheap library attribution, and hiding beats leaking
a private library's catalog). Album and artist artwork is served
without an attribution check: PIDs are unguessable ULIDs and every
discovery path is filtered, so the residual exposure is accepted.

### OIDC: server-mediated, one redirect URI

The server brokers the whole authorization-code-with-PKCE flow; the
identity provider registers exactly one redirect URI (the server's
callback) for every form factor. The flow's completion mode is chosen
at start: `web` sets the session cookie and redirects into the SPA,
`app` bounces a one-time code through the `waxdeck://auth` deep link,
`loopback` bounces it to a localhost listener for desktop, and `code`
renders it for manual copy. One-time codes are stored hashed, are
single-use with a five minute expiry, and accept an optional
proof-of-possession binding: the client sends a challenge (base64url
SHA-256 of a secret) at start and must present the secret at exchange,
so an intercepted code (a rogue app claiming the deep-link scheme) is
useless alone. First-party clients always bind.

Accounts resolve by provider identity (issuer and subject) only. A
first login provisions a fresh account, disambiguating taken usernames
with a suffix; it never links onto an existing local account by
username or email, because silent merges on unverified claims are an
account-takeover class. Linking is a future explicit admin action.
When a groups claim is configured the IdP is authoritative for the
admin role on every login, except that the last enabled administrator
is never demoted on the IdP's say-so: the server must stay
administrable even against a misconfigured claim.

## Consequences

Every request costs one indexed lookup on waxdeck.db's read pool, plus
a grants read for restricted accounts. Revocation and disablement are
immediate, which proxy-mode streaming inherits (media tokens stay
short-lived). Web clients must carry the CSRF header after a reload;
native clients must store the bearer token in the OS keychain and
rotate it periodically. OIDC requires the deployment to state its
public base URL. The visibility design trades entity-level search for
restricted users until entities gain library attribution upstream.

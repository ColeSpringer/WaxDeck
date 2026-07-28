# 27. Per-device settings

Date: 2026-07-28

## Status

Accepted.

## Context

WaxDeck already stores preferences. `/prefs` holds a document per
account — theme, locale, timezone, the shared-stats opt-out — and
`PrefsController` reads and replaces it. That is the right home for
anything a listener would expect to find waiting on a new phone.

It is the wrong home for the other kind. A collapsed sidebar is a
statement about this screen and this pointer. A spoken-word skip interval
is about these headphones. A wifi-only preload switch is about this
connection. The recent searches are a shortcut back to what was typed
here. Syncing those would mean a phone inheriting a desktop's icon rail,
and a device that is offline could not read its own preferences at all.

So three deferred entries and the settings section of the UI plan all
said the same thing — "needs the per-device client-settings store" —
and no such store existed. Two controllers shipped as in-memory
`Notifier`s with a comment pointing at this decision, which is what makes
it worth writing down rather than just building.

The awkward half is the web build. Drift does not run there at all:
`open_stub.dart` throws and `mirrorDatabaseProvider` answers null under
`kIsWeb`. The established pattern for that is the queue's `NoQueueStore`
— a store where nothing persists — and taking it here would leave the
sidebar rail unpersisted on the desktop-shaped surface that most wants
it. A browser window *is* the desktop client for a large share of this
product's use.

## Decision

**A second store, `ClientSettingsStore`, beside the synced one.** Three
methods (`read`, `write`, `remove`) over opaque string values, plus
`ClientSettingKeys` naming what is filed where. Nothing in it ever syncs;
the server never sees it.

**Key/value, not typed columns.** The settings surface names ten of these
already and every phase adds more; a typed column per preference is a
schema migration per preference. Encoding lives with the controller that
reads the key, which is the one place that knows whether the value is a
bool, an interval, or a list. `decode` returns null for anything that
does not parse, so a value written by an older build reads as "nothing
stored" instead of throwing at launch.

**Native persists in the mirror database; the web build persists in
`localStorage`.** Different problems, different implementations, one
port — the same split ADR-0025 made for artwork, and made for the same
reason. Mirror schema v3 adds a `ClientSettings` table (and, in the same
migration, the `QueueMeta.sourceCursor` column the queue-UI phase needs,
so that phase mints no second one).

**The web implementation lives in `app/app/lib/src/settings/`, not in
`waxdeck_data`.** The drift package holds the port and the native store.
A browser-storage backend inside the package whose entire purpose is
SQLite is the coupling ADR-0025 avoided by putting the web artwork store
in the app.

**It takes a `BrowserStorage` seam, not `web.Storage`.** The store is
then a plain Dart object: the probe, the degradation, and the key
semantics are exercised on the VM against a fake, and only the handful of
lines that hand over the real `localStorage` are untested by machine.

**Degrade, never throw — in both implementations, not just the one with
an obvious way to fail.** `localStorage` is not a guarantee: private and
incognito contexts have thrown on write, a partitioned context can refuse
it, a visitor can switch it off. The browser store probes once at
construction with a full write-read-delete round trip (a write-only probe
passes in a context that accepts a write and keeps nothing) and guards
every call after that; a browser that will not hold a value gets an
in-memory one, so a preference set in a private window lasts the session
rather than taking down the shell that reads it at startup. The drift
store guards the same way, for a closed database or a full disk. An
interface where one implementation honors a documented promise and the
other quietly does not is worse than one that never made the promise.

**And the reader enforces it rather than trusting it.** These are
unawaited futures on a startup path, so anything escaping one is an
unhandled zone error, not a caught failure — while the entire cost of
losing is a preference that reads at its default. The mixin therefore
guards its own read and write, which also covers a `decode` that a later
setting writes badly. Failures go to the console, because a preference
that will not persist has no other symptom; that is the same treatment,
for the same reason, that a queue which will not write gets.

**Whatever this session changed is answered from memory first — a
removal as much as a write.** That is what makes a change the browser
refused still hold: it is in the shadow whether or not storage took it.
Membership in the shadow is what makes it authoritative, not a non-null
value, because a removal storage rejects would otherwise fall through and
be answered with the value that was just deleted. The cost is that a
second tab's writes are not picked up mid-session, which is deliberate —
these are preferences read at startup, not a cross-tab channel, and the
native store offers no such channel either.

**The state stays synchronous.** Readers watch a `bool`, not an
`AsyncValue<bool>`. The notifier starts at its default, replaces it once
the stored value arrives, and writes every change back; a change made
before the read lands wins, so a listener who collapses the sidebar
during startup does not have it reopened by their own last launch. A
shell that could not lay itself out until a disk answered would be the
worse trade.

**But "the change wins" is a rule about preferences that name one
thing.** For a preference that accumulates it is a data loss: the first
search remembered before the stored list arrived would discard the whole
history, and the write behind it would persist a one-entry list over it
permanently. So the race has a `merge` hook. Its default keeps the
session's value — correct for the sidebar — and the recent searches
override it to put the new query on the front of the stored ones and
write the result back.

**A rebuild must not cost the preference.** Riverpod re-runs `build` on
the same notifier instance when a dependency changes, and whatever
`build` returns replaces the state, so a `hydrate` that always answered
the default would discard the listener's value *and* skip re-reading it,
leaving the setting at its default for the rest of the session. The
notifier keeps what it knows across rebuilds, and it reads the store
provider rather than watching it, since which store this is cannot
meaningfully change under a running app.

**Signing out clears the account's content and nothing else, and which
is which is per key.** The queue and the artwork go because they are the
departing account's. A collapsed sidebar describes the machine and
stands; wiping it would make signing out a factory reset of a shared
desktop. The recent searches, despite living in the same per-device
store, go with the queue: they are strings that listener typed, they name
things in *their* library, and on web they sit in origin-scoped
`localStorage` that the next account on the browser reads back. The store
being per-device is a fact about where a preference lives, not a licence
to keep every one of them across a sign-out, and each new key answers the
question for itself.

## Consequences

- Two readers ship with the store, deliberately: the sidebar collapse
  (a bool) and the recent searches (a list, encoded as JSON because a
  query may contain any separator a keyboard can emit). A store with no
  reader has an unvalidated shape, and the two cover both value kinds.
- The remaining three named settings — spoken-word skip intervals, the
  wifi-only preload switch, and density — are not wired here. Each needs
  a Settings control that does not exist yet, and wifi-only additionally
  needs a connectivity port (no connectivity plugin is pinned anywhere),
  which is its own wrap-and-pin decision. Their deferred entries stay
  open and now name a store that exists.
- The real `localStorage` binding is not covered by an automated test.
  Nothing in this repo runs under a browser — there is no `@TestOn`
  anywhere and `waxdeck_data`'s tests import `drift/native`, so
  `--platform chrome` cannot simply be switched on — and adding Chrome to
  CI is an infrastructure decision that should not ride a store. Recorded
  in `docs/deferred-work.md` with the verification that stands in for it.
- Migration steps are cumulative and `createTable` builds *today's*
  shape, so a v1 install is handed a `queue_meta` that already carries
  `sourceCursor` and the v3 step must not add it again. The step says
  which versions it means, and the "an upgraded schema is the schema a
  fresh install gets" test is what catches forgetting to. New columns are
  declared last in their table for the same family of reasons: `ALTER
  TABLE ADD COLUMN` appends, so declaration order and physical order stay
  the same on both paths.
- `sourceCursor` is carried by the queue store even though nothing fills
  it yet. A column the queue phase would have had to wire from scratch is
  a trap rather than a head start: a `save` builds the whole meta row, so
  one that omitted the field would reset the stored cursor on every write
  and nothing would say so. The round trip is pinned by a test that
  asserts the entire record; the one step left is `QueueState.toStored`
  having a cursor to hand over.
- `database.g.dart` is checked in, and regenerating it was previously a
  hand step that nothing verified. `make gen-mirror` now does it,
  `generate` includes it, and `drift-check` covers the file. The target
  is named for the mirror rather than for drift: `drift-check` is the
  codegen-drift gate over every generated artifact and has nothing to do
  with drift the package.

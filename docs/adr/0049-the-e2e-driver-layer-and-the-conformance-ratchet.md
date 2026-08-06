# 49. The e2e driver layer and the conformance ratchet

Date: 2026-08-05

## Status

Accepted. ADR-0050 covers the account model the same re-architecture
introduces; ADR-0043 owns the semantics-id registry this extends.

## Context

Every substantive change to the app broke e2e specs in ways that had
nothing to do with the change. Over 96 commits, 34 separate breakage
incidents were diagnosed: UI restructures breaking the navigation paths
specs had memorised (10), collisions between the four parallel workers
(8), genuine regressions correctly caught (7), click and rect races on
the Flutter canvas (6), semantics-id renames (5, mechanical and by
design), and environment flakes (5). Sixty percent of all app and server
commits - 74% of the last thirty - had to edit `e2e/` in lockstep.

The suite has real value: seven of those incidents were app defects that
only e2e found. So the goal was never to shrink it. It was to keep the
signal and stop paying the tax.

Four causes, in the order they cost the most:

**Specs encoded navigation paths, not intents.** There was no driver
layer. `helpers.ts` was a 305-line toolbox of click primitives, and the
specs held 292 raw `page.locator(...)` calls, 33 file-local helpers, six
divergent inlined logins and seventeen re-implementations of the same
sign-in. Conventions that nothing enforces rot. Each rebuild of the
shell, home, settings or player broke eleven or twelve spec files, none
of which were about the thing that changed.

**Canvas interaction was re-solved per incident.** Rect settling,
scroll-into-view, menu-at-rest, DOM-versus-controller typing: each was
diagnosed once, written into whichever helper needed it, and then
partially rediscovered elsewhere. Twenty-two `force: true` calls and 230
hardcoded `timeout:` literals sat in the specs, each chosen against one
failure.

**The id registry was leaky on the TypeScript side.** ADR-0043 made
identifiers generated, and the Dart side has a test that fails on a
hand-written one. The TypeScript side had nothing: four
`flt-semantics-identifier^=` prefix literals survived renames silently,
because the registry could build one id from its arguments but had no way
to say "any of them". Alongside those sat roughly 135 `getByRole` login
strings and 213 hand-typed `/api/v1/...` paths - and one past incident
was a hand-typed path that 404ed and read as a missing feature.

**Animation was a permanent source of races.** A forced click dispatches
at whatever rect the semantics overlay held a frame earlier, so a control
still travelling gets clicked in the wrong place. The suite had absorbed
this as retry budgets and rest checks.

## Decision

### Reduced motion, through the browser's own channel

Every blocking project runs with `contextOptions: { reducedMotion:
'reduce' }`. Flutter 3.44's web engine reads `prefers-reduced-motion` as
`AccessibilityFeatures.disableAnimations`: `AnimationController` scales
to 5% of its duration, route transitions included, and `WaxMotion.of`
hands widgets its `reduced` token set. The class of failure where a click
lands on a rect that is still moving stops existing.

This is not a test seam. It is the accessibility channel a real listener
uses, and what it produces is the app that listener gets.

Two guards, because a premise that fails silently is worse than one that
fails:

- A `motion-smoke` project runs last, re-running `ui.spec.ts` - the
  walking skeleton: form login, chrome walk, playback - with
  `reducedMotion: 'no-preference'`. Animated paths stay covered, and a
  failure there is unambiguous.
- Each project declares its mode once, in a `motion()` helper that sets
  both `contextOptions` and `metadata.motion`. A worker's first test
  asserts the browser is in the declared mode. Playwright has no
  top-level `use.reducedMotion`; it rides `contextOptions`, which is
  whole-object and does not merge across project levels, so a project
  that sets `contextOptions` for another reason would silently drop the
  mode. The canary catches that.

Before the flip, every dwell time in the app was checked: each is a
`Timer` or `Future.delayed` on a literal duration, none derived from a
`WaxMotion` token or an `AnimationController`, and the one visibility
window a media query gates (the visualizer's chrome linger) keys off
`accessibleNavigation`, not `disableAnimations`. Nothing shortens.

### The driver owns locators and navigation; specs express intent

`tests/driver/` holds the layer: `nav.ts` (a `DEST` table of location
plus arrival marker), `gestures.ts` (the four canvas primitives),
`api.ts` (the typed server hand), `seed/` (named preconditions),
`budgets.ts` (timeout tiers), and a surface module per area of the app.
A spec says where it wants to be and what it wants to happen.

**Arriving by URL is the default.** `nav.enter(dest)` is a cold load of
the destination's own path, which the server's SPA fallback answers since
locations moved into the path (ADR-0022). With the session planted as a
cookie that costs one app boot, which is less than a boot plus a login
plus a walk through the chrome. It also stops nine specs from asserting
the sidebar's structure by accident. `nav.to(dest)` is the chrome walk,
for the specs where navigation itself is the subject, and
`driver-smoke.spec.ts` walks every entry that way - so the chrome
coverage the enter-default removes is concentrated in one test whose
failure says "dest playlists is unreachable" instead of nine specs
failing nine different ways.

**Sign-in is a planted cookie, not a driven form.** Web auth is the
`waxdeck_session` cookie alone: the app probes `GET /auth/session` at
boot and shows the shell or the login form on the answer. An
`APIRequestContext` that has logged in already holds what a browser
needs, so its `storageState()` goes to the browser context and every spec
opens signed in. Mutations still work - CSRF is a synchronizer token the
server demands from cookie-borne credentials only, and the app reads it
off the same boot probe. Both halves were verified end to end before the
design was built on: a planted cookie boots authenticated, a cookie
mutation without the header is refused 403, and a mutation the app itself
makes succeeds.

The login form is still driven, by the specs about the door: first run,
sign-up, identity, the accessibility walk, and the walking skeleton.
`auth.signInViaForm(who)` is for exactly those.

**Timeout tiers.** `budgets.ts` names every wait by what it is waiting
for: `T.step` 5s, `T.action` 20s, `T.nav` 30s, `T.assert` 15s, `T.fetch`
60s, `T.analyze` 90s, plus `J.long`/`J.journey` for whole-test budgets.
Specs pass no numbers.

**Copy stays with the spec.** The driver finds a control and returns a
locator; whether it says the right thing is the spec's assertion, because
that copy is the contract with the listener. The driver uses text of its
own only where a control publishes no identifier, and says so where it
does.

**The journey rule.** A scenario stays one end-to-end journey only when
each step consumes state the previous UI step produced and the seam is
the assertion. Steps that merely share a precondition become independent
tests, seeded through `driver/seed/`.

### Two mechanisms of enforcement, types first

**The two biggest rules are compile errors.** `fixtures.ts` hands specs a
`page` typed as `SpecPage` - a `Pick<Page, ...>` of the members a driver
cannot own on a spec's behalf (the viewport, network waits, `evaluate`,
the cookie's own request context). There is no `locator`, no `getBy*`, no
`click`, no `goto`. Reaching around the driver fails `tsc` at the call
site, in the editor, before the suite runs, and `npm run typecheck` is
already a step of `make e2e` and of CI. The real `Page` is available as
`rawPage`, requested by name only by the files the exemption ledger
lists.

The narrowing is a cast, contained to one line in `fixtures.ts`, because
Playwright's fixture types intersect rather than replace:
`base.extend<{ page: SpecPage }>` yields `Page & SpecPage`, which is
`Page`, and no narrowing at all. The value really is a `Page` at runtime;
what changes is what a spec is able to say.

Unmigrated specs import `legacyTest`, which is the old full-`Page`
fixture. Migrating a file is switching that import and letting the
compiler list the work.

**Generated API types.** `openapi-typescript` (pinned) emits
`tests/api-types.ts` from `api/openapi.yaml` as part of `make generate`,
committed and drift-checked like every other generated artifact.
`driver/api.ts` is typed against it: a path that is not in the contract
is not assignable, path parameters are named, and request and response
bodies both come back typed. The hand-typed-404 class is now a compile
error, and the API version prefix is written once. This mirrors the Dart
client's shape - generated DTOs behind a thin hand-written wrapper
(ADR-0002).

Typing the request body found three defects in the seed layer the moment
it was switched on, none of which any amount of care would have caught by
reading. It also needs one subtlety: openapi-typescript spells a
bodiless operation `requestBody?: never`, which makes the property's type
`undefined`, so `NonNullable` of it is `never` - and `never` extends
every shape, which leaves an `infer` unresolved as `unknown` and lets a
GET take any body at all. The conditional checks for `never` explicitly.

**`SemanticsIdPrefixes` closes the registry's last hole.** The generator
now also emits, for each parameterized id, the fixed head of its pattern
(`item-`, `share-row-`, `queue-entry-drag-`), plus a `semPrefix()`
selector helper. Ids whose first character is a placeholder have no fixed
head and are absent. The four hand-typed prefix selectors are gone.

**A small AST ratchet for what types cannot see.** `lint/conformance.mjs`
walks the specs with the already-vendored `typescript` package - AST, not
grep, because about a fifth of the lines in these specs are comments
quoting the code they explain, and a text scan reports the explanation as
the offence. It counts: hand-typed identifier strings, `force: true`,
numeric `timeout:` and `test.setTimeout(n)`, bare `setTimeout` and
`waitForTimeout`, `/api/v1/` literals in specs, `helpers` imports,
`legacyTest` imports, and any use of the bootstrap administrator outside
first-run and `accounts.ts`.

Counts live in `lint/allowlist.json`, per file per rule, and the check
fails when a count goes **up or down**. "ratchet: lower it to N" is as
loud as a new violation, which is what stops a migration from stalling
half-done; a file with no entry has no tolerance at all. It runs in `make
lint` and in `make e2e` before Playwright.

Exemptions each state a reason, so the set is auditable:
`a11y-audit.spec.ts` (a roles-and-names-only journey is its contract),
the perf specs (own contexts, platform instrumentation),
`desktop-loopback.spec.ts` (drives the test IdP's plain HTML form, not
the app), `editing-prototype.spec.ts` (canvas go/no-go probes are the
subject), `smoke.spec.ts` (API-only), `tests/support/*` (raw-page
infrastructure), and the two generated files.

## Consequences

- A shell restructure is an edit to `nav.ts` and a `driver-smoke`
  failure, not eleven spec files.
- An identifier rename or an API rename is `make generate` followed by
  compile errors that name themselves.
- Reduced motion cut the suite's wall time from about five minutes to
  about a minute and a half, before any other change landed.
- `make lint` and the drift job now need `e2e/node_modules`. Both install
  it guarded (`test -d node_modules || npm ci`), so a Go- or Dart-only
  iteration does not pay for it twice.
- `force: true` exists in exactly one file. Every forced click there sits
  behind a destination check or a rect-at-rest check, because forcing is
  not dropping the actionability wait but replacing it: over canvas,
  Playwright's own stability heuristics never settle on a live seek bar.
- The allowlist is a public count of the debt. It started at 610 findings
  across 27 files; it is empty when the migration is done, and `legacyTest`
  and `helpers.ts` are deleted at that point.
- A spec that genuinely needs the raw page asks for `rawPage` and appears
  in the exemption ledger. That is deliberate friction, and the ledger is
  short.
- Both gates run where they can block a merge: `npm run typecheck` and
  `npm run conform` are steps of the CI e2e job as well as of `make e2e`
  and `make lint`. A ratchet that only tightens on the machine that
  happens to run `make lint` is not a ratchet.
- `expect.poll` does not catch a callback that throws - it fails the
  assertion on the first attempt. Since `api.get` throws on any non-2xx,
  every poll built on it would turn one transient 503 into a permanent
  failure, so polls use `api.tryGet`, which answers `undefined` instead.
  Everywhere else a non-2xx is a defect and throwing it with the server's
  own body is what is wanted.

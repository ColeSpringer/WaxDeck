# WaxDeck e2e

Playwright tests against a real server binary with the embedded web UI.

```sh
make e2e         # rebuilds the UI and the binary if stale, then runs
```

Design decisions live in **ADR-0049** (the driver layer and the conformance
ratchet) and **ADR-0050** (the account model and the shared server). This
file is how to work in the suite.

## Writing a spec

A spec says what should happen. It does not know where controls are, how
to get to a screen, or what a URL looks like.

```ts
import { test, expect } from './fixtures';

test('a bucket is its own location', async ({ app }) => {
  await app.nav.enter('artists');       // cold load of /music/artists
  await app.music.openBucket(0);
  expect(app.nav.location()).toMatch(/\/music\/artists\/ar-/);
});
```

The `page` a spec receives is a **narrowed type**. It has no `locator`,
no `getBy*`, no `click`, no `goto` - reaching for one is a compile error,
not a convention. What it does have is the handful of members no driver
can own on a spec's behalf: `setViewportSize`, the `waitFor*` network
waits, `on`/`off`, `evaluate`, and `request`.

Everything else is `app`:

| | |
| --- | --- |
| `app.nav` | `enter(dest)` (by URL), `to(dest)` (through the chrome), `expectAt`, `reload`, `location()` |
| `app.api` | the server, typed against `api/openapi.yaml` |
| `app.seed` | preconditions, set through the API rather than driven |
| `app.auth`, `app.shell`, `app.music`, `app.search`, `app.player`, `app.settings`, `app.podcasts` | one surface per area of the app |

`nav.enter` is the default way to start. `nav.to` walks the sidebar and
belongs to the specs where navigation itself is under test;
`driver-smoke.spec.ts` walks the whole table so the other specs do not
have to.

**No numbers.** Timeouts are the tiers in `driver/budgets.ts` - `T.step`,
`T.action`, `T.nav`, `T.assert`, `T.fetch`, `T.analyze`, and `J.long` /
`J.journey` for a whole test. `expect` already defaults to the assert
tier, so most waits need nothing at all.

**Copy is yours.** The driver finds a control and hands back a locator;
whether it says the right thing is the spec's assertion.

## Accounts

Every test mints its own account, named after the test, through the
production `POST /users`. Nothing is shared with the other three workers
except the server itself.

That splits assertions in two, and it is the one thing to keep in mind:

- **Your account's state is yours.** Queues, stars, positions,
  subscriptions, preferences, playlists, shares. Assert exact counts.
  Assert absence. Take snapshots.
- **The catalog is not.** A reused stack carries previous runs' uploads,
  and three other workers are writing right now. Assert that what you
  made is *present*; never that something is missing, and never a total.
  Wrap anything that takes the file-mutation lease in
  `retryCatalogBusy`.

The bootstrap `admin` account has two jobs: it is the subject of
`first-run.spec.ts` and it mints the others. Nothing else may log in as
it. An account that needs the admin role declares it in `accountShapes`
(`tests/accounts.ts`) *and* in the pinned list in
`lint/conformance.mjs` - two files, so it shows up in review.

Anything else created by name - a playlist, a station, a share, an app
password - gets a deterministic per-spec name with create-or-reuse
semantics, or a `finally` that cleans up. There is no reset endpoint and
there will not be one (ADR-0036).

## Motion

Every blocking project runs the browser with `prefers-reduced-motion`,
which Flutter reads as `disableAnimations`: transitions collapse to 5% of
their duration and the rect-still-moving class of flake stops existing.
The `motion-smoke` project re-runs `ui.spec.ts` with motion on, last, so
animated paths stay covered.

Each project declares its mode once (the `motion()` helper in the
config), and the first test in each worker asserts the browser really is
in it.

## Gates

```sh
npm run typecheck    # the two biggest rules, as compile errors
npm run conform      # the rest, as a ratchet
npx playwright test
```

`make e2e` runs all three; `make lint` runs `conform`.

`lint/allowlist.json` holds a per-file, per-rule count of what has not
been migrated yet. It fails when a count goes **up or down** - "ratchet:
lower it to N" is as loud as a new violation. A file with no entry has no
tolerance at all.

## Migrating a spec

The unmigrated specs import `legacyTest as test`, which is the old full
`Page` and the shared administrator. To migrate one:

1. Change the import to `{ test, expect } from './fixtures'`.
2. Let `tsc` list every place the spec reached past the driver, and give
   each one a home on a surface.
3. Replace the login with nothing - the session is already planted.
4. Replace setup journeys with `app.seed`, and tighten the assertions the
   shared account used to prevent.
5. Delete the file's entry from `lint/allowlist.json`.

When the last one is done, `legacyTest`, `helpers.ts` and the allowlist
all go.

## Running

`make e2e` brings the thing under test up to date itself: the Flutter web
build when a Dart source is newer than the embedded bundle, and the
server binary always, since it embeds that bundle at link time.
Forgetting used to mean driving the *previous* build, which reads exactly
like a missing feature.

The config's `webServer` starts `server/waxdeck` and waits on
`/api/v1/health`; set `WAXDECK_BASE_URL` to target an already-running
instance instead, in which case `make e2e` rebuilds nothing.

Specs run against the full Chromium in its new headless mode
(`channel: 'chromium'`), not the `chrome-headless-shell` Playwright
reaches for by default. The web build is wasm, and skwasm rasterizes in a
dedicated worker behind SharedArrayBuffer; the shell segfaults on that
under load, which arrives as an unexplained "Page crashed".

The stack includes a small test identity provider
(`fixtures/cmd/testidp`) so the single sign-on journey runs against a
real HTTP IdP, and a feed host for the podcast specs.

| | |
| --- | --- |
| `E2E_RETRIES=0` | no retries. What the soak uses, and what to use when hunting a flake |
| `E2E_QUARANTINE=include` | run `@quarantine`-tagged tests too |
| `WAXDECK_E2E_MT_SKWASM=1` | re-test a new engine against the skwasm heap race |

A `@quarantine` tag takes a test out of the blocking run and leaves it to
the soak. Every one owes an entry in `docs/deferred-work.md` in the same
commit.

## Soak

`.github/workflows/e2e-soak.yaml` runs weekly and on demand:
`E2E_RETRIES=0 --repeat-each=3`, quarantine included. CI's own e2e job
annotates any test that only passed on a retry and keeps `test-results/`
- traces and hang evidence - for a flaky run as well as a failed one.

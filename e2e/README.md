# WaxDeck e2e

Playwright tests against a real server binary with the embedded web UI.

```sh
make e2e         # rebuilds the UI and the binary if stale, then runs
```

This file is how to work in the suite.

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
| `app.nav` | `enter(dest)` (by URL), `to(dest)` (through the chrome), `expectAt`, `back`, `reload`, `open(url)`, `location()` |
| `app.api` | the server, typed against `api/openapi.yaml`; `as(token)` for another credential |
| `app.seed` | preconditions, set through the API rather than driven |
| `app.admin` `app.auth` `app.books` `app.cast` `app.discovery` `app.home` `app.music` `app.player` `app.playlists` `app.podcasts` `app.queue` `app.radio` `app.review` `app.search` `app.settings` `app.sharing` `app.shell` `app.sso` `app.stats` `app.uploads` | one surface per area of the app |

`nav.enter` is the default way to start. `nav.to` walks the sidebar and
belongs to the specs where navigation itself is under test;
`driver-smoke.spec.ts` walks the whole table so the other specs do not
have to.

Two more fixtures, both lazy - ask and you pay, otherwise you do not:

- `otherAccount(suffix?)` mints a second listener off this test's title.
  Talk to them with `app.api.as(their.token)`.
- `device(options?)` opens a second browser as this account, with a
  session of its own, and hands back its own `App`. That second login is
  load-bearing: a client endpoint's id comes from the session it
  registered over, so two browsers on one cookie are one device and the
  picker will not show them each other.

**No numbers.** Timeouts are the tiers in `driver/budgets.ts` - `T.step`,
`T.action`, `T.nav`, `T.assert`, `T.fetch`, `T.analyze`, and `J.long` /
`J.journey` for a whole test. `expect` already defaults to the assert
tier, so most waits need nothing at all.

**Copy is yours.** The driver finds a control and hands back a locator;
whether it says the right thing is the spec's assertion.

**And that copy is English.** The specs assert English sentences and
look controls up by role and accessible name, both of which the app
draws from whichever locale it resolved. `playwright.config.ts` pins
`locale: 'en-US'`, so the runner's own desktop language decides nothing
and a Spanish machine runs the same suite as a green one. The
consequence is worth stating in both directions: a translation cannot
red this suite, and this suite does not gate a translation. What checks
the tables is `app/app/test/l10n_arb_test.dart`, and what proves a
second locale draws at all is the Spanish pump in
`app/app/test/settings_screen_test.dart`.

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

The session is planted as a cookie, so a spec opens signed in. The few
whose subject is the door say so per file (or per `describe`):

```ts
test.use({ session: 'signed-out' });   // the app lands on the form
test.use({ session: 'virgin' });       // no account, no bootstrap - first-run only
```

Anything else created by name - a playlist, a station, a share, an app
password - gets a deterministic per-spec name with create-or-reuse
semantics, or a `finally` that cleans up. There is no reset endpoint and
there will not be one.

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

`lint/allowlist.json` is **empty**, and every rule is a hard zero
suite-wide: hand-typed identifiers, `force: true`, hand-aimed secondary
taps (`button: 'right'`), numeric timeouts, bare sleeps, `/api/v1/`
literals, and any use of the bootstrap administrator.
It fails when a count goes **up or down** - "ratchet: lower it to N" is
as loud as a new violation - so the file stays as the seam for the next
rule rather than as a tolerance. `--write-baseline` re-seeds it, and is
only for the commit that adds a rule.

Three spec files are exempt, each with its reason stated in
`lint/conformance.mjs`, and they are exactly the three that ask for
`rawPage`: the accessibility walk (roles and names only, by contract),
the perf specs, and the desktop loopback (it drives the IdP's own HTML
form). If you need the real `Page`, the question to answer first is
whether your subject is really the app.

## Projects

```
setup → wave → mutators-uploads → mutators-admin → mutators-readonly → motion-smoke → focus-a11y
```

`wave` is everything that owns its own state, four workers wide. The
mutator projects hold what per-test accounts cannot divide - the files on
disk, the trash, the library table, the admin settings row - and uploads
runs before the console because the read-only switch refuses every upload
while it is on. `mutators-admin` runs parallel except its backup pair
(serial by declaration); `mutators-readonly` holds the read-only window
alone, so nothing else ever meets a refusing server. motion-smoke sits
before the focus projects on purpose - they fight the OS for focus and
are the flake-prone tail, and a late failure there must not cost the one
unreduced-motion pass. `feishin` and `sso-dex` join only when their
containers are up (`FEISHIN_BASE_URL`, `WAXDECK_DEX_SSO`).

## Running

`make e2e` brings the thing under test up to date itself: the Flutter web
build when a Dart source is newer than the embedded bundle, and the
server binary always, since it embeds that bundle at link time.
Forgetting used to mean driving the *previous* build, which reads exactly
like a missing feature.

The config's `webServer` starts `server/waxdeck` and waits on
`/api/v1/health`; set `WAXDECK_BASE_URL` to target an already-running
instance instead, in which case `make e2e` rebuilds nothing. A second,
rootless server (`run-wizard-stack.sh`, port 4430, no sidecar) backs
the `wizard` project alone: the first-run wizard's entry condition - an
administrator whose server has no libraries - can never hold on the
main stack, whose fixture root is configured at boot. External runs
skip the wizard project, since one URL names one server.

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

**About one run per fifteen minutes, locally.** The signup limiter is a
per-source-IP budget of five attempts in a quarter hour - successes burn
it too - and the suite spends four: the closed-door assertion, two
signups in `admin-ops`, and `signup-ui`'s walk-up. Past that the next
signup is refused, and `signup-ui` is what meets it, failing like a
broken form rather than like a limiter. The limiter lives in memory, so
restarting the stack clears it. The soak survives because the lockout
starts at thirty seconds and the attempts are spread out; a tight local
edit loop will not.

## Soak

`.github/workflows/e2e-soak.yaml` runs weekly and on demand:
`E2E_RETRIES=0 --repeat-each=3`, quarantine included. CI's own e2e job
annotates any test that only passed on a retry and keeps `test-results/`
- traces and hang evidence - for a flaky run as well as a failed one.

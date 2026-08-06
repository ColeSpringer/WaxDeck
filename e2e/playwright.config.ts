import { defineConfig, devices } from '@playwright/test';

// Point at an already-running stack with WAXDECK_BASE_URL (the compose-based
// harness comes later); by default we launch the locally built binaries.
const baseURL = process.env.WAXDECK_BASE_URL ?? 'http://localhost:4420';
const external = !!process.env.WAXDECK_BASE_URL;

// Retries hide flakes, so the two runs that are supposed to find them get
// none: E2E_RETRIES=0 is what the soak workflow and a local repeat-each
// run set. CI keeps one, not the two it used to: a test that needs three
// attempts is a quarantine candidate, not a pass.
const retries =
  process.env.E2E_RETRIES !== undefined
    ? Number(process.env.E2E_RETRIES)
    : process.env.CI
      ? 1
      : 0;

// A project's motion mode in one place: the browser's own accessibility
// channel, and the copy of it the suite asserts against. `metadata` is
// what the canary reads (tests/fixtures.ts), so a project that forgets
// to declare a mode fails loudly rather than inheriting one silently.
//
// reducedMotion rides `contextOptions` because Playwright has no
// top-level `use.reducedMotion`; note that makes it whole-object, so a
// project setting contextOptions replaces the inherited object rather
// than merging into it - which is why the mode is spread from here
// instead of being written per project.
const motion = (mode: 'reduce' | 'no-preference') => ({
  metadata: { motion: mode },
  use: {
    ...devices['Desktop Chrome'],
    contextOptions: { reducedMotion: mode },
  },
});

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  // Playback-heavy specs stream real audio while clipboard specs need
  // OS focus; too many concurrent pages makes both flaky. Four workers
  // keeps the suite fast without the contention.
  workers: 4,
  // Playwright's 30s default is a budget for a page; a spec here boots
  // the real Flutter web client against the real stack, and the one that
  // signs two of them in takes 15s on an idle workstation. Four workers
  // on a four-vCPU runner roughly doubles that, which is how connect
  // came to fail every CI run while passing locally in half the time.
  // 120s is what the heavy specs were already asking for one
  // `test.setTimeout` at a time; the ones that need longer than that
  // still say so themselves.
  timeout: 120_000,
  // The assert tier from tests/driver/budgets.ts, as the default every
  // `expect` and `expect.poll` gets. Playwright's own default is 5s,
  // which is a browser-speed number and too short for anything that
  // waits on this server; a spec that needs longer says which tier
  // (`{ timeout: T.fetch }`), and a spec that says nothing gets the
  // right answer instead of a surprise. Spelled here rather than
  // imported so the config stays free of the tests' module graph.
  expect: { timeout: 15_000 },
  forbidOnly: !!process.env.CI,
  retries,
  // A quarantined test is one the suite has stopped believing and has
  // not yet fixed; it keeps running in the soak, where its failures are
  // information rather than a red PR. Every `@quarantine` tag owes a
  // docs/deferred-work.md entry in the same commit, so the exclusion is
  // a tracked debt rather than a place things go to be forgotten.
  grepInvert: process.env.E2E_QUARANTINE === 'include' ? undefined : /@quarantine/,
  // The JSON report is what the CI job walks to annotate flaky tests; it
  // lands under test-results/ so the artifact upload carries it next to
  // the traces and hang evidence that explain them.
  reporter: process.env.CI
    ? [
        ['list'],
        ['html', { open: 'never' }],
        ['json', { outputFile: 'test-results/report.json' }],
      ]
    : 'list',
  use: {
    baseURL,
    // Kept on failure rather than on first retry: local runs do not
    // retry, so a flake that shows up once in a dozen runs would
    // otherwise leave nothing behind to diagnose it with.
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    // The full Chromium in its new headless mode, not the old
    // chrome-headless-shell that Playwright reaches for by default.
    // The web build is wasm (skwasm rasterizes in a dedicated worker
    // behind SharedArrayBuffer), and the shell segfaults on it: the
    // kernel log records signal 11 in `chrome-headless` and
    // `DedicatedWorker` threads, which surfaces as an unexplained
    // "Page crashed" in whichever spec happened to be logging in. The
    // full binary is also what people actually run.
    channel: 'chromium',
    // The playback specs stream real audio for as long as their fixtures
    // last, and on a workstation that comes out of the speakers. Nothing
    // in the suite asserts audible sound - playback is checked through
    // positions and the server's own play accounting - so the browser is
    // muted and the suite is safe to run anywhere.
    launchOptions: { args: ['--mute-audio'] },
  },
  projects: [
    // First-run setup runs alone before everything else: it drives the
    // one-shot bootstrap wizard every other spec assumes has happened.
    {
      name: 'setup',
      testMatch: /first-run\.spec\.ts/,
      ...motion('reduce'),
    },
    // Every blocking project asks the browser for reduced motion, which
    // Flutter 3.44's web engine reads as AccessibilityFeatures
    // .disableAnimations: route transitions, sheets and every default
    // AnimationController collapse to 5% of their duration, and
    // WaxMotion.of hands widgets its `reduced` token set. That removes
    // the whole class of failure where a click lands on a rect that is
    // still moving. It is the browser's real accessibility channel, not
    // a test seam - a listener who asks for reduced motion gets exactly
    // this app.
    {
      name: 'chromium',
      testIgnore: [
        /first-run\.spec\.ts/,
        /editing-prototype\.spec\.ts/,
        /a11y-audit\.spec\.ts/,
        /radio-cast\.spec\.ts/,
      ],
      dependencies: ['setup'],
      ...motion('reduce'),
    },
    // The two specs that write the preference document, kept off each
    // other. `PUT /users/me/prefs` replaces the whole document and every
    // writer builds its body from a snapshot it read earlier, so two of
    // them in flight is last-writer-wins over fields neither meant to
    // touch - settings.spec.ts says so and keeps to keys nobody else
    // reads, which is not enough, because the clobbering is per document
    // and not per key. The symptom was radio-cast pinning a station and
    // watching the dial disappear under a settings write. Settings keeps
    // the parallel wave (it is the only writer left in it) and radio
    // runs after.
    {
      name: 'prefs-radio',
      testMatch: /radio-cast\.spec\.ts/,
      dependencies: ['chromium'],
      ...motion('reduce'),
    },
    // Focus-sensitive specs run after the parallel wave, one at a
    // time (projects chain through dependencies): text selection,
    // clipboard, native context menus, and the semantics walk all
    // lose OS focus to sibling workers' pages and flake.
    {
      name: 'focus-a11y',
      testMatch: /a11y-audit\.spec\.ts/,
      dependencies: ['prefs-radio'],
      ...motion('reduce'),
    },
    {
      name: 'focus-editing',
      testMatch: /editing-prototype\.spec\.ts/,
      dependencies: ['focus-a11y'],
      ...motion('reduce'),
    },
    // Animated paths stay covered. Everything above runs the app with
    // motion switched off, so the transitions, the deck expanding, and
    // the sheets sliding are code no blocking project exercises any
    // more. This re-runs the walking skeleton - the one spec that logs
    // in through the form, walks the chrome and plays a track - with
    // motion on, last, where a failure is unambiguous: the app is
    // broken when it animates. Roughly a minute on the tail of the
    // suite, and no second copy of the journey to keep in step.
    {
      name: 'motion-smoke',
      // Anchored both ends: a bare /ui\.spec\.ts/ is a substring match
      // over the whole path and picks up signup-ui.spec.ts too.
      testMatch: /[\\/]ui\.spec\.ts$/,
      dependencies: ['focus-editing'],
      ...motion('no-preference'),
    },
  ],
  // run-stack.sh synthesizes the fixture library, starts the WaxFlow
  // streaming sidecar, and execs the server binary built with the embedded
  // web UI (`make web build`, or CI's equivalent); the server scans the
  // fixture library at startup. In CI, always start a fresh stack and fail
  // if the port is already taken, so tests never silently run against a
  // foreign process. Locally, reuse a dev-run stack (or a WAXDECK_BASE_URL
  // target) if one is present.
  webServer: external ? undefined : {
    command: './run-stack.sh',
    url: `${baseURL}/api/v1/health`,
    reuseExistingServer: !process.env.CI,
    timeout: 120_000,
  },
});

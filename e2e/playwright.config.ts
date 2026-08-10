import { defineConfig, devices } from '@playwright/test';

// Point at an already-running stack with WAXDECK_BASE_URL (the compose-based
// harness comes later); by default we launch the locally built binaries.
const baseURL = process.env.WAXDECK_BASE_URL ?? 'http://localhost:4420';
const external = !!process.env.WAXDECK_BASE_URL;

// The rootless second server the first-run wizard journey drives
// (run-wizard-stack.sh). The main stack boots with the fixture library
// configured, so the wizard's entry condition - an administrator whose
// server has no libraries - can never hold there. Local only: an
// external target is one server at one URL, so the wizard project does
// not exist on external runs.
const wizardBaseURL = 'http://localhost:4430';

// Retries hide flakes, so the two runs that are supposed to find them get
// none: E2E_RETRIES=0 is what the soak workflow and a local repeat-each
// run set. CI keeps one, not the two it used to: a test that needs three
// attempts is a quarantine candidate, not a pass.
// Parsed rather than coerced: `Number('')` is 0 and `Number('x')` is
// NaN, and Playwright reads both as "no retries" - so a workflow that
// sets E2E_RETRIES from an input nobody filled in, or a typo, silently
// turns CI's one retry off and reports flakes as failures. Only an
// actual integer counts as having asked.
const askedRetries = Number(process.env.E2E_RETRIES);
const retries = Number.isInteger(askedRetries) && askedRetries >= 0
  ? askedRetries
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
    //
    // The wave is everything that owns its own state. Every test in it
    // holds an account minted from its own title, so nothing
    // here shares a queue, a star, a position or a preference document
    // with anything else - which is what lets it stay fully parallel
    // with no serial groups inside it. `prefs-radio` used to sit between
    // this and the focus projects, because settings and radio both
    // replace the whole preference document and the clobbering is per
    // document rather than per key; two accounts is two documents, so it
    // is gone.
    {
      name: 'wave',
      testIgnore: [
        /first-run\.spec\.ts/,
        /admin-wizard\.spec\.ts/,
        /uploads\.spec\.ts/,
        /admin-ops\.spec\.ts/,
        /editing-prototype\.spec\.ts/,
        /a11y-audit\.spec\.ts/,
      ],
      dependencies: ['setup'],
      ...motion('reduce'),
    },
    // The wizard journey runs against its own rootless server, so it
    // depends on nothing here and nothing here depends on it: the two
    // stacks share no state, and the only account it touches is the
    // administrator it creates on its own installation.
    ...(external
      ? []
      : [
          {
            name: 'wizard',
            testMatch: /admin-wizard\.spec\.ts/,
            metadata: { motion: 'reduce' as const },
            use: { ...motion('reduce').use, baseURL: wizardBaseURL },
          },
        ]),
    // The catalog mutators, which per-test accounts cannot divide: the
    // files on disk, the mutation lease, the trash, the library table
    // and the admin settings row are one installation's, however many
    // accounts are looking at them.
    //
    // Uploads first, then the admin console, and the order is the point:
    // admin-ops flips the read-only switch, which refuses every upload
    // server-wide while it is on. With the two projects chained, that
    // window cannot overlap an upload - the deferred-work entry that
    // used to describe this hazard is closed by the ordering.
    {
      name: 'mutators-uploads',
      testMatch: /uploads\.spec\.ts/,
      dependencies: ['wave'],
      ...motion('reduce'),
    },
    // Not parallel with itself, for two reasons, and the second is the
    // one that decides it. Two tests here read the whole settings
    // object, change one field and put it back, and the endpoint stores
    // each field as its own row - so concurrent replaces interleave and
    // drop each other's change. A `describe.serial` around that pair
    // would answer that much.
    //
    // It would not answer the rest. One of the pair turns SERVER-WIDE
    // read-only on for the length of its body, and read-only refuses
    // every write on the stack with a 409 - the trash round trip's
    // `/library/items/delete`, the uploads, the runtime library. That is
    // the same global switch the chaining above exists to keep off the
    // uploads project, seen from inside the file. Serializing two tests
    // against each other does nothing about a switch one of them holds
    // while the other five run.
    //
    // So this is one worker in order. Giving the idle workers back means
    // making the read-only test stop being global - its own project, or
    // a per-library flag - not rescheduling around it.
    {
      name: 'mutators-admin',
      testMatch: /admin-ops\.spec\.ts/,
      dependencies: ['mutators-uploads'],
      fullyParallel: false,
      ...motion('reduce'),
    },
    // Animated paths stay covered, and this sits BEFORE the focus
    // projects rather than at the very end. Playwright skips a project
    // whose dependency had failures, and the focus projects are where
    // the quarantined test lives - so with this last, one test the suite
    // has already stopped believing would take the only unreduced
    // coverage in the run down with it, in the soak especially, where
    // quarantine is included on purpose.
    //
    // It still may not run beside `wave`: both match ui.spec.ts, and two
    // copies of one test at once is the aliasing the account model
    // removes. The
    // account key names the project now, so that is belt and braces
    // rather than the only thing holding it.
    {
      name: 'motion-smoke',
      // Anchored both ends: a bare /ui\.spec\.ts/ is a substring match
      // over the whole path and picks up signup-ui.spec.ts too.
      testMatch: /[\\/]ui\.spec\.ts$/,
      dependencies: ['mutators-admin'],
      ...motion('no-preference'),
    },
    // Focus-sensitive specs run last, one at a time (projects chain
    // through dependencies): text selection, clipboard, native context
    // menus, and the semantics walk all lose OS focus to sibling
    // workers' pages and flake. Last also means a quarantined failure
    // here costs no other project its run.
    {
      name: 'focus-a11y',
      testMatch: /a11y-audit\.spec\.ts/,
      dependencies: ['motion-smoke'],
      ...motion('reduce'),
    },
    {
      name: 'focus-editing',
      testMatch: /editing-prototype\.spec\.ts/,
      dependencies: ['focus-a11y'],
      ...motion('reduce'),
    },
  ],
  // run-stack.sh synthesizes the fixture library, starts the WaxFlow
  // streaming sidecar, and execs the server binary built with the embedded
  // web UI (`make web build`, or CI's equivalent); the server scans the
  // fixture library at startup. In CI, always start a fresh stack and fail
  // if the port is already taken, so tests never silently run against a
  // foreign process. Locally, reuse a dev-run stack (or a WAXDECK_BASE_URL
  // target) if one is present.
  webServer: external ? undefined : [
    {
      command: './run-stack.sh',
      url: `${baseURL}/api/v1/health`,
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
    },
    // The wizard's rootless server: the same binary over an empty data
    // dir, no sidecar, no roots (see run-wizard-stack.sh).
    //
    // Never reused, unlike the main stack. This one is single-use by
    // construction: its spec walks a door that closes behind it, so a
    // server somebody already bootstrapped makes the one test the
    // stack exists for skip itself. Failing on a busy port is the
    // louder and more useful answer.
    {
      command: './run-wizard-stack.sh',
      url: `${wizardBaseURL}/api/v1/health`,
      reuseExistingServer: false,
      timeout: 120_000,
    },
  ],
});

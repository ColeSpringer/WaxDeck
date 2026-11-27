import { defineConfig, devices } from '@playwright/test';
import { existsSync } from 'node:fs';

// WAXDECK_BASE_URL points at an already-running stack; by default we
// launch the locally built binaries.
const baseURL = process.env.WAXDECK_BASE_URL ?? 'http://localhost:4420';
const external = !!process.env.WAXDECK_BASE_URL;

// Windows spawns webServer commands through cmd.exe, which cannot exec a
// shebang script; name Git's bash explicitly (bare `bash` on PATH is WSL's).
const bash = (() => {
  if (process.platform !== 'win32') return 'bash';
  const candidates = [
    process.env.WAXDECK_GIT_BASH,
    'C:/Program Files/Git/bin/bash.exe',
    process.env.LOCALAPPDATA && `${process.env.LOCALAPPDATA}/Programs/Git/bin/bash.exe`,
  ].filter((p): p is string => !!p);
  const found = candidates.find((p) => existsSync(p));
  if (!found && !external) {
    throw new Error('Git bash not found; set WAXDECK_GIT_BASH to <Git>/bin/bash.exe');
  }
  return found ?? 'bash';
})();

// The rootless second server the wizard journey drives: the main stack
// boots with libraries configured, so the wizard's entry condition can
// never hold there.
const wizardBaseURL = 'http://localhost:4430';

// E2E_RETRIES=0 is the flake-hunting runs' setting; CI keeps one retry.
// Validated as an integer because Playwright reads '' and NaN as "no
// retries", which would silently disarm CI's retry.
const askedRetries = Number(process.env.E2E_RETRIES);
const retries = Number.isInteger(askedRetries) && askedRetries >= 0
  ? askedRetries
  : process.env.CI
    ? 1
    : 0;

// A Chromium project's browser and motion mode in one place; `metadata`
// is what the canary in fixtures.ts reads. contextOptions is replaced
// whole, not merged, which is why the mode is spread from here instead
// of written per project.
const motion = (mode: 'reduce' | 'no-preference') => ({
  metadata: { motion: mode },
  use: {
    ...devices['Desktop Chrome'],
    // Full Chromium, not the default chrome-headless-shell: the shell
    // segfaults on the wasm build (signal 11 in its skwasm worker),
    // surfacing as an unexplained "Page crashed".
    channel: 'chromium',
    // Playback specs stream real audio; nothing asserts audible sound,
    // so mute keeps the suite runnable on a workstation.
    launchOptions: { args: ['--mute-audio'] },
    contextOptions: { reducedMotion: mode },
  },
});

// WebKit and Firefox. Their system libraries are not on every machine, so
// they join on request: WAXDECK_E2E_ENGINES=webkit,firefox, as CI's
// engines job sets it. WAXDECK_E2E_BROWSER_SERVER launches them in a
// `playwright run-server` that has the libraries instead; its browsers
// reach this machine's stack through the connection.
const engineDevices = { webkit: 'Desktop Safari', firefox: 'Desktop Firefox' } as const;
const engines = (process.env.WAXDECK_E2E_ENGINES ?? '')
  .split(',')
  .map((name) => name.trim())
  .filter((name) => name !== '')
  .map((name) => {
    if (!Object.hasOwn(engineDevices, name)) {
      throw new Error(`WAXDECK_E2E_ENGINES: no engine named ${name}`);
    }
    return name as keyof typeof engineDevices;
  });
const browserServer = process.env.WAXDECK_E2E_BROWSER_SERVER;
// Headless Firefox has no WebGL without a GPU, and skwasm needs it, so
// the loader would hand it the JavaScript build. Set to 1 or true, this
// runs Firefox headed instead, on a display the caller provides: xvfb-run
// in CI, never a desktop's own. Anything else leaves it headless.
const firefoxHeaded = ['1', 'true'].includes(process.env.WAXDECK_E2E_FIREFOX_HEADED ?? '');

// The journeys that say whether an engine runs WaxDeck at all.
const crossEngine =
  /[\\/](engines|ui|driver-smoke|fonts|url-strategy|music-search|prose)\.spec\.ts$/;

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  // Streaming and focus-sensitive specs both flake with more concurrency.
  workers: 4,
  // A spec boots the real Flutter client against the real stack; 30s is a
  // page-speed budget, not a stack-speed one.
  timeout: 120_000,
  // The assert tier from tests/driver/budgets.ts, spelled here so the
  // config stays out of the tests' module graph.
  expect: { timeout: 15_000 },
  forbidOnly: !!process.env.CI,
  retries,
  // Quarantined tests run only in the soak; every @quarantine tag owes a
  // docs/deferred-work.md entry in the same commit.
  grepInvert: process.env.E2E_QUARANTINE === 'include' ? undefined : /@quarantine/,
  // The JSON report is what CI walks to annotate flaky tests; under
  // test-results/ so the artifact upload carries it beside the traces.
  // No `github` reporter: it annotates a test that passed on retry as
  // an error, so a green run would show red. tools/flaky-summary.mjs
  // reads the JSON report instead and annotates failures as errors and
  // retries as warnings.
  reporter: process.env.CI
    ? [
        ['list'],
        ['html', { open: 'never' }],
        ['json', { outputFile: 'test-results/report.json' }],
      ]
    : 'list',
  // A run that stalls ends here with its reports written - the JSON one
  // names the tests that were live - rather than at the job's cap with
  // nothing. Four times a green run.
  globalTimeout: process.env.CI ? 20 * 60_000 : 0,
  // The server answers /health before its streaming engine connects;
  // the run starts once it has.
  globalSetup: './tests/support/engine-ready.ts',
  use: {
    baseURL,
    // The suite reads English: role-and-name lookups, copy assertions,
    // durations spelled out in words. The app takes its locale from the
    // browser now, so without this a runner whose desktop is Spanish
    // gets a Spanish UI and every one of those lookups misses.
    locale: 'en-US',
    // On failure, not first retry: local runs never retry, and a flake
    // would otherwise leave nothing to diagnose.
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    // Runs alone first: the one-shot bootstrap every other spec assumes.
    {
      name: 'setup',
      testMatch: /first-run\.spec\.ts/,
      ...motion('reduce'),
    },
    // Reduced motion is the browser's real accessibility channel: Flutter
    // collapses animations, so clicks stop landing on moving rects.
    // The wave is everything that owns its own state - per-test accounts
    // share nothing, which is what lets it stay fully parallel.
    {
      name: 'wave',
      testIgnore: [
        /first-run\.spec\.ts/,
        /admin-wizard\.spec\.ts/,
        /playlist-sync\.spec\.ts/,
        /uploads\.spec\.ts/,
        /admin-ops\.spec\.ts/,
        /catalog-jobs\.spec\.ts/,
        /admin-readonly\.spec\.ts/,
        /engine-outage\.spec\.ts/,
        /a11y-audit\.spec\.ts/,
        /feishin\.spec\.ts/,
        /identity-dex\.spec\.ts/,
      ],
      dependencies: ['setup'],
      ...motion('reduce'),
    },
    // Runs against its own rootless server; the two stacks share no state.
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
    // Catalog mutators, which per-test accounts cannot divide. Uploads
    // before admin-ops on purpose: admin-ops flips server-wide read-only,
    // and the chain keeps that window from overlapping an upload.
    // Playlist sync heads the chain: its downloads land tracks, albums,
    // an artist, and review entries in the shared catalog, which a
    // concurrent wave spec would watch appear mid-assertion.
    {
      name: 'mutators-playlist-sync',
      testMatch: /playlist-sync\.spec\.ts/,
      dependencies: ['wave'],
      ...motion('reduce'),
    },
    {
      name: 'mutators-uploads',
      testMatch: /uploads\.spec\.ts/,
      dependencies: ['mutators-playlist-sync'],
      ...motion('reduce'),
    },
    // The admin console's global surfaces; parallel with itself, with a
    // describe.serial around each pair sharing a server-wide surface (the
    // backup set; the catalog check and its repair).
    {
      name: 'mutators-admin',
      testMatch: /admin-ops\.spec\.ts/,
      dependencies: ['mutators-uploads'],
      ...motion('reduce'),
    },
    // The catalog's jobs and health fixes: a scan and an enrichment pass
    // each hold a lease the whole stack shares, and a sweep request is
    // server-wide, so the file runs serially after the admin surfaces.
    {
      name: 'mutators-jobs',
      testMatch: /catalog-jobs\.spec\.ts/,
      dependencies: ['mutators-admin'],
      ...motion('reduce'),
    },
    // Server-wide read-only, alone on the stack: the global switch's cost
    // paid once instead of charged to every test sharing its file.
    {
      name: 'mutators-readonly',
      testMatch: /admin-readonly\.spec\.ts/,
      dependencies: ['mutators-jobs'],
      ...motion('reduce'),
    },
    // The streaming engine stopped and continued under the whole stack:
    // nothing else may be streaming through it while it is away.
    {
      name: 'mutators-engine',
      testMatch: /engine-outage\.spec\.ts/,
      dependencies: ['mutators-readonly'],
      ...motion('reduce'),
    },
    // Unreduced-motion coverage. Before the focus projects: those are the
    // flake-prone tail, and a skipped dependency would take this run's
    // only unreduced pass down with it. Not beside wave: both match
    // ui.spec.ts, and one test running twice at once aliases.
    {
      name: 'motion-smoke',
      // Anchored both ends or it also matches signup-ui.spec.ts.
      testMatch: /[\\/]ui\.spec\.ts$/,
      dependencies: ['mutators-engine'],
      ...motion('no-preference'),
    },
    // Focus-sensitive specs run last, one at a time: they lose OS focus
    // to sibling workers' pages and flake.
    {
      name: 'focus-a11y',
      testMatch: /a11y-audit\.spec\.ts/,
      dependencies: ['motion-smoke'],
      ...motion('reduce'),
    },
    // Reduced motion, like every blocking project. Neither engine has a
    // mute switch like Chromium's, and neither plays without an audio
    // output: they get the PulseAudio server WAXDECK_E2E_PULSE_SERVER
    // names, CI's null sink, and none otherwise, which fails the playback
    // journeys but keeps a desktop silent. PipeWire, ALSA and JACK, where
    // GStreamer turns next, are closed to them too, and Firefox's volume is
    // zeroed besides. A browser server takes none of this (it keeps its own
    // environment, and drops the preference unless started with --unsafe).
    ...engines.map((name) => ({
      name,
      testMatch: crossEngine,
      dependencies: ['setup'],
      metadata: { motion: 'reduce' as const },
      use: {
        ...devices[engineDevices[name]],
        // The scale every other project draws at; Desktop Safari's is 2,
        // four times the pixels for WebKit to hold.
        deviceScaleFactor: 1,
        contextOptions: { reducedMotion: 'reduce' as const },
        ...(name === 'firefox' && firefoxHeaded ? { headless: false } : {}),
        launchOptions: {
          ...(browserServer
            ? {}
            : {
                env: {
                  ...process.env,
                  PULSE_SERVER:
                    process.env.WAXDECK_E2E_PULSE_SERVER || 'unix:/nonexistent/wax-e2e-muted',
                  PIPEWIRE_REMOTE: 'wax-e2e-muted',
                  ALSA_CONFIG_PATH: '/dev/null',
                  JACK_DEFAULT_SERVER: 'wax-e2e-muted',
                  JACK_NO_START_SERVER: '1',
                } as Record<string, string>,
              }),
          ...(name === 'firefox' ? { firefoxUserPrefs: { 'media.volume_scale': '0.0' } } : {}),
        },
        ...(browserServer
          ? { connectOptions: { wsEndpoint: browserServer, exposeNetwork: '<loopback>' } }
          : {}),
      },
    })),
    // The real third-party client; present only when FEISHIN_BASE_URL
    // names its container. Depends on setup so its bootstrap cannot race
    // the wizard's into a 409.
    ...(process.env.FEISHIN_BASE_URL
      ? [
          {
            name: 'feishin',
            testMatch: /feishin\.spec\.ts/,
            dependencies: ['setup'],
            ...motion('reduce'),
          },
        ]
      : []),
    // SSO against a real dex; run-sso-dex.sh brings the container up
    // before invoking this project by name.
    ...(process.env.WAXDECK_DEX_SSO
      ? [
          {
            name: 'sso-dex',
            testMatch: /identity-dex\.spec\.ts/,
            dependencies: ['setup'],
            ...motion('reduce'),
          },
        ]
      : []),
  ],
  // run-stack.sh synthesizes fixtures, starts the sidecar, and execs the
  // prebuilt server. CI never reuses a running stack, so tests cannot
  // silently run against a foreign process; local runs may.
  webServer: external ? undefined : [
    {
      command: `"${bash}" run-stack.sh`,
      url: `${baseURL}/api/v1/health`,
      reuseExistingServer: !process.env.CI,
      timeout: 120_000,
      // Stopped with SIGTERM rather than killed: run-stack.sh traps it,
      // removes the sidecar pid file the engine-outage spec signals by,
      // and the server and sidecar shut down cleanly; anything still up
      // after ten seconds is killed as before.
      gracefulShutdown: { signal: 'SIGTERM', timeout: 10_000 },
    },
    // The wizard's rootless server. Never reused: its spec walks a door
    // that closes behind it, so a bootstrapped leftover makes the one
    // test skip itself. Dropped for the dex run, which boots no wizard
    // spec but would still pay for (and maybe fail on) this port.
    ...(process.env.WAXDECK_DEX_SSO
      ? []
      : [
          {
            command: `"${bash}" run-wizard-stack.sh`,
            url: `${wizardBaseURL}/api/v1/health`,
            reuseExistingServer: false,
            timeout: 120_000,
          },
        ]),
  ],
});

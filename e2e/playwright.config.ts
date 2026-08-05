import { defineConfig, devices } from '@playwright/test';

// Point at an already-running stack with WAXDECK_BASE_URL (the compose-based
// harness comes later); by default we launch the locally built binaries.
const baseURL = process.env.WAXDECK_BASE_URL ?? 'http://localhost:4420';
const external = !!process.env.WAXDECK_BASE_URL;

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
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
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
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'chromium',
      testIgnore: [
        /first-run\.spec\.ts/,
        /editing-prototype\.spec\.ts/,
        /a11y-audit\.spec\.ts/,
        /radio-cast\.spec\.ts/,
      ],
      dependencies: ['setup'],
      use: { ...devices['Desktop Chrome'] },
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
      use: { ...devices['Desktop Chrome'] },
    },
    // Focus-sensitive specs run after the parallel wave, one at a
    // time (projects chain through dependencies): text selection,
    // clipboard, native context menus, and the semantics walk all
    // lose OS focus to sibling workers' pages and flake.
    {
      name: 'focus-a11y',
      testMatch: /a11y-audit\.spec\.ts/,
      dependencies: ['prefs-radio'],
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'focus-editing',
      testMatch: /editing-prototype\.spec\.ts/,
      dependencies: ['focus-a11y'],
      use: { ...devices['Desktop Chrome'] },
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

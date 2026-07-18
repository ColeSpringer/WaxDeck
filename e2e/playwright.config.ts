import { defineConfig, devices } from '@playwright/test';

// Point at an already-running stack with WAXDECK_BASE_URL (the compose-based
// harness comes later); by default we launch the locally built binaries.
const baseURL = process.env.WAXDECK_BASE_URL ?? 'http://localhost:4420';
const external = !!process.env.WAXDECK_BASE_URL;

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? [['list'], ['html', { open: 'never' }]] : 'list',
  use: {
    baseURL,
    trace: 'on-first-retry',
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
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

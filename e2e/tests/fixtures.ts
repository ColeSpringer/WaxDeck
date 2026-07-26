import { test as base } from '@playwright/test';
import { attachBuffers, captureHangEvidence, HEARTBEAT_INIT } from './hangprobe';

export * from '@playwright/test';

// Specs import { test, expect } from './fixtures' instead of
// '@playwright/test': the page every test receives carries a rAF
// heartbeat and buffered console/error listeners from birth, and a test
// that fails or times out dumps hang evidence (thread states, worker
// responsiveness, compositor liveness) next to its trace before the
// context closes. Purpose and format: tests/hangprobe.ts and the
// renderer-hang entry in docs/deferred-work.md.
// The app ships skwasm single-threaded until flutter/flutter#190039 is
// fixed (see web/index.html). WAXDECK_E2E_MT_SKWASM=1 rewrites the
// served page to turn multi-threading back on for the run, which is
// how a new engine gets re-tested against the heap race without
// touching the app; expect the old hang rate if the bug is still
// there.
const forceMtSkwasm = !!process.env.WAXDECK_E2E_MT_SKWASM;

export const test = base.extend({
  page: async ({ page }, use, testInfo) => {
    // Not in the perf spec: a self-rescheduling rAF loop requests a
    // frame every frame, defeating idle throttling and adding a
    // callback to each frame whose pacing that spec exists to measure.
    if (!testInfo.file.endsWith('perf-web.spec.ts')) {
      await page.addInitScript(HEARTBEAT_INIT);
    }
    if (forceMtSkwasm) {
      await page.route('**/*', async (route) => {
        if (route.request().resourceType() !== 'document') return route.fallback();
        const resp = await route.fetch();
        const body = (await resp.text()).replace(
          'forceSingleThreadedSkwasm: true',
          'forceSingleThreadedSkwasm: false',
        );
        await route.fulfill({ response: resp, body });
      });
    }
    const buffers = attachBuffers(page);
    await use(page);
    if (testInfo.status === 'timedOut' || testInfo.status === 'failed') {
      // Bounded as a whole: teardown shares the test's grace budget,
      // and a wedged probe must not eat the trace teardown behind it.
      await Promise.race([
        captureHangEvidence(page, testInfo, buffers).catch((e) =>
          console.log(`hangprobe failed: ${e}`),
        ),
        new Promise((resolve) => setTimeout(resolve, 25_000)),
      ]);
    }
  },
});

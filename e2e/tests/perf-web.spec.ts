import { test, expect } from '@playwright/test';
import { typeInto } from './helpers';
import { SemanticsIds } from './semantics-ids';

// The web half of the large-library gate, run on demand against a
// server holding the synthesized 100k-item corpus:
//
//   PERF_BASE_URL=http://localhost:4431 npx playwright test perf-web
//
// Measures cold and warm time-to-interactive (the login form is the
// first interactive surface), time from login to a populated grid over
// 100k items, and frame pacing while scrolling the grid through
// load-more churn. Budgets are the pre-agreed gate criteria; measured
// values print for the record either way.
const base = process.env.PERF_BASE_URL ?? '';

const budgets = {
  coldTtiMs: 5000,
  warmTtiMs: 2500,
  gridMs: 2500,
  minMeanFps: 40,
  maxLongFrameShare: 0.05,
};

test.describe('large-library web gate', () => {
  test.skip(!base, 'set PERF_BASE_URL to run the perf gate');
  test.setTimeout(600_000);

  test('cold TTI, warm TTI, grid time, and scroll pacing', async ({
    browser,
    playwright,
  }) => {
    // The corpus scan is asynchronous on a fresh stack; wait until a
    // deep corpus track is searchable before measuring anything.
    const api = await playwright.request.newContext({ baseURL: base });
    const boot = await api.post('/api/v1/auth/bootstrap', {
      data: { username: 'admin', password: 'wax-e2e-pass' },
    });
    let token: string;
    if (boot.ok()) {
      token = (await boot.json()).token;
    } else {
      const login = await api.post('/api/v1/auth/login', {
        data: { username: 'admin', password: 'wax-e2e-pass' },
      });
      expect(login.ok()).toBeTruthy();
      token = (await login.json()).token;
    }
    await expect
      .poll(
        async () => {
          const r = await api.get('/api/v1/library/search?q=Corpus', {
            headers: { Authorization: `Bearer ${token}` },
          });
          if (!r.ok()) return 0;
          return ((await r.json()).tracks ?? []).length;
        },
        { timeout: 300_000, intervals: [2_000] },
      )
      .toBeGreaterThan(0);

    // Cold: a pristine context, nothing cached.
    const context = await browser.newContext();
    const page = await context.newPage();
    const coldStart = Date.now();
    await page.goto(base + '/');
    const username = page.getByRole('textbox', { name: 'Username' });
    await username.waitFor({ timeout: 60_000 });
    const coldTti = Date.now() - coldStart;

    // Warm: same context, assets in cache.
    const warmStart = Date.now();
    await page.reload();
    await page
      .getByRole('textbox', { name: 'Username' })
      .waitFor({ timeout: 60_000 });
    const warmTti = Date.now() - warmStart;

    // Login, then time to a populated grid over the 100k catalog.
    await typeInto(page, page.getByRole('textbox', { name: 'Username' }), 'admin');
    await typeInto(page, page.getByRole('textbox', { name: 'Password' }), 'wax-e2e-pass');
    const gridStart = Date.now();
    await page.getByRole('button', { name: 'Log in' }).click();
    await page
      .locator(`[flt-semantics-identifier^="${SemanticsIds.item('')}"]`)
      .first()
      .waitFor({ timeout: 60_000 });
    const gridMs = Date.now() - gridStart;

    // Scroll pacing: collect frame deltas while wheeling through the
    // grid (which pages more items in as it goes).
    await page.evaluate(() => {
      const w = window as unknown as { __frames: number[]; __stop: boolean };
      w.__frames = [];
      w.__stop = false;
      let last = performance.now();
      const tick = (now: number) => {
        w.__frames.push(now - last);
        last = now;
        if (!w.__stop) requestAnimationFrame(tick);
      };
      requestAnimationFrame(tick);
    });
    const viewport = page.viewportSize()!;
    await page.mouse.move(viewport.width / 2, viewport.height / 2);
    for (let i = 0; i < 120; i++) {
      await page.mouse.wheel(0, 600);
      await page.waitForTimeout(100);
    }
    const frames: number[] = await page.evaluate(() => {
      const w = window as unknown as { __frames: number[]; __stop: boolean };
      w.__stop = true;
      return w.__frames;
    });

    const settled = frames.slice(5); // discard collector warm-up
    const meanMs = settled.reduce((a, b) => a + b, 0) / settled.length;
    const sorted = [...settled].sort((a, b) => a - b);
    const p95 = sorted[Math.floor(sorted.length * 0.95)];
    const longShare = settled.filter((f) => f > 50).length / settled.length;

    console.log(`perf-web verdicts against ${base}`);
    console.log(`  cold TTI        ${coldTti}ms (budget ${budgets.coldTtiMs}ms)`);
    console.log(`  warm TTI        ${warmTti}ms (budget ${budgets.warmTtiMs}ms)`);
    console.log(`  login->grid     ${gridMs}ms (budget ${budgets.gridMs}ms)`);
    console.log(
      `  scroll frames   mean ${meanMs.toFixed(1)}ms (${(1000 / meanMs).toFixed(0)}fps), p95 ${p95.toFixed(1)}ms, >50ms share ${(longShare * 100).toFixed(1)}%`,
    );

    expect(coldTti).toBeLessThanOrEqual(budgets.coldTtiMs);
    expect(warmTti).toBeLessThanOrEqual(budgets.warmTtiMs);
    expect(gridMs).toBeLessThanOrEqual(budgets.gridMs);
    expect(1000 / meanMs).toBeGreaterThanOrEqual(budgets.minMeanFps);
    expect(longShare).toBeLessThanOrEqual(budgets.maxLongFrameShare);

    await context.close();
  });
});

import { test, expect, APIRequestContext, Browser, Locator, Page } from './fixtures';
import { clickThrough, typeInto } from './driver/gestures';
import { measureScrollPacing, reportScrollPacing, ScrollPacing } from './support/scroll-pacing';
import { SemanticsIds, SemanticsIdPrefixes, sem, semPrefix } from './semantics-ids';

// The web half of the large-library gate, run on demand against a
// server holding the synthesized 100k-item corpus:
//
//   PERF_BASE_URL=http://localhost:4431 npx playwright test perf-web
//
// Measures cold and warm time-to-interactive (the login form is the
// first interactive surface), time from login to a populated grid over
// 100k items, and frame pacing while scrolling - the library grid, the
// music indexes and a bucket listing, and the grid again with a track
// playing. Budgets are the pre-agreed gate criteria; measured values
// print for the record either way.
//
// The corpus must be built with covers, which is corpusgen's default.
// The indexes and the grid are artwork surfaces, and measuring them over
// a library with no art is what made the first recorded run
// unrepresentative. `corpusgen -covers=false` builds the other half of
// that comparison when one is wanted.
const base = process.env.PERF_BASE_URL ?? '';

const budgets = {
  coldTtiMs: 5000,
  warmTtiMs: 2500,
  gridMs: 2500,
  minMeanFps: 40,
  maxLongFrameShare: 0.05,
};

const CORPUS_USER = 'admin';
const CORPUS_PASS = 'wax-e2e-pass';

// Any item row, whichever the tracks index drew first. Home is shelves
// now, so the surface that enumerates the whole catalog - the one whose
// paging this gate is about - is the tracks index.
const anyItemRow = (page: Page): Locator =>
  page.locator(semPrefix(SemanticsIdPrefixes.item)).first();

// The tracks index over the corpus. Reached by location rather than
// through the chrome where nothing is playing, which is every use but
// the playing-scroll scenario's second visit.
async function openTracks(page: Page): Promise<void> {
  await page.goto(base + '/music/tracks');
  await anyItemRow(page).waitFor({ timeout: 60_000 });
}

// The corpus scan is asynchronous on a fresh stack; nothing is worth
// measuring until a deep corpus track is searchable. Takes the factory
// rather than a live context so it owns what it opens: a scenario cannot
// leak the one it polls through.
async function waitForCorpus(
  newContext: () => Promise<APIRequestContext>,
): Promise<void> {
  const api = await newContext();
  try {
    const boot = await api.post('/api/v1/auth/bootstrap', {
      data: { username: CORPUS_USER, password: CORPUS_PASS },
    });
    let token: string;
    if (boot.ok()) {
      token = (await boot.json()).token;
    } else {
      const login = await api.post('/api/v1/auth/login', {
        data: { username: CORPUS_USER, password: CORPUS_PASS },
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
  } finally {
    await api.dispose();
  }
}

// Runs [body] against a pristine page and closes its context however it
// ends. A failing assertion would otherwise leak a browser context -
// invisible with one scenario in the file, three plus retries less so.
async function measuring(
  browser: Browser,
  body: (page: Page) => Promise<void>,
): Promise<void> {
  const context = await browser.newContext();
  try {
    await body(await context.newPage());
  } finally {
    await context.close();
  }
}

async function login(page: Page) {
  await page.goto(base + '/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 60_000 });
  await typeInto(page, username, CORPUS_USER);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), CORPUS_PASS);
  await page.getByRole('button', { name: 'Log in' }).click();
}

function expectPacing(label: string, pacing: ScrollPacing) {
  expect(pacing.fps, `${label}: mean fps`).toBeGreaterThanOrEqual(budgets.minMeanFps);
  expect(pacing.longFrameShare, `${label}: long-frame share`).toBeLessThanOrEqual(
    budgets.maxLongFrameShare,
  );
}

test.describe('large-library web gate', () => {
  test.skip(!base, 'set PERF_BASE_URL to run the perf gate');
  test.setTimeout(600_000);
  // The config is fullyParallel with four workers, which distributes
  // tests within a file. Three scenarios each wheel-scrolling a 100k
  // library for a quarter minute, run at once on one machine against one
  // server, would report the contention between them rather than the
  // app - and these numbers become the gate's recorded baseline. Default
  // mode runs them in order in one worker. Not serial mode: a scenario
  // that misses its budget must not skip the two after it, because which
  // surface missed is exactly what the miss policy turns on.
  test.describe.configure({ mode: 'default' });

  test('cold TTI, warm TTI, grid time, and scroll pacing', async ({
    browser,
    playwright,
  }) => {
    await waitForCorpus(() => playwright.request.newContext({ baseURL: base }));
    await measuring(browser, async (page) => {
      // Cold: a pristine context, nothing cached.
      const coldStart = Date.now();
      await page.goto(base + '/');
      await page.getByRole('textbox', { name: 'Username' }).waitFor({ timeout: 60_000 });
      const coldTti = Date.now() - coldStart;

      // Warm: same context, assets in cache.
      const warmStart = Date.now();
      await page.reload();
      await page.getByRole('textbox', { name: 'Username' }).waitFor({ timeout: 60_000 });
      const warmTti = Date.now() - warmStart;

      // Login, then time to a populated home over the 100k catalog:
      // eight shelves, each one a browse read, which is what a listener
      // now waits on before the app is usable.
      await typeInto(page, page.getByRole('textbox', { name: 'Username' }), CORPUS_USER);
      await typeInto(page, page.getByRole('textbox', { name: 'Password' }), CORPUS_PASS);
      const gridStart = Date.now();
      await page.getByRole('button', { name: 'Log in' }).click();
      await page
        .locator(sem(SemanticsIds.shelf('recent')))
        .waitFor({ timeout: 60_000 });
      const gridMs = Date.now() - gridStart;

      // Scroll pacing over the tracks index, which pages more items in
      // as it goes: the enumeration the library grid used to be.
      await openTracks(page);
      const pacing = await measureScrollPacing(page);

      console.log(`perf-web verdicts against ${base}`);
      console.log(`  cold TTI        ${coldTti}ms (budget ${budgets.coldTtiMs}ms)`);
      console.log(`  warm TTI        ${warmTti}ms (budget ${budgets.warmTtiMs}ms)`);
      console.log(`  login->home     ${gridMs}ms (budget ${budgets.gridMs}ms)`);
      reportScrollPacing('tracks scroll', pacing);

      expect(coldTti).toBeLessThanOrEqual(budgets.coldTtiMs);
      expect(warmTti).toBeLessThanOrEqual(budgets.warmTtiMs);
      expect(gridMs).toBeLessThanOrEqual(budgets.gridMs);
      expectPacing('tracks scroll', pacing);
    });
  });

  test('index and bucket scroll pacing', async ({ browser, playwright }) => {
    // The music surfaces, which the first recorded run never visited and
    // which the artwork negative cache changed. Artists first because it
    // is the index that draws no artwork by design: it is the cheap
    // case, and a miss there is not an artwork number.
    await waitForCorpus(() => playwright.request.newContext({ baseURL: base }));
    await measuring(browser, async (page) => {
      await login(page);
      await page.locator(sem(SemanticsIds.navDestination('music'))).waitFor({ timeout: 60_000 });

      console.log(`perf-web index verdicts against ${base}`);

      await page.goto(base + '/music/artists');
      await page.locator(sem(SemanticsIds.indexBucket(0))).waitFor({ timeout: 60_000 });
      const artists = await measureScrollPacing(page);
      reportScrollPacing('artist index', artists);

      // Albums are the same list shape carrying the artwork load the
      // artist index does not.
      await page.goto(base + '/music/albums');
      await page.locator(sem(SemanticsIds.indexBucket(0))).waitFor({ timeout: 60_000 });
      const albums = await measureScrollPacing(page);
      reportScrollPacing('album index', albums);

      // And a bucket listing: the drill-in from an index, which is a list
      // of items rather than of buckets.
      await clickThrough(
        page.locator(sem(SemanticsIds.indexBucket(0))),
        page.locator(sem(SemanticsIds.indexItem(0))),
      );
      const bucket = await measureScrollPacing(page);
      reportScrollPacing('bucket listing', bucket);

      expectPacing('artist index', artists);
      expectPacing('album index', albums);
      expectPacing('bucket listing', bucket);
    });
  });

  test('grid scroll pacing with a track playing', async ({
    browser,
    playwright,
  }) => {
    // Section 10.1 asks for the scroll scenario with playback running,
    // and it is not a redundant repeat: the deck bar repaints its
    // progress every frame the scroll is competing for, and on the web
    // build both land on the same raster thread.
    await waitForCorpus(() => playwright.request.newContext({ baseURL: base }));
    await measuring(browser, async (page) => {
      await login(page);
      // The chrome first, as the index scenarios do: `login` ends on the
      // click and awaits nothing, and `openTracks` navigates for real
      // since the path-URL flip - issued while the login POST is in
      // flight it cancels it, the app boots signed out, and this reads as
      // a blown perf budget rather than as a cancelled login.
      await page
        .locator(sem(SemanticsIds.navDestination('music')))
        .waitFor({ timeout: 60_000 });
      await openTracks(page);

      // Opening an item plays it and raises the deck bar. Play lands in
      // the dock, so the listing this scenario scrolls never leaves the
      // screen and there is nothing to navigate back from.
      await clickThrough(anyItemRow(page), page.locator(sem(SemanticsIds.deckBar)));
      await expect(page.locator(sem(SemanticsIds.deckBar))).toBeVisible({ timeout: 30_000 });

      const pacing = await measureScrollPacing(page);
      console.log(`perf-web playing-scroll verdict against ${base}`);
      reportScrollPacing('tracks + deck bar', pacing);
      expectPacing('tracks + deck bar', pacing);
    });
  });
});

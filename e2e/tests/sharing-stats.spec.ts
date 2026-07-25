import { test, expect, APIRequestContext, Page } from '@playwright/test';
import { authed, clickThrough, ensureAdmin, typeInto, waitForLibrary } from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// Listening stats and public share links over the real stack: sessions
// reported through the listen API surface in the stats screen and the
// year in review, and a share link's whole life from creation through
// anonymous playback to revocation.


// The stack's own origin, for request contexts created outside the
// test fixtures (mirrors playwright.config.ts).
const baseURL = process.env.WAXDECK_BASE_URL ?? 'http://localhost:4420';

async function login(page: Page) {
  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, 'admin');
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), 'wax-e2e-pass');
  await page.getByRole('button', { name: 'Log in' }).click();
  await page.locator(sem(SemanticsIds.playlistsOpen)).waitFor({ timeout: 30_000 });
}

async function trackPid(
  request: APIRequestContext,
  token: string,
  title: string,
): Promise<string> {
  const search = await (
    await request.get(
      `/api/v1/library/search?q=${encodeURIComponent(title)}`,
      authed(token),
    )
  ).json();
  const hit = (search.tracks as Array<{ pid: string; title: string }>).find(
    (t) => t.title === title,
  );
  expect(hit, `the fixture track "${title}" is indexed`).toBeTruthy();
  return hit!.pid;
}

test('reported listens surface in stats and the year in review', async ({
  page,
  request,
}) => {
  test.setTimeout(150_000);
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  const pid = await trackPid(request, token, 'Charlie Song');

  // Four sessions with distinct start times: one two-hour listen ten
  // days back (inside 30d, outside 7d, so the range switch visibly
  // changes the totals), three short recent ones, one carrying the
  // time-saved counter. Session ids are fixed so retries and reruns
  // against the same stack deduplicate instead of inflating totals.
  const now = Date.now();
  const hour = 3_600_000;
  const report = {
    sessions: [
      {
        sessionId: 'e2e-stats-backdated',
        pid,
        startedAt: new Date(now - 10 * 24 * hour).toISOString(),
        msPlayed: 2 * hour,
        finished: true,
      },
      {
        sessionId: 'e2e-stats-recent-a',
        pid,
        startedAt: new Date(now - 3 * hour).toISOString(),
        msPlayed: 120_000,
        finished: true,
      },
      {
        sessionId: 'e2e-stats-recent-b',
        pid,
        startedAt: new Date(now - 2 * hour).toISOString(),
        msPlayed: 120_000,
        skippedMs: 60_000,
        finished: true,
      },
      {
        sessionId: 'e2e-stats-recent-c',
        pid,
        startedAt: new Date(now - 1 * hour).toISOString(),
        msPlayed: 120_000,
        finished: true,
      },
    ],
  };
  const ingest = await request.post('/api/v1/listens', {
    ...authed(token),
    data: report,
  });
  expect(ingest.ok()).toBeTruthy();
  const outcome = await ingest.json();
  expect(outcome.accepted + outcome.duplicates).toBe(4);

  await login(page);
  await clickThrough(page.locator(sem(SemanticsIds.openStats)), page.locator(sem(SemanticsIds.statsRange('7d'))));

  // The default 30d view includes the backdated two-hour session, so
  // the listened headline reads in hours. Other specs' live playback
  // adds seconds at most and never moves the hour.
  // The stat tiles merge into one semantics span whose raw text joins
  // the segments with newlines, and Playwright regexes run against the
  // raw text, so separators match \s+ rather than a literal space.
  const hoursTotal = page.getByText(/\d+h \d+m\s+listened/);
  await expect(hoursTotal.first()).toBeVisible({ timeout: 15_000 });
  await expect(page.getByText(/\d+\s+sessions/).first()).toBeVisible();

  // Switching to 7d drops the backdated session: every hours-scale
  // figure leaves the screen and a minutes-scale total remains. The
  // click retries because a canvas click can be swallowed while
  // handlers attach.
  await expect(async () => {
    await page
      .locator(sem(SemanticsIds.statsRange('7d')))
      .click({ timeout: 2_000, force: true })
      .catch(() => {});
    await expect(hoursTotal).toHaveCount(0, { timeout: 3_000 });
  }).toPass({ timeout: 30_000 });
  await expect(page.getByText(/\d+m\s+listened/).first()).toBeVisible({
    timeout: 15_000,
  });

  // The recap door sits at the bottom of the stats list; wheel it into
  // the semantics tree first (offscreen rows are culled).
  const viewport = page.viewportSize()!;
  await page.mouse.move(viewport.width / 2, viewport.height / 2);
  await expect(async () => {
    await page.mouse.wheel(0, 1_200);
    await expect(page.locator(sem(SemanticsIds.openYearInReview))).toBeVisible({
      timeout: 1_000,
    });
  }).toPass({ timeout: 30_000 });

  // The year in review: this year renders with the same nonzero
  // totals (the year holds every reported session). Recap content
  // surfaces as merged text on some nodes and as a group's accessible
  // name on others, so matching accepts either rendering.
  const textOrLabel = (matcher: string | RegExp) =>
    page.getByText(matcher).or(page.getByLabel(matcher));
  await clickThrough(
    page.locator(sem(SemanticsIds.openYearInReview)),
    page.locator(sem(SemanticsIds.yirPersonal)),
  );
  const year = new Date().getFullYear();
  await expect(textOrLabel(`${year}`).first()).toBeVisible({
    timeout: 15_000,
  });
  await expect(textOrLabel(/\d+h \d+m\s+listened/).first()).toBeVisible({
    timeout: 15_000,
  });

  // The server-wide recap aggregates every enrolled listener; on this
  // stack that is the administrator alone.
  await clickThrough(
    page.locator(sem(SemanticsIds.yirServer)),
    textOrLabel('listeners counted in').first(),
  );
  await expect(
    textOrLabel(/\d+h \d+m\s+listened together/).first(),
  ).toBeVisible({ timeout: 15_000 });
});

test('a share link plays anonymously and dies on revocation', async ({
  request,
  playwright,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  const pid = await trackPid(request, token, 'Bravo Song');

  const created = await request.post('/api/v1/shares', {
    ...authed(token),
    data: { pid, allowDownload: false },
  });
  expect(created.status()).toBe(201);
  const share = await created.json();
  expect(share.pid).toMatch(/^sh-/);
  expect(share.url).toMatch(/^\/s\//);
  expect(share.allowDownload).toBe(false);

  // The capability URL works with no credentials at all: a fresh
  // request context, no cookies, no bearer.
  const anon = await playwright.request.newContext({ baseURL });
  try {
    const landing = await anon.get(share.url);
    expect(landing.status()).toBe(200);
    expect(landing.headers()['content-type']).toContain('text/html');
    const html = await landing.text();
    expect(html).toContain('og:title');
    expect(html).toContain('<audio');
    expect(html).toContain('Bravo Song');
    // No download offer on this link.
    expect(html).not.toContain('/download');

    const stream = await anon.get(`${share.url}/stream`);
    expect(stream.status()).toBe(200);
    expect(stream.headers()['content-type']).toMatch(/^audio\//);
    expect((await stream.body()).byteLength).toBeGreaterThan(1000);

    // A tampered token answers not-found, indistinguishable from a
    // dead link. The flipped character sits inside the signature,
    // clear of the base64 tail whose spare bits decode identically.
    const dot = share.url.lastIndexOf('.');
    const at = dot + 3;
    const tampered =
      share.url.slice(0, at) +
      (share.url[at] === 'A' ? 'B' : 'A') +
      share.url.slice(at + 1);
    expect(tampered).not.toBe(share.url);
    const forged = await anon.get(tampered);
    expect(forged.status()).toBe(404);

    // Revocation bites immediately.
    const revoked = await request.delete(`/api/v1/shares/${share.pid}`, authed(token));
    expect(revoked.status()).toBe(204);
    const gone = await anon.get(share.url);
    expect(gone.status()).toBe(404);
    expect(await gone.text()).toContain('revoked');
    const deadStream = await anon.get(`${share.url}/stream`);
    expect(deadStream.status()).toBe(404);
  } finally {
    await anon.dispose();
  }
});

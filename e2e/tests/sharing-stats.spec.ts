import { test, expect } from './fixtures';
import { J } from './driver';

// Listening stats and public share links over the real stack: sessions
// reported through the listen API surface in the stats screen and the
// year in review, and a share link's whole life from creation through
// anonymous playback to revocation.

test('reported listens surface in stats and the year in review', async ({ app }) => {
  test.setTimeout(J.long);
  const { pid } = await app.seed.item('Charlie Song');

  // Four sessions with distinct start times: one two-hour listen ten
  // days back (inside 30d, outside 7d, so the range switch visibly
  // changes the totals), three short recent ones, one carrying the
  // time-saved counter. Session ids are fixed so retries and reruns
  // against the same stack deduplicate instead of inflating totals -
  // and the account is this test's own, so the totals on screen are
  // these four sessions and nothing else.
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
        source: 'live' as const,
      },
      {
        sessionId: 'e2e-stats-recent-a',
        pid,
        startedAt: new Date(now - 3 * hour).toISOString(),
        msPlayed: 120_000,
        finished: true,
        source: 'live' as const,
      },
      {
        sessionId: 'e2e-stats-recent-b',
        pid,
        startedAt: new Date(now - 2 * hour).toISOString(),
        msPlayed: 120_000,
        skippedMs: 60_000,
        finished: true,
        source: 'live' as const,
      },
      {
        sessionId: 'e2e-stats-recent-c',
        pid,
        startedAt: new Date(now - 1 * hour).toISOString(),
        msPlayed: 120_000,
        finished: true,
        source: 'live' as const,
      },
    ],
  };
  const outcome = await app.api.post('/listens', { data: report });
  expect(outcome.accepted + outcome.duplicates).toBe(4);

  await app.nav.enter('stats');

  // The default 30d view includes the backdated two-hour session, so
  // the listened headline reads in hours.
  const hoursTotal = app.stats.figure(/\d+h \d+m\s+listened/);
  await expect(hoursTotal.first()).toBeVisible();
  await expect(app.stats.figure(/\d+\s+sessions/).first()).toBeVisible();

  // Switching to 7d drops the backdated session: every hours-scale
  // figure leaves the screen and a minutes-scale total remains.
  await app.stats.narrowTo('7d', hoursTotal);
  await expect(app.stats.figure(/\d+m\s+listened/).first()).toBeVisible();

  // The year in review: this year renders with the same nonzero
  // totals (the year holds every reported session).
  await app.stats.openYearInReview();
  const year = new Date().getFullYear();
  await expect(app.stats.figure(`${year}`).first()).toBeVisible();
  await expect(app.stats.figure(/\d+h \d+m\s+listened/).first()).toBeVisible();

  // The server-wide recap aggregates every enrolled listener, which is
  // a number this test does not own and does not assert - what it
  // asserts is that the view renders a total at all.
  await app.stats.openServerRecap(app.stats.figure('listeners counted in').first());
  await expect(app.stats.figure(/\d+h \d+m\s+listened together/).first()).toBeVisible();
});

test('a share link plays anonymously and dies on revocation', async ({
  app,
  playwright,
  baseURL,
}) => {
  const { pid } = await app.seed.item('Bravo Song');

  const share = await app.api.post('/shares', {
    data: { pid, allowDownload: false },
  });
  expect(share.pid).toMatch(/^sh-/);
  expect(share.url).toMatch(/^\/s\//);
  expect(share.allowDownload).toBe(false);

  // The capability URL works with no credentials at all: a fresh
  // request context, no cookies, no bearer. The language is pinned
  // because the page's chrome is negotiated and the copy asserted below
  // is the English wording, which no runner's locale should decide.
  const anon = await playwright.request.newContext({
    baseURL,
    extraHTTPHeaders: { 'Accept-Language': 'en' },
  });
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
    expect((await anon.get(tampered)).status()).toBe(404);

    // Revocation bites immediately.
    const revoked = await app.api.raw.delete('/shares/{shareId}', {
      path: { shareId: share.pid },
    });
    expect(revoked.status()).toBe(204);
    const gone = await anon.get(share.url);
    expect(gone.status()).toBe(404);
    expect(await gone.text()).toContain('revoked');
    expect((await anon.get(`${share.url}/stream`)).status()).toBe(404);
  } finally {
    await anon.dispose();
  }
});

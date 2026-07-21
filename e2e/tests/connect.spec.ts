import { test, expect, Page, BrowserContext, Browser } from '@playwright/test';
import { ensureAdmin, authed, typeInto, waitForLibrary } from './helpers';

// Connect: every signed-in client is a controller and a controllable
// endpoint. Two live web clients: A plays locally and mirrors its
// session to the server; B sees the session, remote-controls it, and
// finally pulls the playback onto itself (the mid-track handoff).

async function loginWeb(browser: Browser): Promise<{ context: BrowserContext; page: Page }> {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, 'admin');
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), 'wax-e2e-pass');
  await page.getByRole('button', { name: 'Log in' }).click();
  return { context, page };
}

function sem(page: Page, id: string) {
  return page.locator(`[flt-semantics-identifier="${id}"]`);
}

test('a session mirrors to the server and relays remote control', async ({
  browser,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  const items = await (
    await request.get('/api/v1/library/items', authed(token))
  ).json();
  const target = items.items.find(
    (it: { title: string }) => it.title === 'Alpha Song',
  );

  // Client A: plays the track on its own player.
  const a = await loginWeb(browser);
  const card = sem(a.page, `item-${target.pid}`);
  await card.waitFor({ timeout: 30_000 });
  await card.click();
  const toggle = sem(a.page, 'player-toggle');
  await toggle.waitFor({ timeout: 30_000 });

  // A's playback reaches the server as a mirror session.
  await expect
    .poll(
      async () => {
        const res = await request.get('/api/v1/player/sessions', authed(token));
        const body = await res.json();
        return body.sessions.length;
      },
      { timeout: 15_000 },
    )
    .toBeGreaterThan(0);
  const sessions = await (
    await request.get('/api/v1/player/sessions', authed(token))
  ).json();
  const session = sessions.sessions[0];
  expect(session.authority).toBe('mirror');
  expect(session.entries[0].pid).toBe(target.pid);

  // A's endpoint lists too.
  const endpoints = await (
    await request.get('/api/v1/player/endpoints', authed(token))
  ).json();
  expect(endpoints.endpoints.some((e: { kind: string }) => e.kind === 'client')).toBe(true);

  // Client B: opens its own player screen on another item, then the
  // device picker, and finds A's session listed.
  const b = await loginWeb(browser);
  const otherCard = sem(b.page, `item-${items.items.find((it: { title: string }) => it.title === 'Bravo Song').pid}`);
  await otherCard.waitFor({ timeout: 30_000 });
  await otherCard.click();
  const devices = sem(b.page, 'player-devices');
  await devices.waitFor({ timeout: 30_000 });
  await devices.click({ force: true });

  const sessionRow = sem(b.page, `session-${session.id}`);
  await sessionRow.waitFor({ timeout: 15_000 });
  await sessionRow.scrollIntoViewIfNeeded();
  await sessionRow.click({ force: true });

  // The remote screen renders A's playback and pauses it; the pause
  // must land on A's real engine, observed through the session state
  // the server republishes.
  const remoteToggle = sem(b.page, 'remote-toggle');
  await remoteToggle.waitFor({ timeout: 30_000 });
  await remoteToggle.click({ force: true });
  await expect
    .poll(
      async () => {
        const res = await request.get(
          `/api/v1/player/sessions/${session.id}`,
          authed(token),
        );
        if (res.status() !== 200) return 'gone';
        return (await res.json()).playing;
      },
      { timeout: 15_000 },
    )
    .toBe(false);

  await a.context.close();
  await b.context.close();
});

// The gapless transcode path against the real engine: the timeline
// mints over the API and its proxied HLS playlist serves, boundaries
// mapping both queue members onto one continuous presentation.
test('a queue timeline mints and serves through the real engine', async ({
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  const items = await (
    await request.get('/api/v1/library/items', authed(token))
  ).json();
  const pids = items.items
    .filter((it: { title: string }) =>
      ['Alpha Song', 'Bravo Song'].includes(it.title),
    )
    .map((it: { pid: string }) => it.pid);
  expect(pids.length).toBe(2);

  const minted = await request.post('/api/v1/player/timeline', {
    ...authed(token),
    data: { itemPids: pids },
  });
  expect(minted.status()).toBe(201);
  const tl = await minted.json();
  expect(tl.mimeType).toBe('application/vnd.apple.mpegurl');
  expect(tl.boundaries.length).toBe(2);
  expect(tl.boundaries[0].pid).toBe(pids[0]);
  expect(tl.boundaries[1].offsetSamples).toBeGreaterThan(0);

  const master = await request.get(tl.url);
  expect(master.status()).toBe(200);
  const body = await master.text();
  expect(body).toContain('#EXTM3U');
  expect(body).toContain('mt=');
});

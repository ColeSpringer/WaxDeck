import {
  test,
  expect,
  Page,
  BrowserContext,
  Browser,
  APIRequestContext,
} from '@playwright/test';
import { ensureAdmin, authed, typeInto, waitForLibrary } from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// Connect: every signed-in client is a controller and a controllable
// endpoint. Two live web clients: A plays locally and mirrors its
// session to the server; B sees the session, remote-controls it, and
// finally pulls the playback onto itself (the mid-track handoff).

// This spec's own account. Sessions are visible to their owner alone
// (or on a shared endpoint), so the two clients below see each other
// and nobody else: the admin account is played by several specs at
// once, and a session picked out of that list by the track it carries
// can easily be another spec's, which then ends when its browser
// closes.
const CONNECT_USER = 'connect-e2e';
const CONNECT_PASS = 'wax-e2e-connect';

async function ensureConnectUser(request: APIRequestContext, token: string) {
  const res = await request.post('/api/v1/users', {
    ...authed(token),
    data: {
      username: CONNECT_USER,
      password: CONNECT_PASS,
      // Named rather than left to the default: this account has to see
      // the fixture library to play anything from it.
      libraryAccess: { mode: 'all' },
    },
  });
  // Already there from an earlier run against the same stack.
  if (!res.ok() && res.status() !== 409) {
    throw new Error(`could not create the connect account: ${res.status()}`);
  }
}

async function loginWeb(browser: Browser): Promise<{ context: BrowserContext; page: Page }> {
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, CONNECT_USER);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), CONNECT_PASS);
  await page.getByRole('button', { name: 'Log in' }).click();
  return { context, page };
}

/// Signs in over the API as this spec's account, for the session and
/// endpoint lists the two clients are asserted against.
async function connectToken(request: APIRequestContext): Promise<string> {
  const res = await request.post('/api/v1/auth/login', {
    data: { username: CONNECT_USER, password: CONNECT_PASS },
  });
  return (await res.json()).token;
}

function locate(page: Page, id: string) {
  return page.locator(sem(id));
}

test('a session mirrors to the server and relays remote control', async ({
  browser,
  request,
}) => {
  const admin = await ensureAdmin(request);
  await waitForLibrary(request, admin);
  await ensureConnectUser(request, admin);
  const token = await connectToken(request);
  const items = await (
    await request.get('/api/v1/library/items', authed(token))
  ).json();
  const target = items.items.find(
    (it: { title: string }) => it.title === 'Alpha Song',
  );

  // Client A: plays the track on its own player.
  const a = await loginWeb(browser);
  const card = locate(a.page, SemanticsIds.item(target.pid));
  await card.waitFor({ timeout: 30_000 });
  await card.click();
  const toggle = locate(a.page, SemanticsIds.playerToggle);
  await toggle.waitFor({ timeout: 30_000 });

  // A's playback reaches the server as a mirror session, and this
  // account plays nothing else, so it is the only one listed.
  type MirrorSession = {
    id: string;
    authority: string;
    entries: Array<{ pid: string }>;
  };
  let session: MirrorSession | undefined;
  await expect
    .poll(
      async () => {
        const res = await request.get('/api/v1/player/sessions', authed(token));
        const body = await res.json();
        session = (body.sessions as MirrorSession[]).find(
          (s) => s.entries?.[0]?.pid === target.pid,
        );
        return session !== undefined;
      },
      { timeout: 15_000, message: "A's session should mirror to the server" },
    )
    .toBe(true);
  expect(session!.authority).toBe('mirror');

  // A's endpoint lists too.
  const endpoints = await (
    await request.get('/api/v1/player/endpoints', authed(token))
  ).json();
  expect(endpoints.endpoints.some((e: { kind: string }) => e.kind === 'client')).toBe(true);

  // Client B: opens its own player screen on another item, then the
  // device picker, and finds A's session listed.
  const b = await loginWeb(browser);
  const otherCard = locate(
    b.page,
    SemanticsIds.item(items.items.find((it: { title: string }) => it.title === 'Bravo Song').pid),
  );
  await otherCard.waitFor({ timeout: 30_000 });
  await otherCard.click();
  const devices = locate(b.page, SemanticsIds.playerDevices);
  await devices.waitFor({ timeout: 30_000 });
  await devices.click({ force: true });

  const sessionRow = locate(b.page, SemanticsIds.session(session!.id));
  await sessionRow.waitFor({ timeout: 15_000 });
  await sessionRow.scrollIntoViewIfNeeded();
  await sessionRow.click({ force: true });

  // The remote screen renders A's playback and pauses it; the pause
  // must land on A's real engine, observed through the session state
  // the server republishes.
  const remoteToggle = locate(b.page, SemanticsIds.remoteToggle);
  await remoteToggle.waitFor({ timeout: 30_000 });
  await remoteToggle.click({ force: true });
  await expect
    .poll(
      async () => {
        const res = await request.get(
          `/api/v1/player/sessions/${session!.id}`,
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

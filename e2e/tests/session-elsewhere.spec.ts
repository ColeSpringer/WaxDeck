import type { Request, Response } from '@playwright/test';
import { test, expect } from './fixtures';
import { App, T, apiPath, createApp } from './driver';

// One browser, two tabs on its one cookie, and the tab nobody touches
// following what the other did to the session: signed out there is
// signed out here, and another account signed in there is that account
// here, with nothing of the last one left on its screen. A tab that was
// off the network meanwhile finds out when it is back.

/// Every track on the album `app` is showing, heard to the end once.
/// Keyed on the track's own pid: ingest dedupes on the session id, so a
/// retry or a reused stack still counts each one once.
async function hearTheAlbum(app: App): Promise<void> {
  const albumPid = app.nav.location().split('/').pop() ?? '';
  const page = await app.api.get('/library/items', {
    query: { facet: 'album', facetKey: albumPid.slice(3), limit: 100 },
  });
  const tracks = page.items ?? [];
  expect(tracks.length).toBeGreaterThan(0);
  await app.api.post('/listens', {
    data: {
      sessions: tracks.map((track) => ({
        sessionId: `elsewhere-${track.pid}`,
        pid: track.pid,
        startedAt: new Date().toISOString(),
        msPlayed: 1000,
        finished: true,
        source: 'live' as const,
      })),
    },
  });
}

test('a tab signed out in another lands on the sign-in screen by itself', async ({
  app,
  tab,
}) => {
  await app.nav.enter('albums');
  await app.music.openEntity(0);
  const other = await tab();
  await other.nav.enter('home');

  await other.auth.signOut();

  // Untouched: the server closed this tab's socket as ended, and the tab
  // asked what it holds now.
  await expect(app.auth.submit()).toBeVisible({ timeout: T.step });
});

test('a tab that was away while another account signed in comes back as that account', async ({
  app,
  page,
  tab,
  otherAccount,
}) => {
  const ben = await otherAccount('ben');
  const network = await app.network();
  await app.nav.enter('albums');
  await app.music.openEntity(0);
  const album = app.nav.location();
  const albumPid = album.split('/').pop() ?? '';
  await hearTheAlbum(app);
  await app.nav.reload(app.music.entityShuffle());
  await expect(app.music.trackPlays(0)).toHaveText('played once');

  const other = await tab();
  await other.nav.enter('home');

  // Everything this tab hears from here on, in order.
  const heard: { method: string; path: string; status: number; at: number }[] = [];
  const record = (r: Response) =>
    heard.push({
      method: r.request().method(),
      path: new URL(r.url()).pathname,
      status: r.status(),
      at: Date.now(),
    });
  page.on('response', record);

  // This tab drops off the network by itself, its socket with it, so no
  // word of the sign-out reaches it; the other, still on it, signs this
  // account out and Ben in over the cookie they share.
  await network.off();
  await other.auth.signOut();
  await other.auth.signInHere(ben);
  const away = network.sockets.length;
  const back = heard.length;
  await network.on();

  // Untouched, it comes back where it was, as Ben. Nothing but a fresh
  // album screen reads the album itself again, and that screen's play
  // states are Ben's answer: none of this album's tracks counted.
  const read = (method: string, path: (p: string) => boolean, from = 0) =>
    heard.findIndex((r, i) => i >= from && r.method === method && path(r.path));
  await expect
    .poll(() => read('GET', (p) => p.endsWith(`/albums/${albumPid}`)), { timeout: T.nav })
    .toBeGreaterThanOrEqual(0);
  const remounted = read('GET', (p) => p.endsWith(`/albums/${albumPid}`));
  await expect
    .poll(() => read('POST', (p) => p.endsWith('/play-states'), remounted))
    .toBeGreaterThan(remounted);
  expect(heard[read('POST', (p) => p.endsWith('/play-states'), remounted)].status).toBe(200);
  await expect(app.music.entityShuffle()).toBeVisible();
  await expect(app.music.trackPlays(0)).toHaveCount(0);
  expect(app.nav.location()).toBe(album);
  // Its own socket came back, as Ben's, before the swap put Ben's screens
  // up: the first the server took after it was back.
  const rejoined = network.sockets.slice(away).find((s) => s.acceptedAt !== undefined);
  expect(rejoined?.acceptedAt ?? Infinity).toBeLessThan(heard[remounted].at);

  await app.shell.openAccountMenu();
  await expect(app.shell.accountName(ben.username)).toBeVisible();
  await expect(app.shell.accountName(app.account.username)).toHaveCount(0);
  await app.shell.closeAccountMenu();

  // Settled. A write from this tab carries the session it now holds: a
  // pin is Ben's preference document, and a stale token would be a 403.
  // The pin is proved off the document, which shows it before this tab
  // has its answer, so the answer is waited for, armed ahead of the press.
  const asBen = createApp({ page: app.page, api: app.api.as(ben.token), account: ben });
  const written = page.waitForResponse(
    (r) => r.request().method() !== 'GET' && new URL(r.url()).pathname.endsWith('/users/me/prefs'),
    { timeout: T.fetch },
  );
  await asBen.music.togglePin(albumPid);
  expect((await written).status()).toBeLessThan(300);
  page.off('response', record);
  // Nothing it sent from the moment it was back carried the last
  // account's token, the catch-up before the swap included.
  const fromBack = heard.slice(back);
  expect(fromBack.filter((r) => r.status === 403), JSON.stringify(fromBack)).toEqual([]);
});

/// An API request this tab makes for whoever its cookie names: all but
/// the session's own routes and what rides outside the app's client
/// (covers, streams, the socket).
const forTheAccount = (path: string | undefined) =>
  path !== undefined &&
  !path.startsWith('/auth/') &&
  !/\/(art|logo|now-playing-art|stream|events)$/.test(path);

test('a tab back from away sends nothing for the account until the session says whose it is', async ({
  app,
  page,
  tab,
  otherAccount,
}) => {
  const ben = await otherAccount('ben');
  const network = await app.network();
  await app.nav.enter('albums');
  await app.music.openEntity(0);
  const album = app.nav.location();
  const albumPid = album.split('/').pop() ?? '';
  const other = await tab();
  await other.nav.enter('home');

  // Everything this tab sends, as it sends it.
  const sent: { method: string; path?: string; at: number }[] = [];
  const record = (r: Request) => sent.push({ method: r.method(), path: apiPath(r.url()), at: Date.now() });
  page.on('request', record);

  // Away while the other tab signs Ben in over the cookie. Back, its
  // socket returns at once and asks whose the session is; that read is
  // held, and what failed while it was away (the album's reads, retried)
  // and the probes a link coming up makes wait on its answer.
  await network.off();
  await other.auth.signOut();
  await other.auth.signInHere(ben);
  const read = await network.holdNext('/auth/session');
  const back = Date.now();
  await network.on();
  await expect.poll(() => read.sentAt, { timeout: T.step }).toBeDefined();
  // While it is held, through a step's budget or until one goes: nothing
  // for the account, from the return on.
  await page
    .waitForRequest((r) => forTheAccount(apiPath(r.url())), { timeout: T.step })
    .catch(() => undefined);
  const early = sent
    .filter((r) => r.at >= back && forTheAccount(r.path))
    .map((r) => `${r.method} ${r.path}`);
  expect(early).toEqual([]);
  const released = Date.now();
  await read.release();

  // The answer is Ben: the swap takes the screens down and his own album
  // screen reads the album afresh, where the tab was.
  await expect
    .poll(() => sent.some((r) => r.at >= released && r.path === `/albums/${albumPid}`), {
      timeout: T.nav,
    })
    .toBe(true);
  await expect.poll(() => app.nav.location(), { timeout: T.nav }).toBe(album);
  await expect(app.music.entityShuffle()).toBeVisible();
  await app.shell.openAccountMenu();
  await expect(app.shell.accountName(ben.username)).toBeVisible();
  await app.shell.closeAccountMenu();

  // Hidden and shown again, the tab kept running and heard its socket:
  // the request it makes next goes without asking first. The flip is the
  // page's own event over its own state; nothing here hides a page for
  // real.
  await page.evaluate(() => {
    Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' });
    Object.defineProperty(document, 'hidden', { configurable: true, get: () => true });
    document.dispatchEvent(new Event('visibilitychange'));
  });
  await page.evaluate(() => {
    delete (document as unknown as Record<string, unknown>).visibilityState;
    delete (document as unknown as Record<string, unknown>).hidden;
    document.dispatchEvent(new Event('visibilitychange'));
  });
  const asBen = createApp({ page: app.page, api: app.api.as(ben.token), account: ben });
  const written = page.waitForResponse(
    (r) => r.request().method() !== 'GET' && apiPath(r.url()) === '/users/me/prefs',
    { timeout: T.fetch },
  );
  const sockets = network.sockets.length;
  const asked = Date.now();
  await asBen.music.togglePin(albumPid);
  expect((await written).status()).toBeLessThan(300);
  page.off('request', record);
  // Only what the flip could cause counts: a session read between the
  // press and its write going out, with no socket coming or going
  // meanwhile (one that does asks for itself).
  const write = sent.find((r) => r.at >= asked && r.method !== 'GET' && r.path === '/users/me/prefs');
  expect(write).toBeDefined();
  const asking = sent.filter((r) => r.at >= asked && r.at <= write!.at && r.path === '/auth/session');
  expect(
    asking.length === 0 || network.sockets.length > sockets,
    `session reads before the write: ${JSON.stringify(asking)}`,
  ).toBe(true);
});

test('a tab that was away while another signed out finds it signed out when it is back', async ({
  app,
  tab,
}) => {
  const network = await app.network();
  await app.nav.enter('albums');
  await app.music.openEntity(0);
  const other = await tab();
  await other.nav.enter('home');

  // Away, its socket with it, while the other tab signs out and nobody
  // signs in: the socket's every try to come back is refused, which a
  // browser reports like a dead network. The sign-out is on that tab's
  // screen before its server has heard it, so this one comes back only
  // once the revoke is answered: a try that beats it is let in.
  await network.off();
  const revoked = other.page.waitForResponse((r) => apiPath(r.url()) === '/auth/logout', {
    timeout: T.fetch,
  });
  await other.auth.signOut();
  expect((await revoked).status()).toBe(204);
  const away = network.sockets.length;
  await network.on();

  // Untouched, it reads its session on the refused try and lands on the
  // sign-in screen.
  await expect(app.auth.submit()).toBeVisible({ timeout: T.step });
  const tries = network.sockets.slice(away);
  expect(tries.length).toBeGreaterThan(0);
  expect(tries.filter((socket) => socket.acceptedAt !== undefined)).toEqual([]);
});

test('a tab playing as one account writes nothing into the account another signs in over the cookie', async ({
  app,
  page,
  tab,
  otherAccount,
  adminToken,
}) => {
  const ben = await otherAccount('ben');
  const asBen = app.api.as(ben.token);
  await app.nav.enter('albums');
  await app.music.openEntity(0);
  const albumPid = app.nav.location().split('/').pop() ?? '';
  const tracks = await app.api.get('/library/items', {
    query: { facet: 'album', facetKey: albumPid.slice(3), limit: 100 },
  });
  const pids = (tracks.items ?? []).map((track) => track.pid);
  expect(pids.length).toBeGreaterThan(0);
  // What Ben's account holds of these tracks, read as him: his play
  // states and his listening record.
  const bens = async () => ({
    states: ((await asBen.post('/play-states', { data: { pids } })).states ?? [])
      .map((state) => JSON.stringify(state))
      .sort(),
    log: (await asBen.get('/stats/sessions', { query: { limit: 200 } })).sessions ?? [],
  });
  const before = await bens();
  const me = (await app.api.get('/auth/session')).user!;

  // This tab plays the album and rests on a track: what its session sends
  // as it goes is that track's last checkpoint and its listen report.
  const isCheckpoint = (r: Request) =>
    r.method() === 'PUT' && /^\/items\/[^/]+\/play-state$/.test(apiPath(r.url()) ?? '');
  const isWrite = (r: Request) =>
    isCheckpoint(r) || (r.method() === 'POST' && apiPath(r.url()) === '/listens');
  const checkpointed = page.waitForResponse((r) => isCheckpoint(r.request()) && r.ok(), {
    timeout: T.nav,
  });
  await app.music.playEntity('play');
  await checkpointed;
  await app.player.pauseDocked();

  // Another tab signs Ben in over the cookie the two share. This tab's
  // session lives on, its socket with it: nothing here is in doubt.
  const other = await tab();
  const signedIn = await other.auth.browserApi().post('/auth/login', {
    data: { username: ben.username, password: ben.password },
  });

  // What this tab sends from here on, and how each of its writes ended.
  const sent: { method: string; path?: string; at: number }[] = [];
  const writes: { request: Request; csrf?: string; status?: number; failed?: boolean }[] = [];
  const onRequest = (r: Request) => {
    sent.push({ method: r.method(), path: apiPath(r.url()), at: Date.now() });
    if (isWrite(r)) writes.push({ request: r, csrf: r.headers()['x-csrf-token'] });
  };
  const onFinished = async (r: Request) => {
    const write = writes.find((w) => w.request === r);
    if (write) write.status = (await r.response())?.status() ?? 0;
  };
  const onFailed = (r: Request) => {
    const write = writes.find((w) => w.request === r);
    if (write) write.failed = true;
  };
  page.on('request', onRequest);
  page.on('requestfinished', onFinished);
  page.on('requestfailed', onFailed);

  // An administrator moves this account's upload right. Its marker hints on
  // this tab's own socket; the pull that follows goes through the cookie,
  // whose page names Ben, so the tab reads its session again, which the
  // cookie answers as Ben's.
  const admin = app.api.as(await adminToken());
  const moved = Date.now();
  await admin.patch('/users/{userId}', {
    path: { userId: me.id },
    data: { uploadEnabled: !me.uploadEnabled },
  });

  // Ben's own album screen, where the tab was.
  await expect
    .poll(() => sent.some((r) => r.at >= moved && r.path === `/albums/${albumPid}`), {
      timeout: T.nav,
    })
    .toBe(true);
  await app.shell.openAccountMenu();
  await expect(app.shell.accountName(ben.username)).toBeVisible();
  await app.shell.closeAccountMenu();
  await expect
    .poll(() => writes.every((w) => w.status !== undefined || w.failed), { timeout: T.fetch })
    .toBe(true);
  page.off('request', onRequest);
  page.off('requestfinished', onFinished);
  page.off('requestfailed', onFailed);

  // None of what the leaving session sent went with Ben's token, and his
  // account holds exactly what it did.
  const report = writes.map((w) => ({
    write: `${w.request.method()} ${apiPath(w.request.url())}`,
    asBen: w.csrf === signedIn.csrfToken,
    status: w.status,
    failed: w.failed,
  }));
  console.log(`LEAVING-WRITES ${JSON.stringify(report)}`);
  expect.soft(report.filter((w) => w.asBen)).toEqual([]);
  expect(await bens()).toEqual(before);
});

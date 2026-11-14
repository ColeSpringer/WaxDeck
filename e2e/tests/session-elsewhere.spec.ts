import type { Response } from '@playwright/test';
import { test, expect } from './fixtures';
import { App, T, createApp } from './driver';

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
  const settled = heard.length;
  const asBen = createApp({ page: app.page, api: app.api.as(ben.token), account: ben });
  await asBen.music.togglePin(albumPid);
  page.off('response', record);
  const since = heard.slice(settled);
  expect(
    since.some((r) => r.method !== 'GET' && r.path.endsWith('/users/me/prefs') && r.status < 300),
    JSON.stringify(since),
  ).toBe(true);
  // Nothing it sent from the moment it was back carried the last
  // account's token, the catch-up before the swap included.
  const fromBack = heard.slice(back);
  expect(fromBack.filter((r) => r.status === 403), JSON.stringify(fromBack)).toEqual([]);
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
  // browser reports like a dead network.
  await network.off();
  await other.auth.signOut();
  const away = network.sockets.length;
  await network.on();

  // Untouched, it reads its session on the refused try and lands on the
  // sign-in screen.
  await expect(app.auth.submit()).toBeVisible({ timeout: T.step });
  const tries = network.sockets.slice(away);
  expect(tries.length).toBeGreaterThan(0);
  expect(tries.filter((socket) => socket.acceptedAt !== undefined)).toEqual([]);
});

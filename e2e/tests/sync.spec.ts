import { test, expect, APIRequestContext } from '@playwright/test';
import crypto from 'node:crypto';
import { authed, ensureAdmin, typeInto, waitForLibrary } from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The live-sync slice over the real stack: the delta-sync endpoints, the
// WebSocket invalidation channel (exercised as two live web clients
// converging), offline mutation replay semantics, downloads of original
// bytes, and the read-only Subsonic surface over app passwords.

test('a mirror snapshots, deltas to quiescence, and follows a change', async ({
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);

  // Snapshot the catalog, paging keyset-style.
  const mirror = new Map<string, string>();
  let since = '';
  let cursor = '';
  for (;;) {
    const q = cursor ? `?limit=2&cursor=${encodeURIComponent(cursor)}` : '?limit=2';
    const page = await (
      await request.get(`/api/v1/sync/catalog${q}`, authed(token))
    ).json();
    expect(page.nextSince).toBeTruthy();
    since = page.nextSince;
    for (const e of page.entries) {
      // The contract: mirrors drop entries whose op they do not
      // recognize (podcast shows ride the same stream as their own
      // operation). This mirror only tracks items.
      if (e.op !== 'upsert') continue;
      mirror.set(e.pid, e.item.title);
    }
    if (!page.nextCursor) break;
    cursor = page.nextCursor;
  }
  expect(mirror.size).toBeGreaterThanOrEqual(4);

  // A drained stream deltas to nothing and the cursor advances in place.
  const empty = await (
    await request.get(
      `/api/v1/sync/catalog?since=${encodeURIComponent(since)}`,
      authed(token),
    )
  ).json();
  expect(empty.entries).toHaveLength(0);

  // The caller's own state flows on the server stream: mint, star, pull.
  const mint = await (
    await request.get('/api/v1/sync/server', authed(token))
  ).json();
  // Specs run in parallel against one stack; each uses its own item so
  // star state never races another spec's assertions (the audit owns
  // Alpha, the two-client test owns Bravo).
  const pid = [...mirror.entries()].find(([, t]) => t === 'Delta Song')![0];
  await request.put(`/api/v1/items/${pid}/star`, {
    ...authed(token),
    data: { starred: true },
  });
  const delta = await (
    await request.get(
      `/api/v1/sync/server?since=${encodeURIComponent(mint.nextSince)}`,
      authed(token),
    )
  ).json();
  const ev = delta.events.find(
    (e: { kind: string; pid?: string }) => e.kind === 'play-state' && e.pid === pid,
  );
  expect(ev, 'the star arrived on the server stream').toBeTruthy();
  expect(ev.playState.starred).toBe(true);

  // Clean up for other specs: unstar.
  await request.put(`/api/v1/items/${pid}/star`, {
    ...authed(token),
    data: { starred: false },
  });
});

test('an offline replay reconciles instead of clobbering', async ({ request }) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  const items = await (
    await request.get('/api/v1/library/items', authed(token))
  ).json();
  const pid = items.items[0].pid;

  // A live checkpoint, then a stale offline replay from an hour ago:
  // the live state wins (music is furthest-position with a recency
  // guard, and the replay is both nearer and far older).
  await request.put(`/api/v1/items/${pid}/play-state`, {
    ...authed(token),
    data: { positionMs: 90_000 },
  });
  const staleAt = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  await request.put(`/api/v1/items/${pid}/play-state`, {
    ...authed(token),
    data: { positionMs: 1_000, recordedAt: staleAt },
  });
  const state = await (
    await request.get(`/api/v1/items/${pid}/play-state`, authed(token))
  ).json();
  expect(state.positionMs).toBe(90_000);
});

test('the original bytes download with ranges and a strong validator', async ({
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  const items = await (
    await request.get('/api/v1/library/items', authed(token))
  ).json();
  const pid = items.items.find(
    (it: { title: string }) => it.title === 'Alpha Song',
  ).pid;

  const info = await (
    await request.get(`/api/v1/items/${pid}/download-info`, authed(token))
  ).json();
  expect(info.files).toHaveLength(1);
  const f = info.files[0];
  expect(f.mimeType).toBe('audio/flac');
  expect(f.essenceHash).toBeTruthy();

  const whole = await request.get(f.url);
  expect(whole.status()).toBe(200);
  expect(whole.headers()['etag']).toBe(`"${f.etag}"`);
  expect(whole.headers()['content-disposition']).toContain('alpha.flac');
  expect((await whole.body()).length).toBe(f.sizeBytes);

  const range = await request.get(f.url, {
    headers: { Range: 'bytes=0-99' },
  });
  expect(range.status()).toBe(206);
  expect((await range.body()).length).toBe(100);
});

test('a server edit reaches a second live client in about a second', async ({
  browser,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  const items = await (
    await request.get('/api/v1/library/items', authed(token))
  ).json();
  const target = items.items.find(
    (it: { title: string }) => it.title === 'Bravo Song',
  );

  // The watching client: logged in on the web UI with the player open,
  // its event socket live.
  const context = await browser.newContext();
  const page = await context.newPage();
  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, 'admin');
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), 'wax-e2e-pass');
  await page.getByRole('button', { name: 'Log in' }).click();
  const card = page.locator(sem(SemanticsIds.item(target.pid)));
  await card.waitFor({ timeout: 30_000 });
  await card.click();
  const star = page.locator(sem(SemanticsIds.starButton('')));
  await star.waitFor({ timeout: 30_000 });
  await expect(star).toHaveAccessibleName('Star');

  // Another device stars the item through the API; the watcher's UI
  // follows through the invalidation channel without any interaction.
  const started = Date.now();
  await request.put(`/api/v1/items/${target.pid}/star`, {
    ...authed(token),
    data: { starred: true },
  });
  await expect(star).toHaveAccessibleName('Unstar', { timeout: 3_000 });
  const elapsed = Date.now() - started;
  console.log(`cross-client star visible after ${elapsed}ms`);

  await request.put(`/api/v1/items/${target.pid}/star`, {
    ...authed(token),
    data: { starred: false },
  });
  await context.close();
});

async function subsonic(
  request: APIRequestContext,
  secret: string,
  view: string,
  extra = '',
) {
  const salt = 'e2esalt';
  const t = crypto.createHash('md5').update(secret + salt).digest('hex');
  const res = await request.get(
    `/rest/${view}?u=admin&t=${t}&s=${salt}&v=1.16.1&c=e2e&f=json${extra}`,
  );
  expect(res.status()).toBe(200);
  return (await res.json())['subsonic-response'];
}

test('a Subsonic client browses and streams read-only', async ({ request }) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);

  const created = await (
    await request.post('/api/v1/users/me/app-passwords', {
      ...authed(token),
      data: { label: 'e2e subsonic' },
    })
  ).json();
  expect(created.secret).toHaveLength(26);

  const ping = await subsonic(request, created.secret, 'ping');
  expect(ping.status).toBe('ok');
  expect(ping.openSubsonic).toBe(true);

  // Sections order "#" first (the untagged matrix files group under
  // [Unknown Artist] there), so find the fixture artist by name.
  const artists = await subsonic(request, created.secret, 'getArtists');
  const artist = artists.artists.index
    .flatMap((s: { artist: { id: string; name: string }[] }) => s.artist)
    .find((a: { name: string }) => a.name === 'Fixture Artist');
  expect(artist).toBeTruthy();

  const detail = await subsonic(
    request,
    created.secret,
    'getArtist',
    `&id=${encodeURIComponent(artist.id)}`,
  );
  const album = detail.artist.album[0];
  const songs = await subsonic(
    request,
    created.secret,
    'getAlbum',
    `&id=${encodeURIComponent(album.id)}`,
  );
  const song = songs.album.song.find(
    (s: { title: string }) => s.title === 'Charlie Song',
  );
  expect(song.id).toMatch(/^tr-/);

  // stream redirects into the tokenized proxy and real bytes flow.
  const salt = 'e2esalt';
  const t = crypto.createHash('md5').update(created.secret + salt).digest('hex');
  const stream = await request.get(
    `/rest/stream?u=admin&t=${t}&s=${salt}&id=${song.id}`,
    { maxRedirects: 5 },
  );
  expect(stream.status()).toBe(200);
  expect((await stream.body()).length).toBeGreaterThan(0);

  // The login password never authenticates this surface.
  const badT = crypto.createHash('md5').update('wax-e2e-pass' + salt).digest('hex');
  const rejected = await (
    await request.get(`/rest/ping?u=admin&t=${badT}&s=${salt}&f=json`)
  ).json();
  expect(rejected['subsonic-response'].status).toBe('failed');
  expect(rejected['subsonic-response'].error.code).toBe(40);

  await request.delete(`/api/v1/users/me/app-passwords/${created.id}`, authed(token));
});

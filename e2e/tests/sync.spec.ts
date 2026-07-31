import { test, expect, APIRequestContext } from './fixtures';
import crypto from 'node:crypto';
import { authed, ensureAdmin, typeInto, waitForLibrary } from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The live-sync slice over the real stack: the delta-sync endpoints, the
// WebSocket invalidation channel (exercised as two live web clients
// converging), offline mutation replay semantics, downloads of original
// bytes, and the read-only Subsonic surface over app passwords.

test('a mirror snapshots, deltas from its cursor, and follows a change', async ({
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);

  // Four workers share this server and account, so nothing here asserts
  // what the delta contains: it legitimately carries other specs' churn
  // (episode downloads, uploads, a rescan re-rowing items), and a
  // sibling subscribe or unsubscribe retires this account's catalog
  // cursors outright (410 sync-reset). Only presence of a write this
  // spec just made is parallel-safe to assert - absence never is - so
  // the catalog half checks protocol mechanics (pages serve, cursors
  // advance, resets recover) and the owned-write check rides the
  // server stream below. Single-writer delta arrival is pinned in the
  // server's sync integration tests.
  const snapshot = async () => {
    const mirror = new Map<string, string>();
    let since = '';
    let cursor = '';
    for (;;) {
      const q = cursor ? `?limit=2&cursor=${encodeURIComponent(cursor)}` : '?limit=2';
      const res = await request.get(`/api/v1/sync/catalog${q}`, authed(token));
      // Only the delta path epoch-checks, so a sibling's subscribe
      // cannot 410 a snapshot page; any non-200 is a real failure.
      expect(res.status(), 'a snapshot page should serve').toBe(200);
      const page = await res.json();
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
    return { mirror, since };
  };

  // Snapshot, then drain the first delta to its current end.
  let mirror = new Map<string, string>();
  for (let attempt = 0; ; attempt++) {
    expect(attempt, 'catalog cursors kept resetting').toBeLessThan(4);
    const snap = await snapshot();
    mirror = snap.mirror;
    let since = snap.since;
    let reset = false;
    for (let pages = 0; ; pages++) {
      expect(pages, 'the delta should drain').toBeLessThan(50);
      const res = await request.get(
        `/api/v1/sync/catalog?since=${encodeURIComponent(since)}`,
        authed(token),
      );
      if (res.status() === 410) {
        console.log('catalog cursor retired mid-drain (sync-reset); re-mirroring');
        reset = true;
        break;
      }
      expect(res.status(), 'a delta page should serve').toBe(200);
      const page = await res.json();
      expect(page.nextSince).toBeTruthy();
      since = page.nextSince;
      if (!page.more) break;
    }
    if (!reset) break;
  }
  expect(mirror.size).toBeGreaterThanOrEqual(4);

  // The caller's own state flows on the server stream: mint, star,
  // pull. Events hydrate play state fresh at read time, so a shared
  // item's star read here would carry whatever a sibling just wrote -
  // and every music track's star has an owner (identity stars the
  // first two items, playlists stars Charlie and Delta, the two-client
  // test below stars Bravo). The book is the one fixture nothing else
  // stars; audiobooks.spec writes only its position, which the server
  // merges independently of the star.
  const own = [...mirror.entries()].find(([, t]) => t === 'The Fixture Book');
  expect(own, 'The Fixture Book should be in the mirrored catalog').toBeTruthy();
  const pid = own![0];

  // A 410 on this stream (event floor or generation moved) has no
  // in-suite trigger today, but it is legal, and re-minting and
  // re-starring is the client-correct recovery, as above.
  let ev: { kind: string; pid?: string; playState?: { starred?: boolean } } | undefined;
  for (let attempt = 0; ; attempt++) {
    expect(attempt, 'server cursors kept resetting').toBeLessThan(4);
    const mintRes = await request.get('/api/v1/sync/server', authed(token));
    expect(mintRes.status(), 'minting a server cursor should serve').toBe(200);
    const mint = await mintRes.json();
    expect(mint.nextSince).toBeTruthy();
    const star = await request.put(`/api/v1/items/${pid}/star`, {
      ...authed(token),
      data: { starred: true },
    });
    // Checked here so a refused write fails as itself, not four steps
    // later as a missing event.
    expect(star.status(), 'the star write should succeed').toBe(200);
    // Other specs' events share the mint-to-pull window, so walk every
    // page and find our own instead of expecting the first page to
    // hold it.
    const events: { kind: string; pid?: string; playState?: { starred?: boolean } }[] = [];
    let serverSince = mint.nextSince;
    let reset = false;
    for (let pages = 0; ; pages++) {
      expect(pages, 'the server stream should drain').toBeLessThan(50);
      const res = await request.get(
        `/api/v1/sync/server?since=${encodeURIComponent(serverSince)}`,
        authed(token),
      );
      if (res.status() === 410) {
        console.log('server cursor retired mid-drain (sync-reset); re-minting');
        reset = true;
        break;
      }
      expect(res.status(), 'a server stream page should serve').toBe(200);
      const page = await res.json();
      expect(page.nextSince).toBeTruthy();
      events.push(...page.events);
      serverSince = page.nextSince;
      if (!page.more) break;
    }
    if (reset) continue;
    ev = events.find((e) => e.kind === 'play-state' && e.pid === pid);
    break;
  }
  expect(ev, 'the star arrived on the server stream').toBeTruthy();
  expect(ev!.playState!.starred).toBe(true);

  // Clean up for other specs: unstar.
  const unstar = await request.put(`/api/v1/items/${pid}/star`, {
    ...authed(token),
    data: { starred: false },
  });
  expect(unstar.status(), 'the unstar write should succeed').toBe(200);
});

test('an offline replay reconciles instead of clobbering', async ({ request }) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  // Own position only: playback.spec checkpoints Alpha's, so a blind
  // first-item pick can race it and one side's read loses. Delta
  // Song's position is this test's alone - playlists.spec stars and
  // scrobbles Delta, but neither write touches position. Found by
  // search because the item list pages while a title stays stable.
  const search = await (
    await request.get('/api/v1/library/search?q=Delta', authed(token))
  ).json();
  const target = search.tracks.find(
    (t: { title: string }) => t.title === 'Delta Song',
  );
  expect(target, 'Delta Song should be searchable').toBeTruthy();
  const pid = target.pid;

  // A live checkpoint, then a stale offline replay from an hour ago:
  // the live state wins (music is furthest-position with a recency
  // guard, and the replay is both nearer and far older).
  const live = await request.put(`/api/v1/items/${pid}/play-state`, {
    ...authed(token),
    data: { positionMs: 90_000 },
  });
  expect(live.status(), 'the live checkpoint should land').toBe(204);
  const staleAt = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const replay = await request.put(`/api/v1/items/${pid}/play-state`, {
    ...authed(token),
    data: { positionMs: 1_000, recordedAt: staleAt },
  });
  expect(replay.status(), 'the offline replay should land').toBe(204);
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
  const put = await request.put(`/api/v1/items/${target.pid}/star`, {
    ...authed(token),
    data: { starred: true },
  });
  expect(put.status(), 'the star write should succeed').toBe(200);
  await expect(star).toHaveAccessibleName('Unstar', { timeout: 3_000 });
  const elapsed = Date.now() - started;
  console.log(`cross-client star visible after ${elapsed}ms`);

  const revert = await request.put(`/api/v1/items/${target.pid}/star`, {
    ...authed(token),
    data: { starred: false },
  });
  expect(revert.status(), 'the unstar write should succeed').toBe(200);
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

import { test, expect } from './fixtures';
import { subsonic, subsonicCredentials } from './driver/subsonic';
import { T } from './driver';

// The live-sync slice over the real stack: the delta-sync endpoints, the
// WebSocket invalidation channel (exercised as a live web client
// following a change made elsewhere), offline mutation replay semantics,
// downloads of original bytes, and the read-only Subsonic surface over
// app passwords.

test('a mirror snapshots, deltas from its cursor, and follows a change', async ({ app }) => {
  // The catalog stream is the half per-test accounts do NOT divide: four
  // workers write to one catalog, so a delta legitimately carries other
  // specs' churn (episode downloads, uploads, a rescan re-rowing items),
  // and a sibling's subscribe retires this account's catalog cursors
  // outright (410 sync-reset). So the catalog half checks protocol
  // mechanics - pages serve, cursors advance, resets recover - and never
  // what the delta contains. The server stream below is per listener,
  // which is what lets the owned-write check be exact.
  const snapshot = async () => {
    const mirror = new Map<string, string>();
    let since = '';
    let cursor: string | undefined;
    for (;;) {
      // Only the delta path epoch-checks, so a sibling's subscribe
      // cannot 410 a snapshot page; any non-200 is a real failure.
      const page = await app.api.get('/sync/catalog', {
        query: cursor === undefined ? { limit: 2 } : { limit: 2, cursor },
      });
      expect(page.nextSince).toBeTruthy();
      since = page.nextSince;
      for (const e of page.entries) {
        // The contract: mirrors drop entries whose op they do not
        // recognize (podcast shows ride the same stream as their own
        // operation). This mirror only tracks items.
        if (e.op !== 'upsert') continue;
        mirror.set(e.pid, e.item!.title);
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
      const res = await app.api.raw.get('/sync/catalog', { query: { since } });
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

  // The caller's own state flows on the server stream: mint, star, pull.
  // Any item will do now. It used to have to be the one fixture nothing
  // else starred, because every spec starred under the same login and
  // events hydrate play state fresh at read time; this account's stars
  // are this test's.
  const { pid } = await app.seed.item('Alpha Song');
  expect(mirror.has(pid), 'the starred item should be in the mirrored catalog').toBe(true);

  // A 410 on this stream (event floor or generation moved) has no
  // in-suite trigger today, but it is legal, and re-minting and
  // re-starring is the client-correct recovery, as above.
  let ev: { kind: string; pid?: string; playState?: { starred?: boolean } } | undefined;
  for (let attempt = 0; ; attempt++) {
    expect(attempt, 'server cursors kept resetting').toBeLessThan(4);
    const mint = await app.api.get('/sync/server');
    expect(mint.nextSince).toBeTruthy();
    // Through the seeder, which fails on a refused write - so it fails
    // as itself rather than four steps later as a missing event.
    await app.seed.star(pid);
    const events: { kind: string; pid?: string; playState?: { starred?: boolean } }[] = [];
    let serverSince = mint.nextSince;
    let reset = false;
    for (let pages = 0; ; pages++) {
      expect(pages, 'the server stream should drain').toBeLessThan(50);
      const res = await app.api.raw.get('/sync/server', { query: { since: serverSince } });
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

  // Put back, so a rerun on this same account starts where this one did.
  await app.seed.star(pid, false);
});

test('an offline replay reconciles instead of clobbering', async ({ app }) => {
  const { pid } = await app.seed.item('Delta Song');

  // A live checkpoint, then a stale offline replay from an hour ago:
  // the live state wins (music is furthest-position with a recency
  // guard, and the replay is both nearer and far older).
  await app.seed.setPosition(pid, 90_000);
  const staleAt = new Date(Date.now() - 60 * 60 * 1000).toISOString();
  const replay = await app.api.raw.put('/items/{pid}/play-state', {
    path: { pid },
    data: { positionMs: 1_000, recordedAt: staleAt },
  });
  expect(replay.status(), 'the offline replay should land').toBe(204);
  const state = await app.api.get('/items/{pid}/play-state', { path: { pid } });
  expect(state.positionMs).toBe(90_000);
});

test('the original bytes download with ranges and a strong validator', async ({
  app,
  request,
}) => {
  const { pid } = await app.seed.item('Alpha Song');

  const info = await app.api.get('/items/{pid}/download-info', { path: { pid } });
  expect(info.files).toHaveLength(1);
  const f = info.files[0];
  expect(f.mimeType).toBe('audio/flac');
  expect(f.essenceHash).toBeTruthy();

  // The download URL is one the server minted and carries its own token,
  // so it is fetched as a stranger would rather than through the typed
  // hand.
  const whole = await request.get(f.url);
  expect(whole.status()).toBe(200);
  expect(whole.headers()['etag']).toBe(`"${f.etag}"`);
  expect(whole.headers()['content-disposition']).toContain('alpha.flac');
  expect((await whole.body()).length).toBe(f.sizeBytes);

  const range = await request.get(f.url, { headers: { Range: 'bytes=0-99' } });
  expect(range.status()).toBe(206);
  expect((await range.body()).length).toBe(100);
});

test('a server edit reaches a live client in about a second', async ({ app }) => {
  const target = await app.seed.item('Bravo Song');

  // The watching client: the web UI with the player open, its event
  // socket live. One browser is enough - the "other device" is the API
  // call below, which is what a phone, a Subsonic client or another
  // browser all look like from here.
  await app.nav.enter('tracks');
  await app.music.play(target.pid);
  const star = app.player.star();
  await star.waitFor({ timeout: T.nav });
  await expect(star).toHaveAccessibleName('Star');

  // Another device stars the item through the API; the watcher's UI
  // follows through the invalidation channel without any interaction.
  const started = Date.now();
  await app.seed.star(target.pid);
  // The channel's own budget, not a settling tier. What this test is
  // named for is that the edit arrives over the WebSocket rather than on
  // the next poll, and `T.step` (five seconds) is long enough for a
  // fallback poll to satisfy it - which would pass while the subject of
  // the test was broken.
  await expect(star).toHaveAccessibleName('Unstar', { timeout: T.live });
  console.log(`cross-client star visible after ${Date.now() - started}ms`);

  await app.seed.star(target.pid, false);
});

test('a Subsonic client browses and streams read-only', async ({ app, request }) => {
  const who = app.account.username;
  const { id, secret } = await app.seed.appPassword('e2e subsonic');
  expect(secret).toHaveLength(26);
  const call = (view: string, extra = '') => subsonic(request, who, secret, view, extra);

  try {
    const ping = await call('ping');
    expect(ping.status).toBe('ok');
    expect(ping.openSubsonic).toBe(true);

    // Sections order "#" first (the untagged matrix files group under
    // [Unknown Artist] there), so find the fixture artist by name.
    const artists = await call('getArtists');
    const artist = artists.artists.index
      .flatMap((s: { artist: { id: string; name: string }[] }) => s.artist)
      .find((a: { name: string }) => a.name === 'Fixture Artist');
    expect(artist).toBeTruthy();

    const detail = await call('getArtist', `&id=${encodeURIComponent(artist.id)}`);
    const album = detail.artist.album[0];
    const songs = await call('getAlbum', `&id=${encodeURIComponent(album.id)}`);
    const song = songs.album.song.find((s: { title: string }) => s.title === 'Charlie Song');
    expect(song.id).toMatch(/^tr-/);

    // stream redirects into the tokenized proxy and real bytes flow.
    const stream = await request.get(
      `/rest/stream?${subsonicCredentials(who, secret)}&id=${song.id}`,
      { maxRedirects: 5 },
    );
    expect(stream.status()).toBe(200);
    expect((await stream.body()).length).toBeGreaterThan(0);

    // The login password never authenticates this surface.
    const rejected = await (
      await request.get(`/rest/ping?${subsonicCredentials(who, app.account.password)}&f=json`)
    ).json();
    expect(rejected['subsonic-response'].status).toBe('failed');
    expect(rejected['subsonic-response'].error.code).toBe(40);
  } finally {
    await app.api.delete('/users/me/app-passwords/{appPasswordId}', {
      path: { appPasswordId: id },
    });
  }
});


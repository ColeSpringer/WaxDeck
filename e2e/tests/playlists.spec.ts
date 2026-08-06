import { test, expect } from './fixtures';
import crypto from 'node:crypto';
import { APIRequestContext } from '@playwright/test';

// The playlists slice over the real stack: the rule editor building a
// smart playlist in the browser, live re-evaluation when user state
// changes, a manual list being filled and reordered by hand, the
// add-to-playlist sheet, and the Subsonic playlist, star, scrobble, and
// radio surfaces over app passwords.
//
// Every list here belongs to the test that made it. What that removes is
// the old scoping: a starred rule used to have to name a title as well,
// because parallel specs starred other fixtures under the same login.

test('the rule editor builds, previews, and saves a smart playlist', async ({ app }) => {
  await app.seed.clearPlaylistsNamed('All The Music');
  await app.nav.enter('playlists');

  await app.playlists.create('smart', 'All The Music');

  // The editor's default condition is mediaType is music, which matches
  // the fixture library; the preview reports the live count.
  await app.playlists.ruleAddCondition().click();
  await expect(app.playlists.rulePreview()).toContainText(/Matches [1-9]\d* items/);
  await app.playlists.ruleSave().click();

  // Back on the listing (the add button proves the editor is gone, so
  // the row text cannot false-positive on the editor's heading), the
  // playlist exists; its detail evaluates.
  await app.playlists.add().waitFor();
  await app.playlists.text('All The Music').waitFor();
  const made = await app.seed.playlistNamed('All The Music');
  await app.playlists.openShowing(made, app.playlists.ruleSummary());

  // What the list is and how much it holds, read off the header's own
  // accessible name.
  await expect(app.playlists.header(/Smart playlist · [1-9]\d* items/)).toBeVisible();
  await expect(
    app.playlists.text('Evaluated live, every time this list is opened.'),
  ).toBeVisible();

  await app.seed.clearPlaylistsNamed('All The Music');
});

test('a smart playlist with user-state rules live-updates', async ({ app }) => {
  const target = await app.seed.item('Charlie Song');
  await app.seed.star(target.pid, false);

  // Starred alone is enough now. It used to need a title condition
  // beside it, because four workers shared one login and every star any
  // of them made was in this rule's scope; this account stars what this
  // test stars and nothing else.
  const pid = await app.seed.createSmartPlaylist('Starred Live', {
    root: {
      type: 'all',
      nodes: [{ type: 'condition', field: 'starred', op: 'is', value: 'true' }],
    },
  });

  try {
    await app.nav.enter('playlists');
    await app.playlists.openShowing(pid, app.playlists.text('Nothing matches yet'));

    // Another device stars the track; the open playlist re-evaluates
    // through the invalidation channel without any interaction.
    await app.seed.star(target.pid);
    await expect(app.playlists.text('Charlie Song')).toBeVisible();
  } finally {
    await app.seed.star(target.pid, false);
    await app.api.delete('/playlists/{pid}', { path: { pid } });
  }
});

test('a manual playlist is filled from its own search row and reordered by hand', async ({
  app,
}) => {
  const pid = await app.seed.createPlaylist('By Hand');

  try {
    await app.nav.enter('playlists');
    await app.playlists.openShowing(pid, app.playlists.addField());

    // Two tracks, added through the row that keeps the listener on the
    // page they are building.
    for (const title of ['Alpha Song', 'Bravo Song']) {
      await app.playlists.addByTitle(title);
      await expect(app.playlists.text(`Added "${title}"`)).toBeVisible();
    }

    const stored = async () => {
      const items = await app.api.tryGet('/playlists/{pid}/items', { path: { pid } });
      return (items?.entries ?? []).map((e) => e.item.title);
    };
    await expect.poll(stored).toEqual(['Alpha Song', 'Bravo Song']);

    // Drag the second row onto the first. The replace carries the
    // playlist's own updatedAt as its precondition, so a stored order
    // that flips is proof the whole round trip landed.
    await app.playlists.reorder(1, 0);
    await expect.poll(stored).toEqual(['Bravo Song', 'Alpha Song']);

    // And one row back out, through the affordance a keyboard can reach.
    await app.playlists.entryRemove(0).click();
    await expect.poll(stored).toEqual(['Alpha Song']);
  } finally {
    await app.api.delete('/playlists/{pid}', { path: { pid } });
  }
});

test('the player adds a track to a fresh manual playlist', async ({ app }) => {
  await app.seed.clearPlaylistsNamed('From The Player');
  const target = await app.seed.item('Alpha Song');

  await app.nav.enter('tracks');
  await app.music.play(target.pid);
  await app.player.addToPlaylist();
  await app.playlists.createFromSheet('From The Player');

  // The snack text shows twice on flutter web (the visible span and the
  // polite live-region announcement); either one proves delivery.
  await expect(
    app.playlists.text('Added "Alpha Song" to From The Player'),
  ).toBeVisible();

  const pid = await app.seed.playlistNamed('From The Player');
  const entries = await app.api.get('/playlists/{pid}/items', { path: { pid } });
  expect((entries.entries ?? []).map((e) => e.item.title)).toContain('Alpha Song');
  await app.seed.clearPlaylistsNamed('From The Player');
});

test('a Subsonic client manages playlists, stars, scrobbles, and radio', async ({
  app,
  request,
}) => {
  const who = app.account.username;
  const { id, secret } = await app.seed.appPassword('playlist e2e');
  const call = (view: string, extra = '') => subsonic(request, who, secret, view, extra);
  const target = await app.seed.item('Delta Song');

  try {
    // Create a playlist with one song and read it back.
    const created = await call('createPlaylist', `&name=SubsonicList&songId=${target.pid}`);
    expect(created.playlist.songCount).toBe(1);
    const playlistId = created.playlist.id;
    const lists = await call('getPlaylists');
    expect(lists.playlists.playlist.map((p: { name: string }) => p.name)).toContain(
      'SubsonicList',
    );

    // Star through /rest and observe it in getStarred2. Exact, because
    // the starred set belongs to this account: it used to be whatever
    // four specs had starred between them.
    await call('star', `&id=${target.pid}`);
    const starred = await call('getStarred2');
    expect(starred.starred2.song.map((s: { id: string }) => s.id)).toEqual([target.pid]);
    await call('unstar', `&id=${target.pid}`);

    // A timed scrobble ingests as a listen exactly once, replay
    // included. Counted as a delta rather than an absolute: a retry
    // lands on this same account and scrobbles at a fresh timestamp, so
    // "exactly one play, ever" would be true only on the first attempt.
    const before =
      (await app.api.get('/items/{pid}/play-state', { path: { pid: target.pid } }))
        .playCount ?? 0;
    const at = Date.now() - 60_000;
    await call('scrobble', `&id=${target.pid}&time=${at}`);
    await call('scrobble', `&id=${target.pid}&time=${at}`);
    await expect
      .poll(
        async () =>
          (await app.api.tryGet('/items/{pid}/play-state', { path: { pid: target.pid } }))
            ?.playCount ?? 0,
        { message: 'a replayed scrobble is one play, not two' },
      )
      .toBe(before + 1);

    // The radio library round-trips through the compatibility surface.
    // It is server-global, so every station under this name goes at the
    // end rather than only the one this attempt made.
    await call(
      'createInternetRadioStation',
      `&name=E2E%20FM&streamUrl=${encodeURIComponent('https://radio.example.com/e2e.mp3')}`,
    );
    const stations = await call('getInternetRadioStations');
    const mine = stations.internetRadioStations.internetRadioStation.filter(
      (s: { name: string }) => s.name === 'E2E FM',
    );
    expect(mine.length).toBeGreaterThan(0);
    for (const station of mine) {
      await call('deleteInternetRadioStation', `&id=${station.id}`);
    }

    await call('deletePlaylist', `&id=${playlistId}`);
  } finally {
    await app.api.delete('/users/me/app-passwords/{appPasswordId}', {
      path: { appPasswordId: id },
    });
  }
});

// The Subsonic surface is somebody else's protocol - salted-hash auth
// over query strings, not the first-party contract - so it is driven
// through the raw request context, the way a real client does.
async function subsonic(
  request: APIRequestContext,
  who: string,
  secret: string,
  view: string,
  extra = '',
) {
  const salt = 'ple2esalt';
  const t = crypto.createHash('md5').update(secret + salt).digest('hex');
  const res = await request.get(
    `/rest/${view}?u=${encodeURIComponent(who)}&t=${t}&s=${salt}&v=1.16.1&c=e2e&f=json${extra}`,
  );
  expect(res.status()).toBe(200);
  const body = (await res.json())['subsonic-response'];
  expect(body.status).toBe('ok');
  return body;
}

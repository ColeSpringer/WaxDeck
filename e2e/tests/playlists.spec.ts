import { test, expect } from './fixtures';
import { subsonic } from './driver/subsonic';
import { clickThrough } from './driver/gestures';

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

test('a smart rule excludes the members of another playlist', async ({ app }) => {
  // Playlist membership as a rule dimension: "everything except what is
  // already in that list", which is what the field landed for. Built
  // over the API rather than through the editor - the editor's picker is
  // covered by a widget test, and what is worth proving over the real
  // stack is that the engine actually excludes the members.
  const target = await app.seed.item('Alpha Song');
  const archive = await app.seed.createPlaylist('Archive Of One', [target.pid]);

  const rest = await app.seed.createSmartPlaylist('Everything Else', {
    root: {
      type: 'all',
      nodes: [
        { type: 'condition', field: 'mediaType', op: 'is', value: 'music' },
        { type: 'condition', field: 'playlist', op: 'isNot', value: archive },
      ],
    },
  });

  try {
    const titles = async () => {
      const items = await app.api.tryGet('/playlists/{pid}/items', { path: { pid: rest } });
      return (items?.entries ?? []).map((e) => e.item.title);
    };
    await expect.poll(titles).not.toContain('Alpha Song');
    // Not empty either: an excluded member is the subject, and a rule
    // that matched nothing would pass the assertion above for free.
    expect((await titles()).length).toBeGreaterThan(0);

    // And the detail header names the list rather than showing its pid.
    await app.nav.enter('playlists');
    await app.playlists.openShowing(rest, app.playlists.ruleSummary());
    await expect(app.playlists.text('Playlist is not Archive Of One')).toBeVisible();
  } finally {
    await app.api.delete('/playlists/{pid}', { path: { pid: rest } });
    await app.api.delete('/playlists/{pid}', { path: { pid: archive } });
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

test('a Navidrome smart playlist round-trips through NSP', async ({ app }) => {
  await app.seed.clearPlaylistsNamed('From Navidrome');
  await app.seed.clearPlaylistsNamed('Music only');

  // A document written the way the other server writes one: a rating on
  // its 0-5 scale, and a notContains that has no rule operator of its
  // own.
  const imported = await app.api.post('/playlists/nsp', {
    data: {
      name: 'From Navidrome',
      all: [
        { contains: { genre: 'Rock' } },
        { gt: { rating: 3 } },
        { notContains: { title: 'Live' } },
      ],
      sort: 'dateAdded',
      order: 'desc',
      limit: 25,
    },
  });
  expect(imported.kind).toBe('smart');

  // Out again, and the rating scale comes back down with it.
  const exported = JSON.stringify(
    await app.api.get('/playlists/{pid}/nsp', { path: { pid: imported.pid } }),
  );
  expect(exported).toContain('"rating":3');
  expect(exported).toContain('"notContains"');
  expect(exported).toContain('"limit":25');

  // And what it wrote imports again, which is what "round trip" has to
  // mean for a format another server reads.
  const again = await app.api.post('/playlists/nsp', {
    query: { name: 'Round Two' },
    data: JSON.parse(exported),
  });
  expect(again.kind).toBe('smart');

  // What cannot be said exactly refuses the whole document, in both
  // directions. A field the catalog has no answer for, on the way in:
  const refused = await app.api.raw.post('/playlists/nsp', {
    data: { name: 'Bitrate', all: [{ gt: { bitrate: 320 } }] },
  });
  expect(refused.status()).toBe(400);
  expect(await refused.text()).toContain('bitrate');

  // A typo for `all` is refused rather than read as "everything": an
  // unrecognised top-level key would otherwise import as a rule over
  // the whole library.
  const typo = await app.api.raw.post('/playlists/nsp', {
    data: { name: 'Typo', alll: [{ contains: { genre: 'Rock' } }] },
  });
  expect(typo.status()).toBe(400);
  expect(await typo.text()).toContain('alll');

  // And a rule NSP cannot carry, on the way out. All-or-nothing: the
  // genre condition beside it does not survive on its own.
  const lossy = await app.api.post('/playlists', {
    data: {
      name: 'Music only',
      kind: 'smart',
      rule: {
        root: {
          type: 'all',
          nodes: [
            { type: 'condition', field: 'mediaType', op: 'is', value: 'music' },
            { type: 'condition', field: 'genre', op: 'is', value: 'Rock' },
          ],
        },
      },
    },
  });
  const refusedExport = await app.api.raw.get('/playlists/{pid}/nsp', {
    path: { pid: lossy.pid },
  });
  expect(refusedExport.status()).toBe(501);

  await app.seed.clearPlaylistsNamed('From Navidrome');
  await app.seed.clearPlaylistsNamed('Round Two');
  await app.seed.clearPlaylistsNamed('Music only');
});

test('an NSP export reports every gap, and offers the partial', async ({ app }) => {
  await app.seed.clearPlaylistsNamed('Two Sorts');

  // Two things NSP cannot carry, of two different kinds: a field it has
  // no name for, and a second sort term. The second one is the reason
  // this test exists - a rule ordered by two terms exported fine until
  // the converter started reporting the terms it was silently dropping,
  // and `maxRuleSorts` is 4, so somebody has one.
  const lossy = await app.api.post('/playlists', {
    data: {
      name: 'Two Sorts',
      kind: 'smart',
      rule: {
        root: {
          type: 'all',
          nodes: [
            { type: 'condition', field: 'genre', op: 'is', value: 'Rock' },
            { type: 'condition', field: 'mediaType', op: 'is', value: 'music' },
          ],
        },
        sorts: [{ field: 'playCount', desc: true }, { field: 'title' }],
      },
    },
  });

  // The report never refuses on expressiveness - that is what makes it
  // askable before the export - and it names every gap, not the first.
  const report = await app.api.get('/playlists/{pid}/nsp/report', {
    path: { pid: lossy.pid },
  });
  expect(report.direction).toBe('export');
  const gaps = report.gaps ?? [];
  expect(gaps.length).toBeGreaterThan(1);
  expect(gaps.map((g) => g.kind)).toContain('sort');
  for (const gap of gaps) {
    expect(gap.path).toBeTruthy();
    expect(gap.reason).toBeTruthy();
  }

  // Strict still refuses, and the refusal names the dropped sort term
  // rather than stopping at the first offender it met.
  const strict = await app.api.raw.get('/playlists/{pid}/nsp', {
    path: { pid: lossy.pid },
  });
  expect(strict.status()).toBe(501);
  expect(await strict.text()).toContain('title');

  // The partial writes what is left: the genre condition survives, the
  // field NSP has no name for does not.
  const partial = JSON.stringify(
    await app.api.get('/playlists/{pid}/nsp', {
      path: { pid: lossy.pid },
      query: { partial: true },
    }),
  );
  expect(partial).toContain('Rock');
  expect(partial).not.toContain('mediaType');

  // And through the UI, which is where the choice actually gets made:
  // the loss is listed in the converter's own words, and only somebody
  // who has read it reaches the document.
  await app.nav.enter('playlists');
  await app.playlists.openShowing(lossy.pid, app.playlists.ruleSummary());
  await app.playlists.fromOverflow(
    app.playlists.exportNsp(),
    app.playlists.exportNspLoss(),
  );
  // The converter's sentence names the query engine's spelling (`kind`
  // for a mediaType condition), so the row leads with the field's own
  // name from the rule editor - which is what ties the refusal to a row
  // somebody actually built.
  await expect(app.playlists.exportNspLossRow(0)).toContainText('Media type');
  await expect(app.playlists.exportNspLossRow(1)).toContainText('Title');
  await expect(app.playlists.exportNspLoss()).toContainText('single sort term');

  // Proceeding lands on the same document dialog the other exports use.
  // What it holds is asserted through the API above and in the widget
  // test: a SelectableText reports as an empty disabled textbox to the
  // browser's accessibility tree, so no text assertion can reach it.
  await clickThrough(app.playlists.exportNspProceed(), app.playlists.exportCopy());
  await expect(app.playlists.text('Export as NSP')).toBeVisible();

  await app.seed.clearPlaylistsNamed('Two Sorts');
});


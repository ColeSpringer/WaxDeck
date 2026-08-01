import { test, expect, APIRequestContext, Page } from './fixtures';
import crypto from 'node:crypto';
import { authed, chooseFromMenu, clickThrough, ensureAdmin, itemRow, openMusicSection, typeInto, waitForLibrary } from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The playlists slice over the real stack: the rule editor building a
// smart playlist in the browser, live re-evaluation when user state
// changes, a manual list being filled and reordered by hand, the
// add-to-playlist sheet, and the Subsonic playlist, star, scrobble, and
// radio surfaces over app passwords.


async function login(page: Page) {
  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, 'admin');
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), 'wax-e2e-pass');
  await page.getByRole('button', { name: 'Log in' }).click();
  await page.locator(sem(SemanticsIds.navDestination('music'))).waitFor({ timeout: 30_000 });
  await openMusicSection(page);
}

// Opens the playlists listing from the chrome.
async function openPlaylists(page: Page) {
  await clickThrough(
    page.locator(sem(SemanticsIds.navDestination('playlists'))),
    page.locator(sem(SemanticsIds.playlistAdd)),
  );
}

test('the rule editor builds, previews, and saves a smart playlist', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  await login(page);

  await openPlaylists(page);
  const smartChip = page.locator(sem(SemanticsIds.playlistCreateKind('smart')));
  await clickThrough(page.locator(sem(SemanticsIds.playlistAdd)), smartChip);
  await smartChip.click();
  await typeInto(page, page.locator(sem(SemanticsIds.playlistNameField)), 'All The Music');
  await page.locator(sem(SemanticsIds.playlistCreateConfirm)).click();

  // The editor's default condition is mediaType is music, which matches
  // the fixture library; the preview reports the live count.
  const addCondition = page.locator(sem(SemanticsIds.ruleAddCondition));
  await addCondition.waitFor({ timeout: 30_000 });
  await addCondition.click();
  await expect(page.locator(sem(SemanticsIds.rulePreviewTotal))).toContainText(
    /Matches [1-9]\d* items/,
    { timeout: 15_000 },
  );
  await page.locator(sem(SemanticsIds.ruleSave)).click();

  // Back on the listing (the add button proves the editor is gone,
  // so the row text cannot false-positive on the editor's heading),
  // the playlist exists; its detail evaluates.
  await page.locator(sem(SemanticsIds.playlistAdd)).waitFor({ timeout: 15_000 });
  const card = page.getByText('All The Music').first();
  await card.waitFor({ timeout: 15_000 });
  await clickThrough(card, page.locator(sem(SemanticsIds.playlistRuleSummary)));

  // What the list is and how much it holds, read off the header's own
  // accessible name: the header merges its subtree into one node, so
  // that line is what a screen reader hears rather than a text node of
  // its own.
  await expect(
    page.getByRole('banner', { name: /Smart playlist · [1-9]\d* items/ }),
  ).toBeVisible({ timeout: 15_000 });
  await expect(
    page.getByText('Evaluated live, every time this list is opened.'),
  ).toBeVisible({ timeout: 15_000 });

  // Cleanup so reruns against a warm stack stay idempotent.
  const lists = await (
    await request.get('/api/v1/playlists?limit=200', authed(token))
  ).json();
  for (const pl of lists.playlists) {
    if (pl.name === 'All The Music') {
      await request.delete(`/api/v1/playlists/${pl.pid}`, authed(token));
    }
  }
});

test('a smart playlist with user-state rules live-updates', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  const items = await (
    await request.get('/api/v1/library/items', authed(token))
  ).json();
  const target = items.items.find(
    (it: { title: string }) => it.title === 'Charlie Song',
  );
  expect(target).toBeTruthy();
  await request.put(`/api/v1/items/${target.pid}/star`, {
    ...authed(token),
    data: { starred: false },
  });

  const created = await (
    await request.post('/api/v1/playlists', {
      ...authed(token),
      data: {
        name: 'Starred Live',
        kind: 'smart',
        rule: {
          root: {
            type: 'all',
            nodes: [
              { type: 'condition', field: 'starred', op: 'is', value: 'true' },
              // Scoped to this spec's own item: parallel specs star
              // other fixtures, and an unscoped starred rule would see
              // them.
              {
                type: 'condition',
                field: 'title',
                op: 'is',
                value: 'Charlie Song',
              },
            ],
          },
        },
      },
    })
  ).json();
  expect(created.pid).toMatch(/^pl-/);

  try {
    await login(page);
    await clickThrough(
      page.locator(sem(SemanticsIds.navDestination('playlists'))),
      page.locator(sem(SemanticsIds.playlist(created.pid))),
    );
    await clickThrough(
      page.locator(sem(SemanticsIds.playlist(created.pid))),
      page.getByText('Nothing matches yet'),
    );

    // Another device stars the track; the open playlist re-evaluates
    // through the invalidation channel without any interaction.
    await request.put(`/api/v1/items/${target.pid}/star`, {
      ...authed(token),
      data: { starred: true },
    });
    await expect(page.getByText('Charlie Song')).toBeVisible({
      timeout: 5_000,
    });
  } finally {
    await request.put(`/api/v1/items/${target.pid}/star`, {
      ...authed(token),
      data: { starred: false },
    });
    await request.delete(`/api/v1/playlists/${created.pid}`, authed(token));
  }
});

test('a manual playlist is filled from its own search row and reordered by hand', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  const created = await (
    await request.post('/api/v1/playlists', {
      ...authed(token),
      data: { name: 'By Hand', kind: 'static' },
    })
  ).json();

  try {
    await login(page);
    await clickThrough(
      page.locator(sem(SemanticsIds.navDestination('playlists'))),
      page.locator(sem(SemanticsIds.playlist(created.pid))),
    );
    const addField = page.locator(sem(SemanticsIds.playlistAddField));
    await clickThrough(page.locator(sem(SemanticsIds.playlist(created.pid))), addField);

    // Two tracks, added through the row that keeps the listener on the
    // page they are building.
    for (const title of ['Alpha Song', 'Bravo Song']) {
      await typeInto(page, addField, title);
      const hit = page.locator(sem(SemanticsIds.playlistAddResult(0)));
      await hit.waitFor({ timeout: 15_000 });
      await hit.click();
      await expect(page.getByText(`Added "${title}"`).first()).toBeVisible({
        timeout: 15_000,
      });
    }

    const stored = async () => {
      const page1 = await (
        await request.get(`/api/v1/playlists/${created.pid}/items`, authed(token))
      ).json();
      return page1.entries.map((e: { item: { title: string } }) => e.item.title);
    };
    await expect.poll(stored, { timeout: 15_000 }).toEqual([
      'Alpha Song',
      'Bravo Song',
    ]);

    // Drag the second row onto the first. The replace carries the
    // playlist's own updatedAt as its precondition, so a stored order
    // that flips is proof the whole round trip landed.
    const second = page.locator(sem(SemanticsIds.playlistEntryDrag(1)));
    const first = page.locator(sem(SemanticsIds.playlistEntryDrag(0)));
    await second.waitFor({ timeout: 15_000 });
    const from = await second.boundingBox();
    const to = await first.boundingBox();
    expect(from && to, 'both drag handles are on screen').toBeTruthy();
    await page.mouse.move(from!.x + from!.width / 2, from!.y + from!.height / 2);
    await page.mouse.down();
    await page.mouse.move(to!.x + to!.width / 2, to!.y + to!.height / 2, {
      steps: 12,
    });
    await page.mouse.up();

    await expect.poll(stored, { timeout: 15_000 }).toEqual([
      'Bravo Song',
      'Alpha Song',
    ]);

    // And one row back out, through the affordance a keyboard can reach.
    await page.locator(sem(SemanticsIds.playlistEntryRemove(0))).click();
    await expect.poll(stored, { timeout: 15_000 }).toEqual(['Alpha Song']);
  } finally {
    await request.delete(`/api/v1/playlists/${created.pid}`, authed(token));
  }
});

test('the player adds a track to a fresh manual playlist', async ({
  page,
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

  await login(page);
  const card = await itemRow(page, target.pid);
  await card.waitFor({ timeout: 30_000 });
  // Add-to-playlist is a row of the player's one overflow menu since the
  // rebuild onto the scaffold: 5.3 gives the header two controls, and
  // every verb that acts on the item is behind the second of them.
  await clickThrough(card, page.locator(sem(SemanticsIds.playerMore)));
  await chooseFromMenu(
    page.locator(sem(SemanticsIds.playerMore)),
    page.locator(sem(SemanticsIds.addToPlaylist)),
    page.locator(sem(SemanticsIds.addToPlaylistNew)),
  );
  await page.locator(sem(SemanticsIds.addToPlaylistNew)).click();
  await typeInto(page, page.locator(sem(SemanticsIds.playlistNameField)), 'From The Player');
  await page.locator(sem(SemanticsIds.playlistCreateConfirm)).click();
  // The snack text shows twice on flutter web (the visible span and
  // the polite live-region announcement); either one proves delivery.
  await expect(
    page.getByText('Added "Alpha Song" to From The Player').first(),
  ).toBeVisible({ timeout: 15_000 });

  const lists = await (
    await request.get('/api/v1/playlists?limit=200', authed(token))
  ).json();
  const created = lists.playlists.find(
    (pl: { name: string }) => pl.name === 'From The Player',
  );
  expect(created).toBeTruthy();
  const entries = await (
    await request.get(`/api/v1/playlists/${created.pid}/items`, authed(token))
  ).json();
  expect(entries.entries.map((e: { item: { title: string } }) => e.item.title)).toContain(
    'Alpha Song',
  );
  await request.delete(`/api/v1/playlists/${created.pid}`, authed(token));
});

test('a Subsonic client manages playlists, stars, scrobbles, and radio', async ({
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  const created = await (
    await request.post('/api/v1/users/me/app-passwords', {
      ...authed(token),
      data: { label: 'playlist e2e' },
    })
  ).json();
  const secret = created.secret as string;

  const items = await (
    await request.get('/api/v1/library/items', authed(token))
  ).json();
  const target = items.items.find(
    (it: { title: string }) => it.title === 'Delta Song',
  );

  // Create a playlist with one song and read it back.
  const createRes = await subsonic(
    request,
    secret,
    'createPlaylist',
    `&name=SubsonicList&songId=${target.pid}`,
  );
  expect(createRes.status).toBe('ok');
  expect(createRes.playlist.songCount).toBe(1);
  const playlistId = createRes.playlist.id;
  const lists = await subsonic(request, secret, 'getPlaylists');
  expect(
    lists.playlists.playlist.map((p: { name: string }) => p.name),
  ).toContain('SubsonicList');

  // Star through /rest and observe it in getStarred2.
  await subsonic(request, secret, 'star', `&id=${target.pid}`);
  const starred = await subsonic(request, secret, 'getStarred2');
  expect(
    starred.starred2.song.map((s: { id: string }) => s.id),
  ).toContain(target.pid);
  await subsonic(request, secret, 'unstar', `&id=${target.pid}`);

  // A timed scrobble ingests as a listen exactly once, replay included.
  const at = Date.now() - 60_000;
  await subsonic(request, secret, 'scrobble', `&id=${target.pid}&time=${at}`);
  await subsonic(request, secret, 'scrobble', `&id=${target.pid}&time=${at}`);
  const state = await (
    await request.get(`/api/v1/items/${target.pid}/play-state`, authed(token))
  ).json();
  expect(state.playCount).toBeGreaterThanOrEqual(1);

  // The radio library round-trips through the compatibility surface.
  await subsonic(
    request,
    secret,
    'createInternetRadioStation',
    `&name=E2E%20FM&streamUrl=${encodeURIComponent('https://radio.example.com/e2e.mp3')}`,
  );
  const stations = await subsonic(request, secret, 'getInternetRadioStations');
  const station = stations.internetRadioStations.internetRadioStation.find(
    (s: { name: string }) => s.name === 'E2E FM',
  );
  expect(station).toBeTruthy();
  await subsonic(
    request,
    secret,
    'deleteInternetRadioStation',
    `&id=${station.id}`,
  );

  // Cleanup.
  await subsonic(request, secret, 'deletePlaylist', `&id=${playlistId}`);
});

async function subsonic(
  request: APIRequestContext,
  secret: string,
  view: string,
  extra = '',
) {
  const salt = 'ple2esalt';
  const t = crypto.createHash('md5').update(secret + salt).digest('hex');
  const res = await request.get(
    `/rest/${view}?u=admin&t=${t}&s=${salt}&v=1.16.1&c=e2e&f=json${extra}`,
  );
  expect(res.status()).toBe(200);
  const body = (await res.json())['subsonic-response'];
  expect(body.status).toBe('ok');
  return body;
}

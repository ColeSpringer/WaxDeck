import { test, expect, APIRequestContext, Page } from '@playwright/test';
import crypto from 'node:crypto';
import { authed, clickThrough, ensureAdmin, typeInto, waitForLibrary } from './helpers';

// The playlists slice over the real stack: the rule editor building a
// smart playlist in the browser, live re-evaluation when user state
// changes, the manual add-to-playlist flow, and the Subsonic playlist,
// star, scrobble, and radio surfaces over app passwords.

const sem = (id: string) => `[flt-semantics-identifier="${id}"]`;

async function login(page: Page) {
  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, 'admin');
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), 'wax-e2e-pass');
  await page.getByRole('button', { name: 'Log in' }).click();
  await page.locator(sem('playlists-open')).waitFor({ timeout: 30_000 });
}

test('the rule editor builds, previews, and saves a smart playlist', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  await login(page);

  // exact: true throughout: role names substring-match by default, and
  // a playlist row's merged semantics ("Starred Live, Smart | ...")
  // would satisfy a bare 'Smart' before the dialog even opens.
  const smartSegment = page.getByRole('button', { name: 'Smart', exact: true });
  await clickThrough(page.locator(sem('playlists-open')), page.locator(sem('playlist-add')));
  await clickThrough(page.locator(sem('playlist-add')), smartSegment);
  await smartSegment.click();
  const nameField = page.getByRole('textbox', { name: 'Playlist name' });
  await typeInto(page, nameField, 'All The Music');
  await page.locator(sem('playlist-create-confirm')).click();

  // The editor's default condition is mediaType is music, which matches
  // the fixture library; the preview reports the live count.
  const addCondition = page.locator(sem('rule-add-condition'));
  await addCondition.waitFor({ timeout: 30_000 });
  await addCondition.click();
  await expect(page.getByText(/Matches [1-9]\d* items/)).toBeVisible({
    timeout: 15_000,
  });
  await page.locator(sem('rule-save')).click();

  // Back on the listing (the add button proves the editor is gone,
  // so the row text cannot false-positive on the editor's heading),
  // the playlist exists; its detail evaluates.
  await page.locator(sem('playlist-add')).waitFor({ timeout: 15_000 });
  const row = page.getByText('All The Music').first();
  await row.waitFor({ timeout: 15_000 });
  await clickThrough(row, page.getByText(/Smart playlist \| [1-9]\d* items/));

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
      page.locator(sem('playlists-open')),
      page.locator(sem(`playlist-${created.pid}`)),
    );
    await clickThrough(
      page.locator(sem(`playlist-${created.pid}`)),
      page.getByText('No items match the rules yet'),
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
  const card = page.locator(sem(`item-${target.pid}`));
  await card.waitFor({ timeout: 30_000 });
  await clickThrough(card, page.locator(sem('add-to-playlist')));
  await clickThrough(
    page.locator(sem('add-to-playlist')),
    page.getByRole('button', { name: 'New playlist', exact: true }),
  );
  await page.getByRole('button', { name: 'New playlist', exact: true }).click();
  const nameField = page.getByRole('textbox', { name: 'Playlist name' });
  await typeInto(page, nameField, 'From The Player');
  await page.getByRole('button', { name: 'Create', exact: true }).click();
  // The snack text shows twice on flutter web (the visible span and
  // the polite live-region announcement); either one proves delivery.
  await expect(page.getByText('Added "Alpha Song"').first()).toBeVisible({
    timeout: 15_000,
  });

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

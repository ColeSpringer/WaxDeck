import { test, expect, type SpecPage } from './fixtures';
import { T, clickThrough } from './driver';
import { typeInto } from './driver/gestures';
import { SemanticsIds } from './semantics-ids';
import type { components } from './api-types';

type ServerSyncPage = components['schemas']['ServerSyncPage'];

// Back in a browser tab, where the browser keeps a list of where the
// visitor went and so does the app. The arrow is the browser's own back,
// so the two stay one list: forward after the arrow is where the arrow
// left, a search refined in place is one entry, a page closed is behind
// nothing, and a browser move is told apart from the app's own, which
// the router sees the same way.

/// The client walking its server stream past upload [id]'s marker. Armed
/// before the POST that emits it, because the walk can outrun the POST's
/// own answer.
function walkedPast(page: SpecPage, id: Promise<string>) {
  const walked = page.waitForResponse(
    async (r) => {
      if (!r.url().includes('/sync/server') || !r.url().includes('since=')) return false;
      const body = (await r.json().catch(() => undefined)) as ServerSyncPage | undefined;
      const pid = await id;
      return (body?.events ?? []).some((e) => e.kind === 'upload' && e.pid === pid);
    },
    { timeout: T.fetch },
  );
  id.catch(() => {});
  walked.catch(() => {});
  return walked;
}

test('the arrow is the browser back, so forward returns where it left', async ({
  app,
  page,
}) => {
  // A notification row is the door: it goes to its place, so there is a
  // way back to the list only because back returns where you were.
  const minted = page.waitForResponse(
    (r) => r.url().includes('/sync/server') && !r.url().includes('since='),
    { timeout: T.nav },
  );
  await app.nav.enter('home');
  await minted;
  const posting = app.api.post('/uploads', {
    data: { fileName: 'navigation.mp3', sizeBytes: 1024, mediaType: 'music' },
  });
  const walked = walkedPast(page, posting.then((s) => s.id));
  const session = await posting;
  try {
    await walked;
    // Walked, not entered: the list is what this client saw while it ran.
    await app.nav.to('notifications');
    await expect(app.shell.notificationRow('upload')).toBeVisible({ timeout: T.fetch });
    await clickThrough(
      app.shell.notificationRow('upload'),
      app.shell.control(SemanticsIds.uploadsScreen),
    );
    await app.nav.expectAt('uploads');

    await app.nav.arrow('notifications');
    await app.nav.expectAt('notifications');

    // A step back made by the browser leaves the row's place ahead of it.
    await app.nav.forward('uploads');
    await app.nav.expectAt('uploads');

    // And forward did not cost the app its list.
    await app.nav.arrow('notifications');
    await app.nav.expectAt('notifications');
  } finally {
    await app.api.delete('/uploads/{uploadId}', { path: { uploadId: session.id } });
  }
});

test('a search refined twice is one entry, which back leaves', async ({ app }) => {
  await app.nav.enter('home');
  await app.search.open();
  await app.search.refine('Alph');
  await app.search.refine('Alpha');

  await app.nav.back('home');
  await app.nav.expectAt('home');
});

test('smoke check: the arrow after a tab tap returns to the tab left', async ({ app }) => {
  // The Music tab restores the album it was left on, which is how the
  // router sees a browser back as well; no popstate fires for a tap, so
  // the browser never offers the misreading, which the widget tests pin.
  await app.nav.enter('albums');
  await app.music.openBucket(0);
  const album = new URL(app.nav.location()).pathname;
  await app.nav.to('podcasts');
  await app.nav.tab('music', app.music.entry(0));
  expect(new URL(app.nav.location()).pathname).toBe(album);

  await app.nav.arrow('podcasts');
  await app.nav.expectAt('podcasts');
});

test('a browser back to the link the tab opened on leaves nothing behind it', async ({
  app,
}) => {
  // Only the browser saying it moved tells this back from a visit: read
  // as one, the album would be a new visit after Podcasts, and the arrow
  // would go there instead of up to the albums. Opened cold on a fresh
  // page, so the album is the first entry the app made.
  const { items } = await app.api.get('/library/items', {
    query: { mediaType: 'music', limit: 50 },
  });
  const track = items.find((item) => item.albumPid);
  expect(track, 'a track on an album').toBeDefined();
  await app.music.openAlbumOf(track!.pid);
  const album = new URL(app.nav.location()).pathname;
  await app.nav.to('podcasts');

  await app.nav.back(app.music.entityPlay());
  expect(new URL(app.nav.location()).pathname).toBe(album);
  await app.nav.arrow('albums');
  await app.nav.expectAt('albums');
});

test('two quick presses of the arrow from the second entry of the app stay in it', async ({
  app,
}) => {
  // The first press steps the browser back to the app's first entry; the
  // second, on whatever screen it lands on, finds no entry of the app
  // behind and goes up the router's way instead of out of the tab.
  // Opened cold on a fresh page, so the album is the first entry the app
  // made.
  const { items } = await app.api.get('/library/items', {
    query: { mediaType: 'music', limit: 50 },
  });
  const track = items.find((item) => item.albumPid);
  expect(track, 'a track on an album').toBeDefined();
  await app.music.openAlbumOf(track!.pid);
  const origin = new URL(app.nav.location()).origin;
  await app.nav.markDocument();
  await app.nav.to('tasks');

  await app.nav.arrowTwice(40);

  const rest = await app.nav.settled();
  expect(rest.origin, 'still the app').toBe(origin);
  expect(await app.nav.sameDocument(), 'the same document').toBe(true);
});

test('the player closed is behind nothing back lands on, and ahead of forward', async ({
  app,
}) => {
  // A router pop is a new browser entry, so the entry behind would be
  // the player just closed; the close is the browser's back instead.
  await app.nav.enter('albums');
  await app.music.openBucket(0);
  await app.music.playEntry(0);
  await app.player.pause();
  await app.player.collapse(app.queue.deckBar());

  await app.nav.back('albums');
  await expect(app.player.toggle()).toBeHidden();
  await app.nav.forward(app.music.entry(0));
  await app.nav.forward(app.player.toggle());

  await app.player.collapse(app.queue.deckBar());
  await app.nav.arrow('albums');
  await expect(app.player.toggle()).toBeHidden();
});

test('a browser back with a dialog up closes it and leaves the page where it is', async ({
  app,
}) => {
  // Every other back closes a dialog first. The browser's own does too,
  // and goes forward again beneath it, so the page and its entry stay.
  await app.nav.enter('home');
  await app.nav.to('playlists');
  const add = app.shell.control(SemanticsIds.playlistAdd);
  const confirm = app.shell.control(SemanticsIds.playlistCreateConfirm);
  await clickThrough(add, confirm);

  await app.nav.back(add);
  await expect(confirm).toBeHidden({ timeout: T.assert });
  await app.nav.expectAt('playlists');

  await app.nav.back('home');
  await app.nav.expectAt('home');
});

test('a browser back passes over an entry the app forgot', async ({ app, page }) => {
  // Two panes, the queue beside the entry open. A second entry opened
  // over the first, and the first skipped from the keyboard while the
  // second stays open: the app forgets it, the browser keeps its entry,
  // and back from the second never shows it.
  await page.setViewportSize({ width: 1600, height: 1000 });
  const { items } = await app.api.get('/library/items', {
    query: { mediaType: 'music', limit: 50 },
  });
  // From the end, away from the first rows other specs rematch, and on
  // two releases, each its own entry.
  const pids: string[] = [];
  const releases = new Set<string>();
  for (const item of [...items].reverse()) {
    const release = item.albumPid ?? item.pid;
    if (pids.length === 2 || releases.has(release)) continue;
    releases.add(release);
    pids.push(item.pid);
  }
  expect(pids, 'two music items on two releases').toHaveLength(2);
  const ids: string[] = [];
  try {
    for (const pid of pids) {
      ids.push((await app.api.post('/items/{pid}/rematch', { path: { pid } })).reviewEntryId);
    }
    expect(new Set(ids).size, 'two entries').toBe(2);
    for (const entryId of ids) {
      await expect
        .poll(
          async () => {
            const entry = await app.api.tryGet('/review/queue/{entryId}', {
              path: { entryId },
            });
            if (entry === undefined) return 'missing';
            return entry.identifying ? 'identifying' : entry.status;
          },
          { timeout: T.fetch, message: 'the entry should settle to pending' },
        )
        .toBe('pending');
    }
    await app.nav.enter('home');
    await app.nav.to('review');
    // `k` from the lower row moves the cursor onto the upper, so nothing
    // else may sit between them.
    const order = await app.review.rowIds();
    const [upper, lower] = [...ids].sort((a, b) => order.indexOf(a) - order.indexOf(b));
    expect(order.indexOf(upper), 'on screen').toBeGreaterThanOrEqual(0);
    expect(order.indexOf(lower), 'the two rows are neighbours').toBe(order.indexOf(upper) + 1);
    await app.review.open(upper);
    await app.review.open(lower);
    await expect.poll(() => app.nav.location(), { timeout: T.nav }).toContain(lower);

    await app.review.press('k');
    await app.review.press('s');
    await expect
      .poll(
        async () =>
          (await app.api.tryGet('/review/queue/{entryId}', { path: { entryId: upper } }))
            ?.status,
        { timeout: T.fetch, message: 'the key should skip the upper entry' },
      )
      .toBe('skipped');
    // The server having it is not the app having heard: its row leaves
    // the queue once it has, and only then is the entry forgotten. A back
    // before that lands on an entry the app still holds.
    await expect(app.review.row(upper)).toBeHidden({ timeout: T.assert });
    expect(app.nav.location(), 'the pane stays on the open entry').toContain(lower);

    await app.nav.back('review');

    await app.nav.settledAt('review');
    await expect(app.review.pane()).toBeHidden({ timeout: T.assert });
  } finally {
    for (const entryId of ids) {
      const entry = await app.api.tryGet('/review/queue/{entryId}', { path: { entryId } });
      if (entry?.status === 'pending') {
        await app.api.post('/review/queue/{entryId}/decide', {
          path: { entryId },
          data: { action: 'as-is' },
        });
      }
    }
  }
});

test('a browser back from a playlist deleted on its own screen passes the list', async ({
  app,
}) => {
  // Opened from the list and deleted there, the playlist leaves by a
  // router pop, an entry of the list after its own: one back passes the
  // playlist's entry and the list's first, to the screen before the list.
  const name = 'Deleted on its own screen';
  await app.seed.clearPlaylistsNamed(name);
  const pid = await app.seed.createPlaylist(name);
  try {
    await app.nav.enter('home');
    await app.nav.to('tasks');
    await app.nav.to('playlists');
    await app.playlists.openShowing(pid, app.playlists.overflow());
    await app.playlists.fromOverflow(
      app.playlists.control(SemanticsIds.playlistDelete),
      app.playlists.control(SemanticsIds.playlistDeleteConfirm),
    );
    await clickThrough(
      app.playlists.control(SemanticsIds.playlistDeleteConfirm),
      app.playlists.add(),
    );
    await app.nav.expectAt('playlists');
    await expect(app.playlists.row(pid)).toHaveCount(0);

    await app.nav.back('tasks');

    await app.nav.settledAt('tasks');
  } finally {
    await app.seed.clearPlaylistsNamed(name);
  }
});

test('a browser back then forward leaves the arrow going where it went before', async ({
  app,
}) => {
  // Opened cold, so nothing is behind Notifications: read as visits of
  // their own, the two moves would put Tasks behind it.
  await app.nav.enter('notifications');
  await app.nav.to('tasks');
  await app.nav.back('notifications');
  await app.nav.forward('tasks');

  await app.nav.arrow('notifications');
  await app.nav.expectAt('notifications');
  await app.nav.arrow('home');
  await app.nav.expectAt('home');
});

test('a browser back after signing out leaves the app rather than the sign-in screen', async ({
  app,
  page,
}) => {
  // Signed out, each entry the session left is answered by the sign-in
  // screen, which the router would report as one more entry, so a Back
  // landed on the sign-in screen again. The app passes them instead, and
  // leaving is what Back means from a sign-in screen.
  await app.nav.enter('home');
  const origin = new URL(app.nav.location()).origin;
  await app.nav.to('tasks');
  await app.nav.to('notifications');
  await app.auth.signOut();
  await app.auth.expectAtLogin();
  const entries = await page.evaluate(() => history.length);

  await app.nav.backOutOf(origin);

  expect(await page.evaluate(() => history.length), 'no entry minted').toBe(entries);
});

test.describe('signed out', () => {
  test.use({ session: 'signed-out' });

  test('signup left by the arrow or by browser back is the login form again', async ({
    app,
  }) => {
    // Either way out answers the login form's await with nothing, which
    // it ignores, so the answer is the widget tests' to pin; this pins
    // that both land on the form and that it opens signup again.
    await app.auth.enterLogin();
    const login = app.auth.field('username');
    const open = app.auth.control(SemanticsIds.signupOpen);
    const signup = app.auth.control(SemanticsIds.signupUsername);

    await clickThrough(open, signup);
    await app.nav.arrow(login);
    await app.auth.expectAtLogin();

    await clickThrough(open, signup);
    await app.nav.back(login);
    await app.auth.expectAtLogin();
  });

  test('signup left by its own success fills in the login form that opened it', async ({
    app,
  }) => {
    // The login form awaits the signup it opens and fills in the name it
    // is handed. Success leaves by a pop, on the web the browser's back,
    // so the name rides that browser move: only the password is typed.
    // A walk-up account, as signup-ui's: what the invite produced.
    const invite = await app.api.post('/invites', {
      data: { note: 'navigation walk-up', maxUses: 1 },
    });
    const username = `walkup-nav-${Date.now().toString(36)}`;
    const password = 'walkup-pass-123';
    await app.auth.enterLogin();
    await app.auth.signUpViaForm({ username, password, invite: invite.token });

    await typeInto(app.page, app.auth.control(SemanticsIds.loginPassword), password);
    await app.auth.control(SemanticsIds.loginSubmit).click();
    await expect(app.auth.control(SemanticsIds.navRegion)).toBeVisible({ timeout: T.nav });
  });
});

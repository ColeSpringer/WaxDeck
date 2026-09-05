import { test, expect } from './fixtures';
import { T } from './driver/budgets';

// The synced-playlist loop over the real stack: bind a manual playlist
// to the stubbed source the stack launches beside feedserv, preview the
// dry run, sync, and watch the entries ride the review queue in. Its
// own file rather than a playlists.spec.ts test because the downloads
// need the upload right, which a minted plain user does not hold - the
// same reason uploads.spec.ts runs under an admin-shaped account.
test('a manual playlist binds to a source, previews, and syncs its entries in', async ({ app }) => {
  // The stubbed acquisition source the stack launches beside feedserv.
  // Everything mutated here is this account's own: its playlist, its
  // identify preference, its review-queue traffic.
  const SOURCE_URL = 'http://127.0.0.1:4422/playlist';
  const name = 'Stub Mirror';
  await app.seed.clearPlaylistsNamed(name);
  const pid = await app.seed.createPlaylist(name);
  // Downloads ride the review queue; this account opts its own
  // submissions out of identification so they file themselves and the
  // attach is observable without a review round trip.
  await app.api.put('/users/me/prefs', { data: { identifyOptOut: true } });

  try {
    await app.nav.enter('playlists');
    await app.playlists.openShowing(pid, app.playlists.addField());
    await app.playlists.openSyncSheet();
    await app.playlists.bindSource(SOURCE_URL);

    // The dry run before anything ran: the stub lists three entries,
    // none of them in the library yet.
    await app.playlists.syncPreviewButton().click();
    await expect(app.playlists.syncPreviewDialog()).toBeVisible();
    // Either sentence, deliberately: on a reused stack (CI's retry, a
    // developer's second run) the earlier run's tracks and map rows
    // survive the playlist teardown, so the same dry run reports three
    // attaches instead of three downloads. Both are the correct
    // preview of the state the stack is actually in.
    await expect(
      app.playlists.text(
        /3 (new entries would be downloaded|tracks would join the list)/,
      ),
    ).toBeVisible();
    await app.playlists.text('OK').click();

    // Sync now, then close the sheet: the status chip lives on the
    // screen underneath, whose semantics the modal barrier prunes.
    await app.playlists.syncNow().click();
    await app.playlists.dismissSheet(app.playlists.syncChip());

    // The entries join once their as-is imports settle, which a later
    // run attaches. Re-syncing while polling is what a person would
    // do, and the server answers an in-flight run with the same task
    // rather than stacking a second.
    // Read first, sync only while short: the iteration that observes
    // three members must not have queued one more run behind itself,
    // or that run's clean success overwrites the counts the closing
    // assertion reads.
    await expect
      .poll(
        async () => {
          const page = await app.api.get('/playlists/{pid}/items', {
            path: { pid },
          });
          const got = (page.entries ?? []).length;
          if (got < 3) {
            await app.api.post('/playlists/{pid}/source/sync', {
              path: { pid },
            });
          }
          return got;
        },
        { timeout: T.fetch, intervals: [T.live] },
      )
      .toBe(3);

    // The mirrored membership shows in source order.
    await app.nav.enter('playlists');
    await app.playlists.openShowing(pid, app.playlists.entry(0));
    await expect(app.playlists.entry(0)).toContainText('Stub Cut 1');
    await expect(app.playlists.entry(2)).toContainText('Stub Cut 3');

    // The binding reports the run it made.
    const source = await app.api.get('/playlists/{pid}/source', { path: { pid } });
    expect(source.live).toBe(true);
    expect(source.disabled).toBe(false);
    expect(source.lastRun?.added).toBe(3);
  } finally {
    await app.api.put('/users/me/prefs', { data: { identifyOptOut: false } });
    await app.seed.clearPlaylistsNamed(name);
  }
});

test('a bound export re-saves its settings without being handed the export again', async ({
  app,
}) => {
  // The settings-only form: a matched binding's export is not stored
  // anywhere a client can read back, so a mode flip that replaced the
  // binding whole would have to ask for the paste again.
  const name = 'Resaved Export';
  await app.seed.clearPlaylistsNamed(name);
  const pid = await app.seed.createPlaylist(name);

  try {
    await app.nav.enter('playlists');
    await app.playlists.openShowing(pid, app.playlists.addField());
    await app.playlists.openSyncSheet();
    await app.playlists.bindExport(
      'text',
      'Salt Harbour - The Bree Trio\nNobody Here - Never Recorded',
    );

    const bound = await app.api.get('/playlists/{pid}/source', { path: { pid } });
    expect(bound.live).toBe(false);
    expect(bound.source).toBe('text');
    expect(bound.refCount).toBe(2);

    await app.playlists.saveSyncMode('append');

    await expect
      .poll(
        async () => await app.api.tryGet('/playlists/{pid}/source', { path: { pid } }),
        { timeout: T.fetch },
      )
      // The mode moved and the refs did not: the server kept the
      // binding under the settings.
      .toMatchObject({ mode: 'append', source: 'text', refCount: 2 });
  } finally {
    await app.seed.clearPlaylistsNamed(name);
  }
});

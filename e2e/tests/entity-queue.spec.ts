import { test, expect } from './fixtures';

// The entity screens and the queue surface over the real stack: an
// artist bucket opening the artist rather than a filtered list, an
// album playing from a row, and the queue answering the player's
// control with something that can be reordered and cleared.

test('an album is its own location, and playing a row queues the album', async ({
  app,
}) => {
  await app.nav.enter('albums');
  await app.music.openEntity(0);

  // The album's own pid in the address bar: an entity screen, not a
  // filtered listing, at the location the index already handed over.
  const shared = app.nav.location();
  expect(shared).toMatch(/\/music\/albums\/al-/);

  // And a reload lands back on it, which is what makes it a link.
  await app.nav.reload(app.music.entityPlay());
  expect(app.nav.location()).toBe(shared);

  // Shuffle is the first one in the app, and it starts playback rather
  // than only setting a toggle.
  await app.music.playEntity('shuffle');
});

test('an artist bucket opens the artist, not a filtered list', async ({ app }) => {
  await app.nav.enter('artists');
  await app.music.openEntity(0);

  // The entity's own pid, and the entity's own screen behind it: the
  // header's verbs are what a listing at this location never had.
  expect(app.nav.location()).toMatch(/\/music\/artists\/ar-/);
  await expect(app.music.entityPlay()).toBeVisible();

  // The bucket the fixture library sorts first is an audiobook author,
  // which is exactly the case a music-only screen gets wrong: the list
  // has to hold what the bucket counted, and the verbs have to be off
  // rather than queueing a twelve-hour file.
  await expect(app.music.text('Audiobooks')).toBeVisible();
  await expect(app.music.entityPlay()).toBeDisabled();
});

test('the queue is a place, and it reorders and clears', async ({ app }) => {
  // Something to queue: an album played from its first row.
  await app.nav.enter('albums');
  await app.music.openBucket(0);
  await app.music.playEntry(0);

  await app.queue.openFromPlayer();

  // It names where the queue came from, and what follows the current
  // entry can be dragged.
  await expect(app.queue.text(/Playing from /)).toBeVisible();
  await expect(app.queue.dragHandles()).not.toHaveCount(0);

  // Clearing empties it, and the surface says so rather than going
  // blank. Exact, not "fewer than before": the queue belongs to this
  // test's own account and nothing else is writing to it.
  await app.queue.clear().click();
  await expect(app.queue.text('Nothing queued')).toBeVisible();

  // And the location resolves for anyone who types it. Cold, on the web
  // build, that is an empty queue: the queue persists to the local
  // mirror and the web build has none, so a launch there offers the
  // server's last session to resume rather than restoring a queue. The
  // surface says so instead of going blank, which is the assertion.
  await app.nav.enter('queue');
  await expect(app.queue.text('Nothing queued')).toBeVisible();
});

// The other half of the open pair: picking a row up on a
// listing and dropping it on the panel. Pointer only by decision, so
// this is a coordinate drag with no semantics node to click instead -
// quarantine-eligible if a synthetic drag turns out to flake, and
// covered by widget tests either way.
test('a listing row can be dragged into the queue panel', async ({ app }) => {
  // Something playing, so the panel has a queue in it and the drop is
  // an append rather than the start of a session.
  await app.nav.enter('albums');
  await app.music.openBucket(0);
  await app.music.playEntry(0);

  // Down from the player and across in-app, never by URL: a cold load
  // restarts the web app, which reduces live playback to the deck
  // bar's resume offer - and an offer has no queue control to open the
  // panel with. Collapsing restores the chrome the pushed player was
  // covering.
  await app.player.collapse(app.queue.deckBar());
  await app.nav.to('tracks');
  await app.queue.openPanel();

  const before = await app.queue.dragHandles().count();
  await app.queue.dragOntoPanel(app.music.anyItem());

  // One more row after the current entry, and the panel says what it
  // took. The queue is client-local, so this is this browser's own
  // count and needs no serialization against the shared server.
  await expect(app.queue.text(/Added .* to the queue/)).toBeVisible();
  await expect(app.queue.dragHandles()).toHaveCount(before + 1);
});

test('a set of up-next rows can be picked, moved, and dropped', async ({
  app,
}) => {
  // The queue is client-local, so this needs no serialization against
  // the shared server: what it picks belongs to this browser.
  await app.nav.enter('albums');
  await app.music.openBucket(0);
  await app.music.playEntry(0);
  // Paused before anything is counted: this is about what a selection
  // does to a queue, and the fixture tracks are seconds long, so a
  // running clock drains the up-next rows out from under the assertions
  // while they are being made.
  await app.player.pause();
  await app.queue.openFromPlayer();

  const handles = app.queue.dragHandles();
  await expect(handles).not.toHaveCount(0);
  const upNext = await handles.count();
  // Nothing picked means no mode: an empty set is not a selection.
  await expect(app.queue.selectBoxes()).toHaveCount(0);
  await expect(app.queue.selectionRemove()).toHaveCount(0);

  // A long press on an up-next row starts one, and every up-next row
  // joins in - the current entry and the history stay out of scope.
  const first = await app.queue.firstUpNextId();
  await app.queue.pick(first);
  await expect(app.queue.selectBoxes()).toHaveCount(upNext);
  await expect(app.queue.text('1 selected')).toBeVisible();

  // The set's verbs act on the whole of it in one go. Move to top is
  // the one worth driving here: it is the reorder a selection exists
  // for, and the row it moves is still there afterwards.
  await app.queue.selectionTop().click();
  await expect(app.queue.entry(first)).toBeVisible();
  await expect(app.queue.text('1 selected')).toBeVisible();

  // Removing takes the set and ends the mode.
  await app.queue.selectionRemove().click();
  await expect(app.queue.entry(first)).toHaveCount(0);
  await expect(app.queue.selectBoxes()).toHaveCount(0);

  // And Escape ends a selection without leaving the screen.
  const next = await app.queue.firstUpNextId();
  await app.queue.pick(next);
  await expect(app.queue.selectBoxes()).not.toHaveCount(0);
  await app.queue.escape();
  await expect(app.queue.selectBoxes()).toHaveCount(0);
  await expect(app.queue.screen()).toBeVisible();
});

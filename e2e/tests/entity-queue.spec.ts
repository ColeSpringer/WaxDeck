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

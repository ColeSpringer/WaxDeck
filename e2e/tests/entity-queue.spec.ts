import { test, expect, Page } from './fixtures';
import {
  ADMIN_PASS,
  ADMIN_USER,
  clickInView,
  clickThrough,
  ensureAdmin,
  typeInto,
  waitForLibrary,
} from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The entity screens and the queue surface over the real stack: an
// artist bucket opening the artist rather than a filtered list, an
// album playing from a row, and the queue answering the deck bar's
// control with something that can be reordered and cleared.

async function login(page: Page) {
  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, ADMIN_USER);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), ADMIN_PASS);
  await page.getByRole('button', { name: 'Log in' }).click();
  await page.locator(sem(SemanticsIds.navDestination('music'))).waitFor({ timeout: 30_000 });
}

test('an album is its own location, and playing a row queues the album', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  await login(page);

  await page.goto('/music/albums');
  await clickThrough(
    page.locator(sem(SemanticsIds.indexBucket(0))),
    page.locator(sem(SemanticsIds.entityPlay)),
  );
  // The album's own pid in the address bar: an entity screen, not a
  // filtered listing, at the location the index already handed over.
  await expect(page).toHaveURL(/\/music\/albums\/al-/);
  const shared = page.url();

  // And a reload lands back on it, which is what makes it a link.
  await page.reload();
  await page.locator(sem(SemanticsIds.entityPlay)).waitFor({ timeout: 30_000 });
  expect(page.url()).toBe(shared);

  // Shuffle is the first one in the app, and it starts playback rather
  // than only setting a toggle.
  await clickThrough(
    page.locator(sem(SemanticsIds.entityShuffle)),
    page.locator(sem(SemanticsIds.playerToggle)),
  );
});

test('an artist bucket opens the artist, not a filtered list', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  await login(page);

  await page.goto('/music/artists');
  await clickThrough(
    page.locator(sem(SemanticsIds.indexBucket(0))),
    page.locator(sem(SemanticsIds.entityShuffle)),
  );
  // The entity's own pid, and the entity's own screen behind it: the
  // header's verbs are what a listing at this location never had.
  await expect(page).toHaveURL(/\/music\/artists\/ar-/);
  await expect(page.locator(sem(SemanticsIds.entityPlay))).toBeVisible();

  // The bucket the fixture library sorts first is an audiobook author,
  // which is exactly the case a music-only screen gets wrong: the list
  // has to hold what the bucket counted, and the verbs have to be off
  // rather than queueing a twelve-hour file.
  await expect(page.getByText('Audiobooks')).toBeVisible({ timeout: 15_000 });
  await expect(page.locator(sem(SemanticsIds.entityPlay))).toBeDisabled();
});

test('the queue is a place, and it reorders and clears', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  await login(page);

  // Something to queue: an album played from its first row.
  await page.goto('/music/albums');
  await clickThrough(
    page.locator(sem(SemanticsIds.indexBucket(0))),
    page.locator(sem(SemanticsIds.indexItem(0))),
  );
  await clickThrough(
    page.locator(sem(SemanticsIds.indexItem(0))),
    page.locator(sem(SemanticsIds.playerToggle)),
  );

  // Opened from the player rather than from the deck bar, whose control
  // at this width toggles the panel instead: over the shell there is no
  // panel slot to use, so the player's own control pushes the queue's
  // screen, which is the surface under test. Not by `goto` either, since
  // the path-URL flip made that a real page load - it would restart the
  // app and take the queue with it, which is the next assertion's job
  // rather than this one's.
  // clickInView rather than clickThrough, because this control is one
  // small glyph in a row of them on a screen that animates in from
  // below: a forced click against a rect read a moment earlier lands on
  // the neighbour, and the neighbour is Discover, whose menu then covers
  // the queue button so every retry clicks the barrier instead. Seen
  // once. clickInView re-reads the box each attempt and refuses to click
  // until it is fully in view.
  await clickInView(page, page.locator(sem(SemanticsIds.playerQueue)), {
    settled: page.locator(sem(SemanticsIds.queueShuffle)),
  });
  await page.locator(sem(SemanticsIds.queueShuffle)).waitFor({ timeout: 30_000 });

  // It names where the queue came from, and what follows the current
  // entry can be dragged.
  await expect(page.getByText(/Playing from /)).toBeVisible({ timeout: 15_000 });
  await expect(page.locator('[flt-semantics-identifier^="queue-entry-drag-"]'))
    .not.toHaveCount(0);

  // Clearing empties it, and the surface says so rather than going
  // blank.
  await page.locator(sem(SemanticsIds.queueClear)).click();
  await expect(page.getByText('Nothing queued')).toBeVisible({ timeout: 15_000 });

  // And the location resolves for anyone who types it. Cold, on the web
  // build, that is an empty queue: the queue persists to the local
  // mirror and the web build has none, so a launch there offers the
  // server's last session to resume rather than restoring a queue. The
  // surface says so instead of going blank, which is the assertion.
  await page.goto('/queue');
  await expect(page.getByText('Nothing queued')).toBeVisible({ timeout: 30_000 });
});

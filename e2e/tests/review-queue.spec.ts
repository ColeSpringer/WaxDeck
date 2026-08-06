import { test, expect } from './fixtures';
import { J, T } from './driver';

// The curation journey: seed a pending review entry by requesting a
// rematch of a scanned track (the stack runs with matching off, so the
// entry stays pending with no network lookups), then drive the
// keyboard-first review queue in the web UI to select, open, and
// decide it. This exercises the app's first shortcuts layer and the
// review surface end to end.

test('review a queued match with the keyboard', async ({ app }) => {
  test.setTimeout(J.long);

  // Seed a pending entry through the API: a rematch queues one unit.
  const music = await app.api.get('/library/items', {
    query: { mediaType: 'music', limit: 1 },
  });
  const pid = (music.items ?? [])[0]?.pid;
  expect(pid, 'the fixture library should hold a music item to rematch').toBeTruthy();
  const rematch = await app.api.post('/items/{pid}/rematch', { path: { pid: pid! } });
  const entryId = rematch.reviewEntryId;
  expect(entryId).toMatch(/^rv-/);

  // The entry settles to pending (matching is off, so the identify
  // worker closes it with no candidates rather than auto-applying).
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

  // The queue has a curation row of its own in the chrome; walked
  // rather than entered, because reaching a daily surface in one click
  // is part of what it is.
  await app.nav.to('review');

  // The cursor is put on this spec's own row by opening it, never
  // assumed to be at the top: the queue is server-global and
  // newest-first, so an entry another worker seeds sorts in above this
  // one - per-test accounts do not change that, because a rematch is a
  // catalog decision rather than a per-listener one. Escape returns to
  // the queue with the cursor where the open entry left it and `e`
  // reopens it, but nothing re-anchors the cursor once the pane is
  // closed, so an entry arriving between the two keys shifts this row
  // down and `e` opens its neighbour. The whole round repeats in that
  // case: re-opening this row by hand is what puts the cursor back.
  //
  // Cursor movement itself (j, k, arrows) is covered deterministically
  // in review_screen_test.dart, over a queue that holds still.
  await expect(async () => {
    await app.review.open(entryId);
    expect(app.nav.location(), 'this row is what opened').toContain(entryId);
    await app.review.press('Escape');
    await expect(app.review.asIs()).toBeHidden();
    await app.review.press('e');
    await app.review.asIs().waitFor({ timeout: T.assert });
    expect(app.nav.location(), 'the cursor stayed on this entry').toContain(entryId);
  }).toPass({ timeout: T.fetch });

  // The entry screen offers the as-is decision (no candidates to
  // approve). Accept it, which returns to the queue.
  await app.review.asIs().click();

  // The entry is decided: it leaves the pending queue, and the API
  // agrees.
  await expect
    .poll(
      async () =>
        (await app.api.tryGet('/review/queue/{entryId}', { path: { entryId } }))?.status ??
        'missing',
      { timeout: T.fetch, message: 'the entry should be decided as-is' },
    )
    .toBe('as-is');
});

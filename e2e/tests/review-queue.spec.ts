import { test, expect, APIRequestContext } from './fixtures';
import {
  ADMIN_PASS,
  ADMIN_USER,
  authed,
  clickThrough,
  ensureAdmin,
  typeInto,
  waitForLibrary,
} from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The curation journey: seed a pending review entry by requesting a
// rematch of a scanned track (the stack runs with matching off, so the
// entry stays pending with no network lookups), then drive the
// keyboard-first review queue in the web UI to select, open, and
// decide it. This exercises the app's first shortcuts layer and the
// review surface end to end.


async function firstMusicPid(
  request: APIRequestContext,
  token: string,
): Promise<string> {
  const resp = await request.get(
    '/api/v1/library/items?mediaType=music&limit=1',
    authed(token),
  );
  expect(resp.ok()).toBeTruthy();
  const items = (await resp.json()).items ?? [];
  expect(items.length).toBeGreaterThan(0);
  return items[0].pid;
}

test('review a queued match with the keyboard', async ({ page, request }) => {
  test.setTimeout(180_000);
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);

  // Seed a pending entry through the API: a rematch queues one unit.
  const pid = await firstMusicPid(request, token);
  const rematch = await request.post(
    `/api/v1/items/${pid}/rematch`,
    authed(token),
  );
  expect(rematch.status()).toBe(202);
  const entryId = (await rematch.json()).reviewEntryId as string;
  expect(entryId).toMatch(/^rv-/);

  // The entry settles to pending (matching is off, so the identify
  // worker closes it with no candidates rather than auto-applying).
  await expect
    .poll(
      async () => {
        const resp = await request.get(
          `/api/v1/review/queue/${entryId}`,
          authed(token),
        );
        if (!resp.ok()) return 'missing';
        const entry = await resp.json();
        return entry.identifying ? 'identifying' : entry.status;
      },
      { timeout: 30_000, message: 'the entry should settle to pending' },
    )
    .toBe('pending');

  // Log in through the UI.
  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, ADMIN_USER);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), ADMIN_PASS);
  await page.getByRole('button', { name: 'Log in' }).click();

  // Open the review queue through the sidebar's curation group.
  await clickThrough(
    page.locator(sem(SemanticsIds.navGroup('curation'))),
    page.locator(sem(SemanticsIds.navDestination('review'))),
  );
  const row = page.locator(sem(SemanticsIds.reviewRow(entryId)));
  await clickThrough(
    page.locator(sem(SemanticsIds.navDestination('review'))),
    row,
  );

  // The cursor is put on this spec's own row by opening it, never
  // assumed to be at the top: the queue is shared and newest-first, so
  // an entry another worker seeds sorts in above this one. Escape
  // returns to the queue with the cursor where the open entry left it
  // and `e` reopens it - but nothing re-anchors the cursor once the pane
  // is closed, so an entry arriving between the two keys shifts this row
  // down and `e` opens its neighbour. The whole round repeats in that
  // case: re-opening this row by hand is what puts the cursor back.
  //
  // Cursor movement itself (j, k, arrows) is covered deterministically
  // in review_screen_test.dart, over a queue that holds still.
  const asIs = page.locator(sem(SemanticsIds.reviewAsIs));
  await expect(async () => {
    await row.click({ force: true });
    await asIs.waitFor({ timeout: 15_000 });
    expect(page.url(), 'this row is what opened').toContain(entryId);
    await page.keyboard.press('Escape');
    await expect(asIs).toBeHidden({ timeout: 15_000 });
    await page.keyboard.press('e');
    await asIs.waitFor({ timeout: 15_000 });
    expect(page.url(), 'the cursor stayed on this entry').toContain(entryId);
  }).toPass({ timeout: 60_000 });

  // The entry screen offers the as-is decision (no candidates to
  // approve). Accept it, which returns to the queue.
  await asIs.click();

  // The entry is decided: it leaves the pending queue, and the API
  // agrees.
  await expect
    .poll(
      async () => {
        const resp = await request.get(
          `/api/v1/review/queue/${entryId}`,
          authed(token),
        );
        if (!resp.ok()) return 'missing';
        return (await resp.json()).status;
      },
      { timeout: 30_000, message: 'the entry should be decided as-is' },
    )
    .toBe('as-is');
});

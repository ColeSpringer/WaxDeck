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

  // Open the review queue through the curation menu.
  await clickThrough(
    page.locator(sem(SemanticsIds.curationMenu)),
    page.locator(sem(SemanticsIds.curationReview)),
  );
  await clickThrough(
    page.locator(sem(SemanticsIds.curationReview)),
    page.locator(sem(SemanticsIds.reviewRow(entryId))),
  );

  // Keyboard-first: j selects the first row, e opens it. The shortcuts
  // layer autofocuses the queue, so the keys reach it without a click.
  await page.keyboard.press('j');
  await page.keyboard.press('e');

  // The entry screen offers the as-is decision (no candidates to
  // approve). Accept it, which returns to the queue.
  const asIs = page.locator(sem(SemanticsIds.reviewAsIs));
  await asIs.waitFor({ timeout: 15_000 });
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

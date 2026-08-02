import { test, expect } from './fixtures';
import {
  ADMIN_PASS,
  ADMIN_USER,
  clickThrough,
  ensureAdmin,
  itemRow,
  typeInto,
  waitForLibrary,
} from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// Switching items mid-play must replace what the engine is playing.
// just_audio's web backend caches source players by playlist id, and the
// playlist the 0.10 API funnels every load through keeps one id for the
// player's whole life - so a second load on a live player found the
// stale cached player, kept the old element's src, applied the new
// initial position as a bare seek, and reported success: the old item
// played on under the new item's face while the new session checkpointed
// against it. The engine stops the platform player before every
// replacement now; this spec pins the observable half of that promise -
// the switched-to item's media is actually fetched.
test('switching tracks mid-play fetches the new media', async ({ page, request }) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);

  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, ADMIN_USER);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), ADMIN_PASS);
  await page.getByRole('button', { name: 'Log in' }).click();

  // The tracks index, and the first two rows it actually draws: a lazy
  // list only builds what its viewport holds, so the pair is read off
  // the screen rather than assumed from any listing order. Which two
  // tracks they are does not matter - the stale-player path triggered
  // on every load issued while the platform was still active, mid-play
  // or already run out (completed is not idle), so the fixtures'
  // few-second lengths do not matter either.
  await page
    .locator(sem(SemanticsIds.navDestination('music')))
    .waitFor({ timeout: 30_000 });
  await page.goto('/#/music/tracks');
  const rows = page.locator('[flt-semantics-identifier^="item-tr-"]');
  await rows.nth(1).waitFor({ timeout: 30_000 });
  const rowIds = (await rows.evaluateAll((els) =>
    els.map((e) => e.getAttribute('flt-semantics-identifier')),
  )) as string[];
  const a = { pid: rowIds[0].replace('item-', '') };
  const b = { pid: rowIds[1].replace('item-', '') };

  // Play the first track and see its media actually fetched.
  const mediaA = page.waitForRequest(
    (req) => req.url().includes('/media/') && req.url().includes(`pid=${a.pid}`),
    { timeout: 30_000 },
  );
  const rowA = await itemRow(page, a.pid);
  await clickThrough(rowA, page.locator(sem(SemanticsIds.playerToggle)));
  await mediaA;

  // Tap the second track and hold the switch to its promise: the engine
  // fetches the new media. Before the stop-first fix the web player
  // reported success while keeping the old stream loaded - the first
  // item played on (or replayed) under the second item's face - and
  // this request never happened.
  const mediaB = page.waitForRequest(
    (req) => req.url().includes('/media/') && req.url().includes(`pid=${b.pid}`),
    { timeout: 30_000 },
  );
  // The player screen sits over the tracks index; its own collapse
  // control pops it (browser history against flutter's navigator is
  // handled asynchronously and can pop the wrong thing).
  const rowB = page.locator(sem(SemanticsIds.item(b.pid)));
  await clickThrough(
    page.getByRole('button', { name: 'Collapse player' }).first(),
    rowB,
  );
  await rowB.click({ force: true });
  await mediaB;
});

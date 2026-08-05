import { test, expect, Page } from './fixtures';
import {
  authed,
  chooseFromMenu,
  clickThrough,
  ensureAdmin,
  loginAsAdmin,
  waitForLibrary,
} from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The landing surface over the real stack: shelves drawn from the
// discovery lists (two of which this phase added to the contract), the
// account menu in the top app bar rather than in the tab bar, and the
// shares list reached as a location beneath settings rather than pushed.

async function login(page: Page) {
  await loginAsAdmin(page, page.locator(sem(SemanticsIds.homeScreen)));
}

test('home draws its shelves off the collection lists', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  await login(page);

  // Recently added is unconditional on a library that has anything, and
  // Never played is the collection shelf this phase's contract change
  // exists for. Both are cards over items, so a fixture library with
  // scanned tracks has to draw them.
  await expect(
    page.locator(sem(SemanticsIds.shelf('recent'))),
  ).toBeVisible({ timeout: 30_000 });

  // Wheeled into the semantics tree rather than scrolled into view: the
  // shelves are slivers, so an off-screen one is not built at all and
  // has no element to scroll to.
  const sealed = page.locator(sem(SemanticsIds.shelf('sealed')));
  const viewport = page.viewportSize()!;
  await page.mouse.move(viewport.width / 2, viewport.height / 2);
  await expect(async () => {
    await page.mouse.wheel(0, 600);
    await expect(sealed).toBeVisible({ timeout: 1_000 });
  }).toPass({ timeout: 30_000 });

});

test('a shelf\'s Show all opens the enumeration behind it', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  await login(page);

  // Its own scenario rather than a step after the shelf sweep above:
  // that one wheels down to reach the shelves below the fold, and this
  // control is above it. Two tests, each failing for one reason.
  //
  // Clicked and checked as one unit rather than through clickThrough.
  // The shelves above this one arrive on their own schedule, and each
  // one that resolves pushes this control down a shelf's height: a
  // forced click skips the stability wait, so one dispatched into that
  // gap lands wherever the old rect now is. Under a full suite that is
  // the episodes shelf's own "Show all" and a trip to Podcasts, which
  // is why the click is answered by where it actually went rather than
  // by waiting out an enumeration that was never coming.
  const showAll = page.locator(sem(SemanticsIds.shelfAll('recent')));
  const tracks = /\/music\/tracks$/;
  const anyItem = page
    .locator(`[flt-semantics-identifier^="${SemanticsIds.item('')}"]`)
    .first();
  await expect(async () => {
    if (await anyItem.isVisible()) return;
    // Clicked again only when nothing is already on its way: an
    // enumeration still drawing is not a failed attempt, and navigating
    // home out from under it is the one thing this must not do.
    if (!tracks.test(page.url())) {
      // Home first where the last attempt left the app somewhere with no
      // handle on it; the handle only exists here. Since the path-URL
      // flip this is a whole engine reboot rather than a route change, so
      // the shelf is waited for rather than clicked at on a five-second
      // budget - otherwise every recovery spends an attempt proving the
      // app had not finished starting.
      if (!(await showAll.isVisible())) {
        await page.goto('/');
        await showAll.waitFor({ timeout: 30_000 });
      }
      await showAll.click({ timeout: 5_000, force: true });
      await expect(page).toHaveURL(tracks, { timeout: 5_000 });
    }
    await anyItem.waitFor({ timeout: 20_000 });
  }).toPass({ timeout: 60_000 });
  await expect(page).toHaveURL(tracks);
});

test('the account menu is in the app bar and still reaches settings', async ({
  page,
  request,
}) => {
  await ensureAdmin(request);
  // A phone: the width where the tab bar carries the domains and nothing
  // else, and where this control is the only route to everything that is
  // not one.
  await page.setViewportSize({ width: 420, height: 860 });
  await login(page);

  // In the top app bar, not in a tab-bar cell. The bar is above the
  // content and the tab bar is below it, so the y coordinate is what
  // tells the two apart.
  const account = page.locator(sem(SemanticsIds.navAccount));
  await expect(account).toBeVisible({ timeout: 30_000 });
  const bar = await account.boundingBox();
  const tabs = await page.locator(sem(SemanticsIds.navRegion)).boundingBox();
  expect(bar!.y, 'the avatar sits above the tab bar').toBeLessThan(tabs!.y);

  // `chooseFromMenu`, not `clickThrough`: that helper re-clicks its
  // trigger while it waits, which for a menu closes the one it just
  // opened.
  await chooseFromMenu(
    account,
    page.locator(sem(SemanticsIds.navDestination('settings'))),
  );
  await expect(page).toHaveURL(/\/settings$/);
});

test('the shares list is a location under settings', async ({
  page,
  request,
}) => {
  await ensureAdmin(request);
  await login(page);

  // Opened from the Account section's own row, which goes rather than
  // pushes now that the location is declared beneath settings.
  await page.goto('/settings/account');
  await clickThrough(
    page.locator(sem(SemanticsIds.openShareLinks)),
    page.locator(sem(SemanticsIds.sharesEmpty)).or(
      page.locator(`[flt-semantics-identifier^="share-row-"]`).first(),
    ),
  );
  await expect(page).toHaveURL(/\/settings\/shares$/);

  // And a stranger opening the link cold gets the page with settings
  // underneath it, which is the whole point of the re-homing.
  await page.reload();
  await expect(
    page.locator(sem(SemanticsIds.sharesEmpty)).or(
      page.locator(`[flt-semantics-identifier^="share-row-"]`).first(),
    ),
  ).toBeVisible({ timeout: 30_000 });
  expect(page.url()).toMatch(/\/settings\/shares$/);
});

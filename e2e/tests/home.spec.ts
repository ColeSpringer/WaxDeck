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
  await clickThrough(
    page.locator(sem(SemanticsIds.shelfAll('recent'))),
    page.locator(`[flt-semantics-identifier^="${SemanticsIds.item('')}"]`).first(),
  );
  await expect(page).toHaveURL(/#\/music\/tracks$/);
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
  await expect(page).toHaveURL(/#\/settings$/);
});

test('the shares list is a location under settings', async ({
  page,
  request,
}) => {
  await ensureAdmin(request);
  await login(page);

  // Opened from the Account section's own row, which goes rather than
  // pushes now that the location is declared beneath settings.
  await page.goto('/#/settings/account');
  await clickThrough(
    page.locator(sem(SemanticsIds.openShareLinks)),
    page.locator(sem(SemanticsIds.sharesEmpty)).or(
      page.locator(`[flt-semantics-identifier^="share-row-"]`).first(),
    ),
  );
  await expect(page).toHaveURL(/#\/settings\/shares$/);

  // And a stranger opening the link cold gets the page with settings
  // underneath it, which is the whole point of the re-homing.
  await page.reload();
  await expect(
    page.locator(sem(SemanticsIds.sharesEmpty)).or(
      page.locator(`[flt-semantics-identifier^="share-row-"]`).first(),
    ),
  ).toBeVisible({ timeout: 30_000 });
  expect(page.url()).toMatch(/#\/settings\/shares$/);
});

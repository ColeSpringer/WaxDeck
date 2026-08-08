import { test, expect } from './fixtures';

// The landing surface over the real stack: shelves drawn from the
// discovery lists, the account menu in the top app bar rather than in the
// tab bar, and the shares list reached as a location beneath settings
// rather than pushed.

test('home draws its shelves off the collection lists', async ({ app }) => {
  await app.nav.enter('home');

  // Recently added is unconditional on a library that has anything, and
  // Never played is the collection shelf the contract change exists for.
  // Both are cards over items, so a fixture library with scanned tracks
  // has to draw them - and this account has played nothing, so the
  // never-played shelf is not merely likely, it is certain.
  await expect(app.home.shelf('recent')).toBeVisible();

  // Wheeled into the semantics tree rather than scrolled into view: the
  // shelves are slivers, so an off-screen one is not built at all and
  // has no element to scroll to.
  await app.home.revealShelf('sealed');
});

test("a shelf's Show all opens the enumeration behind it", async ({ app }) => {
  await app.nav.enter('home');

  // Its own scenario rather than a step after the shelf sweep above:
  // that one wheels down to reach the shelves below the fold, and this
  // control is above it. Two tests, each failing for one reason.
  await app.home.showAll('recent', 'tracks');
  await app.nav.expectAt('tracks');
});

test('the account menu is in the app bar and still reaches settings', async ({
  app,
  page,
}) => {
  // A phone: the width where the tab bar carries the domains and nothing
  // else, and where this control is the only route to everything that is
  // not one.
  await page.setViewportSize({ width: 420, height: 860 });
  await app.nav.enter('home');

  // In the top app bar, not in a tab-bar cell. The bar is above the
  // content and the tab bar is below it, so the y coordinate is what
  // tells the two apart.
  const account = app.shell.account();
  await expect(account).toBeVisible();
  const bar = await account.boundingBox();
  const tabs = await app.shell.region().boundingBox();
  expect(bar!.y, 'the avatar sits above the tab bar').toBeLessThan(tabs!.y);

  // Settings is a destination the menu carries at this width rather than
  // an account verb, so it keeps its own destination identifier.
  await app.nav.accountMenu();
  await app.shell.destination('settings').click();
  await app.nav.expectAt('settings');
});

test('the shares list is a location under settings', async ({ app }) => {
  await app.settings.enterSection('account', app.settings.setting('about'));

  // Opened from the Account section's own row, which goes rather than
  // pushes now that the location is declared beneath settings.
  await app.sharing.openFromSettings();
  expect(app.nav.location()).toMatch(/\/settings\/shares$/);

  // And a stranger opening the link cold gets the page with settings
  // underneath it, which is the whole point of the re-homing.
  await app.nav.reload(app.sharing.list());
  expect(app.nav.location()).toMatch(/\/settings\/shares$/);
});

test('an album pinned from its own screen turns up on home', async ({
  app,
}) => {
  // Per-account state, so this needs no serialization against the other
  // workers: a pin is in this worker's preference document and nobody
  // else's. Started from a known state rather than an assumed one -
  // accounts are minted from the test title and reused across runs, so a
  // run that failed after pinning would otherwise leave the next one
  // starting pinned, where the first toggle unpins and the assertion
  // fails for a reason that has nothing to do with the code.
  const prefs = await app.api.get('/users/me/prefs');
  await app.api.put('/users/me/prefs', {
    data: { ...prefs, pinned: [] },
  });

  await app.nav.enter('albums');
  await app.music.openEntity();
  const title = app.nav.location();

  await app.music.togglePin();
  await app.nav.enter('home');
  await app.home.revealShelf('pinned');

  // The pid is what the shelf card is addressed by, and it is the last
  // segment of the album's own location - which is the round trip the
  // whole thing rests on: a pid stored, resolved, and drawn.
  const pid = decodeURIComponent(title.split('/').pop()!);
  await expect(app.home.card('pinned', pid)).toBeVisible();

  // And unpinning from the album screen takes it away again, so the
  // shelf never accumulates what a listener meant to remove.
  await app.nav.open(title, app.music.entityShuffle());
  await app.music.togglePin();
  await app.nav.enter('home');
  await expect(app.home.shelf('pinned')).toBeHidden();
});

import { test, expect, APIRequestContext, Page } from './fixtures';
import {
  ADMIN_PASS,
  ADMIN_USER,
  clickThrough,
  ensureAdmin,
  openMusicSection,
  typeInto,
  waitForLibrary,
} from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The music domain over the real stack: the hub's ways in, an index in
// both of its orders with the alphabet rail beside the A-to-Z one, a
// bucket opening its own shareable location, and the search screen
// answering a query typed into the real field.

async function login(page: Page) {
  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, ADMIN_USER);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), ADMIN_PASS);
  await page.getByRole('button', { name: 'Log in' }).click();
  await page.locator(sem(SemanticsIds.navDestination('music'))).waitFor({ timeout: 30_000 });
}

test('the music hub opens an index, and a bucket is its own location', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  await login(page);

  // The hub is the music branch's root now; the sidebar's Music row goes
  // there rather than to the old browse tabs.
  await clickThrough(
    page.locator(sem(SemanticsIds.navDestination('music'))),
    page.locator(sem(SemanticsIds.musicTile('artists'))),
  );
  await expect(page).toHaveURL(/#\/music$/);

  await clickThrough(
    page.locator(sem(SemanticsIds.musicTile('artists'))),
    page.locator(sem(SemanticsIds.indexBucket(0))),
  );
  await expect(page).toHaveURL(/#\/music\/artists$/);

  // Artists lead A to Z, which is the only order the rail is honest
  // over, so it is drawn beside them.
  await expect(page.locator(sem(SemanticsIds.indexRail))).toBeVisible();

  // Opening a bucket puts it in the address bar as an entity pid: the
  // whole point of a location is that a stranger can open it.
  await clickThrough(
    page.locator(sem(SemanticsIds.indexBucket(0))),
    page.locator(sem(SemanticsIds.indexItem(0))),
  );
  await expect(page).toHaveURL(/#\/music\/artists\/ar-/);
  const shared = page.url();

  // And a reload lands back on the same list, which is what a shared
  // link has to do: nothing here rides an in-memory payload.
  await page.reload();
  await page.locator(sem(SemanticsIds.indexItem(0))).waitFor({ timeout: 30_000 });
  expect(page.url()).toBe(shared);
});

test('the sort toggle swaps the index order and the rail with it', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  await login(page);

  await page.goto('/#/music/artists');
  await page.locator(sem(SemanticsIds.indexBucket(0))).waitFor({ timeout: 30_000 });
  await expect(page.locator(sem(SemanticsIds.indexRail))).toBeVisible();

  const sorted: string[] = [];
  page.on('request', (r) => {
    if (r.url().includes('/library/facets')) sorted.push(r.url());
  });

  // Biggest-first is a listing of its own with its own cursor space -
  // the server refuses one carried across the toggle - and the rail goes
  // with it, because in count order the letters are scattered down the
  // list.
  await page.getByRole('button', { name: 'Most items' }).click();
  await expect(page.locator(sem(SemanticsIds.indexRail))).toHaveCount(0);
  await expect
    .poll(() => sorted.some((u) => !u.includes('sort=label')), {
      timeout: 15_000,
      message: 'the toggle should ask the server for the other order',
    })
    .toBeTruthy();
});

test('search answers a typed query and opens what it finds', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  await login(page);

  // The sidebar header is where the layout system puts search at this
  // width; it is a launcher, so the screen it opens owns the query.
  await clickThrough(
    page.locator(sem(SemanticsIds.searchLauncher)),
    page.locator(sem(SemanticsIds.searchField)),
  );
  await expect(page).toHaveURL(/#\/search$/);

  await typeInto(page, page.getByRole('textbox', { name: 'Search' }), 'Alpha');
  await page.locator(sem(SemanticsIds.searchHit('tracks', 0))).waitFor({ timeout: 30_000 });

  // A filter chip narrows to the groups it covers; audiobooks cover none
  // of a music-only fixture library, and the screen says so rather than
  // showing an empty page with hits behind it.
  await page.locator(sem(SemanticsIds.searchFilter('books'))).click();
  await expect(page.getByText(/Nothing for/)).toBeVisible({ timeout: 15_000 });
  await page.locator(sem(SemanticsIds.searchFilter('all'))).click();

  // A track hit is a thing to play, not a place to go.
  await clickThrough(
    page.locator(sem(SemanticsIds.searchHit('tracks', 0))),
    page.locator(sem(SemanticsIds.playerToggle)),
  );
});

test('playlists is reachable from the music section at sidebar width', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  await login(page);

  // The section is closed until it holds where you are, so this is the
  // journey the move cost: one disclosure, then the row.
  await openMusicSection(page);
  await clickThrough(
    page.locator(sem(SemanticsIds.navDestination('playlists'))),
    page.locator(sem(SemanticsIds.playlistAdd)),
  );
  await expect(page).toHaveURL(/#\/playlists$/);
});

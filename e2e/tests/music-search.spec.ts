import { test, expect } from './fixtures';

// The music domain over the real stack: the hub's ways in, an index in
// both of its orders with the alphabet rail beside the A-to-Z one, a
// bucket opening its own shareable location, and the search screen
// answering a query typed into the real field.

test('the music hub opens an index, and a bucket is its own location', async ({ app }) => {
  await app.nav.to('music');
  await app.nav.expectAt('music');

  await app.music.openIndex('artists');
  await app.nav.expectAt('artists');

  // Artists lead A to Z, which is the only order the rail is honest
  // over, so it is drawn beside them.
  await expect(app.music.rail()).toBeVisible();

  // Opening a bucket puts it in the address bar as an entity pid: the
  // whole point of a location is that a stranger can open it.
  await app.music.openBucket(0);
  expect(app.nav.location()).toMatch(/\/music\/artists\/ar-/);
  const shared = app.nav.location();

  // And a reload lands back on the same list, which is what a shared
  // link has to do: nothing here rides an in-memory payload.
  await app.nav.open(shared, app.music.entry(0));
  expect(app.nav.location()).toBe(shared);
});

test('the sort toggle swaps the index order and the rail with it', async ({ app, page }) => {
  await app.nav.enter('artists');
  await expect(app.music.rail()).toBeVisible();

  const sorted: string[] = [];
  page.on('request', (r) => {
    if (r.url().includes('/library/facets')) sorted.push(r.url());
  });

  // Biggest-first is a listing of its own with its own cursor space -
  // the server refuses one carried across the toggle - and the rail goes
  // with it, because in count order the letters are scattered down the
  // list.
  await app.music.sortByCount();
  await expect(app.music.rail()).toHaveCount(0);
  await expect
    .poll(() => sorted.some((u) => !u.includes('sort=label')), {
      message: 'the toggle should ask the server for the other order',
    })
    .toBeTruthy();
});

test('search answers a typed query and opens what it finds', async ({ app }) => {
  await app.nav.enter('home');

  // The sidebar header is where the layout system puts search at this
  // width, and it is a real field: clicking it opens the screen and
  // keeps the caret, where the launcher it replaces opened a screen and
  // abandoned the field the cursor was already in. One field throughout,
  // because the screen draws none of its own while this one is showing.
  await app.search.open();
  await app.nav.expectAt('search');
  await expect(app.search.field()).toHaveCount(1);

  await app.search.run('Alpha', 'tracks');

  // A filter chip narrows to the groups it covers; audiobooks cover none
  // of a music-only fixture library, and the screen says so rather than
  // showing an empty page with hits behind it.
  await app.search.narrowTo('books');
  await expect(app.search.emptyState()).toBeVisible();
  await app.search.narrowTo('all');

  // A track hit is a thing to play, not a place to go.
  await app.search.play('tracks', 0);
});

test('playlists is reachable from the music section at sidebar width', async ({ app }) => {
  await app.nav.enter('home');

  // The section is closed until it holds where you are, so this is the
  // journey the move cost: one disclosure, then the row - which is what
  // nav.to('playlists') is.
  await app.nav.to('playlists');
  await app.nav.expectAt('playlists');
});

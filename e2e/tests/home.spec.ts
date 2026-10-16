import { test, expect } from './fixtures';
import { SemanticsIds } from './semantics-ids';
import { emptyFirstPages } from './support/listings';

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

// A second fixture feed, whose episodes ("AAA Before Everything", "AAA
// First In Line") sort before every track in the library.
const EARLY_FEED = 'http://127.0.0.1:4421/early/feed.xml';

test('home draws its shelves while another account follows a show that sorts first', async ({
  app,
  otherAccount,
}) => {
  // Somebody else follows it. Listings used to cut their first page from
  // the whole catalog and only then drop what this account may not see,
  // so the episodes that sort first came back to it as an empty page with
  // a cursor, which home read as an empty library. Two halves keep that
  // from happening again, and each is pinned here.
  const follower = await otherAccount('early');
  const show = await app.seed.as(follower.token).subscribePodcast(EARLY_FEED);
  const hidden = new Set((await app.seed.as(follower.token).episodes(show)).map((e) => e.pid));

  // The server's: a listing is scoped to what this account may see before
  // its page is cut, so the episodes that sort first take no room on it.
  // A page of one, in title order, is one row this account can see.
  for (const first of [
    await app.api.get('/library/items', { query: { limit: 1 } }),
    await app.api.get('/library/browse', { query: { list: 'alphabetical', limit: 1 } }),
  ]) {
    expect(first.items, 'a page of one should hold a row this account can see').toHaveLength(1);
    expect(hidden.has(first.items[0].pid), 'not an episode of a show it does not follow').toBe(
      false,
    );
  }

  // The app's: a page may still come back short, even empty, with a
  // cursor - the contract's rule everywhere - and home reads on past it.
  // Its first reads, the library probe and the recent shelf, are answered
  // the way the old server answered this account.
  await emptyFirstPages(
    app.page,
    (url) =>
      !url.searchParams.has('mediaType') &&
      (url.pathname.endsWith('/library/items') ||
        (url.pathname.endsWith('/library/browse') &&
          url.searchParams.get('list') === 'recently-added')),
  );

  // This account follows nothing, and its home is the library's.
  await app.nav.enter('home');
  await expect(app.home.shelf('recent')).toBeVisible();
  await expect(app.home.text('Nothing here yet')).toHaveCount(0);
});

test('a shelf chevron pages the row instead of playing what is under it', async ({
  app,
  page,
}) => {
  // Narrow enough that the recent shelf must overflow.
  await page.setViewportSize({ width: 700, height: 900 });
  await app.nav.enter('home');

  const shelf = app.home.shelf('recent');
  await expect(shelf).toBeVisible();
  await shelf.hover();

  // Paging (back chevron arms, location unchanged) proves the click
  // landed on the chevron, not the card - and this is the only place
  // the chevrons' web DOM routing is exercised at all.
  const forward = app.home.shelfForward('recent');
  await expect(forward).toBeVisible();
  await forward.click();
  await expect(app.home.shelfBack('recent')).toBeVisible();
  await app.nav.expectAt('home');
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

  // The pid is what the shelf card is addressed by, and it is the last
  // segment of the album's own location - which is the round trip the
  // whole thing rests on: a pid stored, resolved, and drawn.
  const pid = decodeURIComponent(title.split('/').pop()!);

  await app.music.togglePin(pid);
  await app.nav.enter('home');
  await app.home.revealShelf('pinned');

  await expect(app.home.card('pinned', pid)).toBeVisible();

  // And unpinning from the album screen takes it away again, so the
  // shelf never accumulates what a listener meant to remove.
  await app.nav.open(title, app.music.entityShuffle());
  await app.music.togglePin(pid);
  await app.nav.enter('home');
  await expect(app.home.shelf('pinned')).toBeHidden();
});

test('continue listening holds a book part way through with no play counted', async ({
  app,
}) => {
  // Spoken word joins the shelf from its first saved position, where a
  // track waits for a counted play: a chapter is seldom finished in one
  // sitting, and a listen that stops short counts none. Seeded rather than
  // played, so no listen is reported at all.
  const book = await app.seed.book('The Chaptered Fixture');
  await app.seed.setPosition(book.pid, 2000);

  await app.nav.enter('home');
  await app.home.revealShelf('continue');
  await expect(app.home.card('continue', book.pid)).toBeVisible();
});

test("a shelf card's menu reaches the album and the editor door", async ({
  app,
}) => {
  // The continue shelf draws from this account's own play state, so its
  // contents are owned pids alone - deterministic under parallel
  // workers, where the library-wide shelves shuffle as other accounts
  // upload. A track joins it once a play of it has counted, which only a
  // real listen does (a direct played-flag edit deliberately never stamps
  // last_played_at), so a listen past the music threshold is reported and
  // the track then left mid-way: heard before, in progress now.
  const { pid } = await app.seed.item('Bravo Song');
  await app.api.post('/listens', {
    data: {
      sessions: [
        {
          sessionId: `e2e-home-menu-${Date.now().toString(36)}`,
          pid,
          startedAt: new Date().toISOString(),
          msPlayed: 2000,
          finished: false,
          source: 'live' as const,
        },
      ],
    },
  });
  await app.seed.setPosition(pid, 1000);

  await app.nav.enter('home');
  await app.home.revealShelf('continue');
  await expect(app.home.card('continue', pid)).toBeVisible();

  // A right click is the card's overflow gesture; the sheet's "Go to
  // album" lands on the release the card belongs to. The album screen
  // is pushed, and a push stays out of the reported URL by design, so
  // arrival is the screen's own track rows - not `entityPlay`, which
  // the artist and playlist screens draw too, so a pick landing one
  // row off on "Go to artist" would satisfy it; and not the identity
  // strip, which the screen omits for an album carrying no identity
  // fields, as the fixture album does.
  await app.home.chooseFromCardMenu(
    'continue',
    pid,
    app.home.control(SemanticsIds.itemMenuGoAlbum),
    app.home.control(SemanticsIds.albumTrackMore(0)),
  );
  await expect(app.home.control(SemanticsIds.albumTrackMore(0))).toBeVisible();

  // Back on home, the same menu again. This account holds neither the
  // admin role nor the upload right, so the editor door is not drawn at
  // all - the menu offers navigation and nothing it knows the server
  // would refuse. The door itself, and the editor behind it, belong to
  // the accounts that can use them.
  await app.nav.enter('home');
  await app.home.revealShelf('continue');
  await app.home.openCardMenu('continue', pid);
  await expect(app.home.control(SemanticsIds.itemMenuGoArtist)).toBeVisible();
  await expect(app.metadata.editEntry(pid)).toBeHidden();
});

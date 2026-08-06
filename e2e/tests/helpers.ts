// A shim, on its way out.
//
// Everything here has moved. The gesture primitives are
// `driver/gestures.ts`; the account identities and the bootstrap
// administrator are `accounts.ts`; the loopback sink is
// `support/json-sink.ts`; the library-scan poll is the `libraryReady`
// worker fixture; the login form is `app.auth.signInViaForm`; and
// reaching a screen is `app.nav`. What is left below is only what the
// unmigrated specs still import by name.
//
// This file is deleted when the last `legacyTest` import is. The
// `helpers-import` rule in lint/conformance.mjs counts the way down.

import { expect, APIRequestContext, Locator, Page } from '@playwright/test';
import { SemanticsIds, sem } from './semantics-ids';
import { ADMIN_PASS, ADMIN_USER } from './accounts';
import { clickThrough, typeInto } from './driver/gestures';

export { ACCOUNT_PASS, ADMIN_PASS, ADMIN_USER, ensureAdmin } from './accounts';
export { authed } from './driver/api';
export {
  chooseFromMenu,
  clickInView,
  clickThrough,
  typeInto,
} from './driver/gestures';
export { startJsonSink } from './support/json-sink';

// Kept here rather than moved: a spec that drives the login form as the
// shared administrator is a spec that has not been migrated, so this
// has no home in the driver. `app.auth.signInViaForm` is the migrated
// equivalent and takes the test's own account.
export async function loginAsAdmin(page: Page, settledOn: Locator) {
  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, ADMIN_USER);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), ADMIN_PASS);
  await page.getByRole('button', { name: 'Log in' }).click();
  await settledOn.waitFor({ timeout: 30_000 });
}

// The startup scan is asynchronous; poll until the fixture library shows
// up. Migrated specs take the `libraryReady` worker fixture, which does
// this once per worker instead of once per test.
export async function waitForLibrary(request: APIRequestContext, token: string) {
  await expect
    .poll(
      async () => {
        const resp = await request.get('/api/v1/library/items', {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!resp.ok()) return 0;
        return ((await resp.json()).items ?? []).length;
      },
      { timeout: 60_000, message: 'startup scan should populate the library' },
    )
    .toBeGreaterThanOrEqual(4);
}

// Playlists is one of the ways into music now, so the sidebar lists it
// under the Music hub in a section that stays closed until it holds
// where you are. Migrated specs say `app.nav.to('playlists')`, which
// owns this walk.
export async function openMusicSection(page: Page) {
  await clickThrough(
    page.locator(sem(SemanticsIds.navDisclose('music'))),
    page.locator(sem(SemanticsIds.navDestination('playlists'))),
  );
}

// The tracks index: every item in the library, each row addressed by its
// pid. Home is shelves now, and a shelf is a dozen cards drawn from a
// list rather than an enumeration, so a spec that wants one known track
// comes here - which is what the deleted library grid was doing for it.
//
// **Call this from the shell, not from over it.** It walks the chrome,
// so the nav has to be on screen: with the player, the queue, the
// visualizer or car mode pushed on top, the route is opaque and the
// chrome's handles are gone from the semantics tree. Migrated specs get
// that check from `app.nav.ensureChrome()`.
export async function itemRow(page: Page, pid: string): Promise<Locator> {
  const row = page.locator(sem(SemanticsIds.item(pid)));
  if (await row.count()) return row;
  // Walked through the chrome rather than reached by `goto`, which since
  // the path-URL flip is a real page load: every caller arrives here with
  // an app it has already set up - just signed in, sometimes already
  // playing - and a reload throws that instance away and boots a new one
  // over whatever was in flight. Under the old fragment strategy the same
  // call was a same-document hop and cost nothing, which is why it was
  // written this way. Two clicks, each retried as a unit, land on the
  // same index.
  await clickThrough(
    page.locator(sem(SemanticsIds.navDestination('music'))),
    page.locator(sem(SemanticsIds.musicTile('tracks'))),
  );
  await clickThrough(
    page.locator(sem(SemanticsIds.musicTile('tracks'))),
    row,
  );
  await row.waitFor({ timeout: 30_000 });
  return row;
}

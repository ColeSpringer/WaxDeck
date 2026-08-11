import { test, expect } from './fixtures';
import { T } from './driver/budgets';

// A real third-party client, driven for real: Feishin's own web build in
// a container beside the stack, signed in with an app password over the
// Subsonic surface, browsing to a fixture album and playing it.
//
// The trace suites in server/internal/api emulate what these clients
// ask for, and they are the cheap gate. This is the expensive one, and
// it is the only one that runs the client's own code: what it caught on
// its first run was a sign-in that no trace could see. Feishin's login
// is a `getUser` call, which WaxDeck answered "not implemented by this
// server", so the credentials form simply stayed on screen - while every
// endpoint the emulated trace asked for worked. It also caught
// `search3` ignoring `songOffset`, which the client uses to discover how
// many tracks a server holds by asking at rising offsets until the
// answer is empty; against a server that answers song one forever, that
// probe never ends.
//
// Feishin is configured through its image's own env (SERVER_URL,
// SERVER_TYPE, SERVER_LOCK), so there is no add-server form to drive and
// no place for this spec to drift from what an operator would set. The
// browser reaches WaxDeck cross-origin, which is what WAXDECK_CORS_ORIGINS
// exists for. The container is a test fixture, so it lives in its own
// compose project - `docker compose -f e2e/clients/compose.yaml up -d` -
// rather than in the production file.
const FEISHIN = process.env.FEISHIN_BASE_URL;

test.describe('a real Subsonic client', () => {
  test.skip(!FEISHIN, 'set FEISHIN_BASE_URL to drive the Feishin container');

  test('Feishin signs in with an app password and plays a track', async ({
    app,
    account,
    browser,
  }) => {
    // The compatibility surfaces never take the login password, so this
    // is the credential a real user would paste into the client. Minted
    // through the seed helper, which revokes any earlier password under
    // the label first: the account is stable across runs and the cap is
    // fifty, so a hand mint would walk a reused stack into a refusal
    // with nothing pointing at the cause.
    const minted = await app.seed.appPassword('feishin-e2e');

    // Its own context: a foreign origin with its own storage, and none
    // of this suite's session planted in it.
    const context = await browser.newContext();
    const page = await context.newPage();
    try {
      await page.goto(FEISHIN!);
      await page.getByLabel('Username').fill(account.username);
      await page.getByRole('textbox', { name: 'Password' }).fill(minted.secret);
      await page.getByRole('button', { name: 'Login' }).click();

      // Feishin opens its release notes over the app on a first load.
      // Dismissed rather than clicked around, and tolerated when absent
      // so a version that stops showing it does not fail the run.
      await page
        .getByRole('button', { name: 'Dismiss' })
        .click({ timeout: T.step })
        .catch(() => {});

      await page.goto(`${FEISHIN}/#/library/albums`);
      const album = page.getByText('Fixture Album', { exact: true }).first();
      await expect(album, 'the scanned fixture album reaches the client').toBeVisible({
        timeout: T.nav,
      });
      await album.click();

      // What is asserted is bytes, not a click: /rest/stream answers a
      // redirect to a tokenized media URL, so the response that proves
      // the whole chain - app password, session, media token, range
      // serving - is the media fetch the browser follows it to.
      const streamed = page.waitForResponse(
        (r) => /\/media\/stream/.test(r.url()) && [200, 206].includes(r.status()),
        { timeout: T.nav },
      );
      await page.getByRole('button', { name: /^Play$/ }).first().click();
      await streamed;

      // And the client believes it is playing that track.
      await expect(page.getByText('Alpha Song').first()).toBeVisible({ timeout: T.assert });
    } finally {
      await context.close();
    }
  });
});

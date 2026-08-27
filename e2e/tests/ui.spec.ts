import { test, expect } from './fixtures';
import { T } from './driver';

// The first-party web UI journey: log in through the real login form,
// walk the chrome to the tracks index, open the player, and observe the
// stream actually being fetched through the media proxy. The flutter app
// enables semantics at startup; widgets carry flt-semantics-identifier
// attributes for exactly this suite.
//
// One of the few specs that still drives the door. Everywhere else the
// session is planted as a cookie and the app opens signed in; here the
// login form IS the contract, which is also why `motion-smoke` re-runs
// this file with animations at full length.
test.use({ session: 'signed-out' });

test('login, browse the grid, and play a track', async ({ app, page }) => {
  const { pid } = await app.seed.item('Alpha Song');

  // Browser-side diagnostics: playback-start failures render a terse
  // error pane, so the console and failed requests are the evidence.
  page.on('console', (msg) => {
    if (msg.type() === 'error' || msg.type() === 'warning') {
      console.log(`[browser ${msg.type()}] ${msg.text()}`);
    }
  });
  page.on('pageerror', (err) => console.log(`[pageerror] ${err.message}`));
  page.on('requestfailed', (req) =>
    console.log(`[requestfailed] ${req.method()} ${req.url()} ${req.failure()?.errorText}`),
  );
  page.on('response', (resp) => {
    if (resp.status() >= 400) {
      console.log(`[http ${resp.status()}] ${resp.request().method()} ${resp.url()}`);
    }
  });

  // The login form is the first thing an unauthenticated visitor sees.
  // Click-and-type drives flutter's real text-editing path; a direct
  // value fill can leave the framework-side controller empty, and the
  // driver's typeInto retypes until every keystroke verifiably landed.
  await app.auth.signInViaForm();

  // The in-app reduce-motion override, which is additive to the
  // platform's answer and so could still motion off a run that asked for
  // it on. This spec is the one motion-smoke re-runs with motion
  // enabled, and a stale override would make that project quietly
  // identical to the rest of the suite. Per device today, so a fresh
  // context cannot carry one; asserted anyway, because the day the
  // setting moves into the account's preference document it would carry
  // between runs and nothing else would notice.
  expect(
    await page.evaluate(() => localStorage.getItem('waxdeck.a11y.reduceMotion')),
    'no in-app reduce-motion override is in force',
  ).not.toBe('true');

  // What this account has already been credited with. A delta rather
  // than an absolute: the account is keyed on the test's title, so a
  // reused stack hands this test the play it recorded last time and
  // `playCount >= 1` would be true before the browser opened.
  const before = (await app.api.get('/items/{pid}/play-state', { path: { pid } })).playCount ?? 0;

  // The tracks index enumerates the scanned fixture album. Walked
  // through the chrome rather than entered by location: this is the
  // walking skeleton, and getting there is part of what it covers.
  await app.nav.to('tracks');
  await app.music.play(pid);
  await app.player.ready();

  // Opening the item starts playback through the single-origin media
  // proxy. The rendered duration proves the stream's metadata decoded.
  await expect(app.player.text(/0:0[2-9]/)).toBeVisible({ timeout: T.nav });

  // The fixture is two seconds long; when it completes, the client
  // reports its listen session and checkpoints state. Observing the
  // server count another play closes the whole loop: UI login, index,
  // stream fetch, engine completion, listen ingest.
  await expect
    .poll(
      async () => {
        const state = await app.api.tryGet('/items/{pid}/play-state', { path: { pid } });
        return state?.played === true && (state.playCount ?? 0) > before;
      },
      { timeout: T.fetch, message: 'completed playback should be accounted as a play' },
    )
    .toBeTruthy();
});

// Pull-down and a 40 px chevron were the only ways down, which is a
// touch answer handed to a mouse. Both ways added here are pointer
// gestures with no semantics node of their own - deliberately, since a
// tappable node the size of the window would sit over every named
// control on the player - so the driver reaches them by key and by
// coordinate, and the identifier registry gains nothing.
test.describe('leaving the full-screen player', () => {
  test.use({ session: 'planted' });

  test('a pointer gets out without the pull-down', async ({ app }) => {
    const { pid } = await app.seed.item('Alpha Song');
    await app.nav.to('tracks');

    await app.music.play(pid);
    await app.player.ready();
    await app.player.dismissWithEscape(app.music.item(pid));

    // And back up, to click off the content this time. The track is
    // still playing behind the listing, so expanding the dock is the
    // whole journey - a second row tap would be skipped by the play
    // gesture anyway, its deck-bar goal already met.
    await app.player.ready();
    const dismissed = await app.player.dismissByBackdrop(app.music.item(pid));
    test.skip(!dismissed, 'the backdrop gutter needs a window wider than the content');
  });
});

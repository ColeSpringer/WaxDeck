import { test, expect, Page, APIRequestContext } from './fixtures';
import { authed, chooseFromMenu, clickThrough, ensureAdmin, itemRow, loginAsAdmin } from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The radio slice and the Connect surfaces over the real stack: a station
// added over the API is drawn from the server's own logo proxy, tuned in
// through the browser's real engine, and the cast surfaces (the picker,
// the connection check) render against this client's own endpoint.
//
// The logo host is the same loopback fixture host the podcast scenarios
// use; the stack enables private radio hosts for it, which is also what
// lets the stream proxy relay a loopback URL.
const LOGO_HOST = 'http://127.0.0.1:4421';

/// This spec's own stations, named so a parallel worker's rows cannot be
/// mistaken for them: the library is shared by every account and every
/// worker, and a grid picked over by name would otherwise catch another
/// spec's station.
const STATION = 'E2E Dial FM';
const LOGO_STATION = 'E2E Logo FM';

async function station(
  request: APIRequestContext,
  token: string,
  name: string,
  stream: string,
  logo?: string,
): Promise<{ pid: string }> {
  const existing = await (
    await request.get('/api/v1/radio/stations', authed(token))
  ).json();
  const already = (existing.stations as Array<{ pid: string; name: string }>).find(
    (s) => s.name === name,
  );
  if (already) return { pid: already.pid };
  const res = await request.post('/api/v1/radio/stations', {
    ...authed(token),
    data: {
      // A distinct stream URL per station, because the library refuses a
      // duplicate: two of this spec's stations pointed at one file would
      // conflict on the second create rather than on anything real.
      name,
      streamUrl: stream,
      ...(logo ? { logoUrl: logo } : {}),
    },
  });
  expect(res.status(), await res.text()).toBe(201);
  return { pid: (await res.json()).pid };
}

/// Clears the account's pinned stations.
///
/// Favourites are per account now, so they outlive a browser context and a
/// re-run against a reused stack would find yesterday's pin still there -
/// which is exactly what the dial test asserts the absence of. The rest of
/// the preference document is carried through by hand, because PUT replaces
/// the whole thing.
async function clearFavorites(request: APIRequestContext, token: string) {
  const current = await (
    await request.get('/api/v1/users/me/prefs', authed(token))
  ).json();
  const res = await request.put('/api/v1/users/me/prefs', {
    ...authed(token),
    data: { ...current, radioFavorites: [] },
  });
  expect(res.status(), await res.text()).toBe(200);
}

async function openRadio(page: Page) {
  await clickThrough(
    page.locator(sem(SemanticsIds.navDestination('radio'))),
    page.locator(sem(SemanticsIds.radioHub)),
  );
}

test.describe.serial('radio and cast', () => {
  test('a station logo is served from this origin, not from the station host', async ({
    request,
  }) => {
    const token = await ensureAdmin(request);
    const withLogo = await station(
      request,
      token,
      LOGO_STATION,
      `${LOGO_HOST}/wd-fixture-ep-002.mp3`,
      `${LOGO_HOST}/station-logo.png`,
    );

    // The reversal API item 12 records: a client never fetches a station
    // host directly, because on web that has no CORS headers to offer, an
    // http logo is mixed content on an https page, and the fetch hands the
    // listener's IP to a stranger.
    const logo = await request.get(
      `/api/v1/radio/stations/${withLogo.pid}/logo`,
      authed(token),
    );
    expect(logo.status()).toBe(200);
    // Sniffed from the bytes rather than passed through: hosts label
    // favicons every which way, and what a browser is handed has to match
    // what it is told.
    expect(logo.headers()['content-type']).toBe('image/png');
    expect((await logo.body()).length).toBeGreaterThan(0);
    const etag = logo.headers()['etag'];
    expect(etag).toBeTruthy();
    expect(logo.headers()['cache-control']).toContain('private');
    // No Vary: the station library is shared, so these bytes do not depend
    // on who asked.
    expect(logo.headers()['vary']).toBeUndefined();
    // The hardening pair. A logo URL is attacker-supplied - any account may
    // add a station pointing anywhere - and these bytes are served from
    // this origin, so a browser must not be free to re-decide the body, and
    // a document opened straight from this URL must not run anything. SVG
    // is refused outright upstream of this, which is what makes the raster
    // set safe rather than merely mitigated.
    expect(logo.headers()['x-content-type-options']).toBe('nosniff');
    expect(logo.headers()['content-security-policy']).toContain("default-src 'none'");

    // A matching validator answers 304, so a warm dial repaints for free.
    const revalidated = await request.get(
      `/api/v1/radio/stations/${withLogo.pid}/logo`,
      { ...authed(token), headers: { ...authed(token).headers, 'If-None-Match': etag } },
    );
    expect(revalidated.status()).toBe(304);

    // The size a client's artwork ladder appends is accepted and changes
    // nothing, so one URL builder serves covers and logos alike.
    const sized = await request.get(
      `/api/v1/radio/stations/${withLogo.pid}/logo?size=256`,
      authed(token),
    );
    expect(sized.status()).toBe(200);

    // A station with no logo is a 404 and a monogram, not a broken image.
    const bare = await station(
      request,
      token,
      STATION,
      `${LOGO_HOST}/wd-fixture-ep-003.mp3`,
    );
    const none = await request.get(
      `/api/v1/radio/stations/${bare.pid}/logo`,
      authed(token),
    );
    expect(none.status()).toBe(404);

    // The tokenless 401 is not asserted here: this request context carries
    // the session cookie the login set, and dropping the Authorization
    // header does not drop that. It is covered where a client can actually
    // have no credential at all - TestRadioStationLogoProxy.
  });

  test('the hub pins a station to the dial and tunes it in', async ({
    page,
    request,
  }) => {
    const token = await ensureAdmin(request);
    const bare = await station(
      request,
      token,
      STATION,
      `${LOGO_HOST}/wd-fixture-ep-003.mp3`,
    );
    await clearFavorites(request, token);

    await loginAsAdmin(page, page.locator(sem(SemanticsIds.navDestination('radio'))));
    await openRadio(page);

    const row = page.locator(sem(SemanticsIds.radio(bare.pid)));
    await row.waitFor({ timeout: 30_000 });

    // No dial until something is pinned: a band under a needle with
    // nothing on it is a stripe of chrome.
    await expect(page.locator(sem(SemanticsIds.radioDial))).toHaveCount(0);

    await clickThrough(
      page.locator(sem(SemanticsIds.radioFavorite(bare.pid))),
      page.locator(sem(SemanticsIds.radioDial)),
    );
    // The dial's own control names what it will do.
    await expect(page.locator(sem(SemanticsIds.radioTune))).toBeVisible();

    // Tuning in through the dial takes the engine: the deck bar picks the
    // station up, with a live pill and stop rather than pause.
    await page.locator(sem(SemanticsIds.radioTune)).click({ force: true });
    const bar = page.locator(sem(SemanticsIds.deckBar));
    await bar.waitFor({ timeout: 30_000 });
    // The station's name is in the bar's accessible name, not in its text:
    // the title block is excluded from semantics so the bar announces once
    // rather than re-reading its own elapsed time at every tick.
    await expect(bar).toHaveAttribute(
      'aria-label',
      new RegExp(`Live, ${STATION}`),
      { timeout: 30_000 },
    );
    // Stop rather than pause: a paused live stream resumes at the live edge
    // anyway, and the transport does not pretend otherwise. (Or "Tap to
    // resume" where the browser refused the programmatic start, which is
    // the same control saying the other true thing.)
    await expect(
      page.getByRole('button', { name: /^(Stop|Tap to resume)$/ }).first(),
    ).toBeVisible({ timeout: 30_000 });
    // A station has no per-user state, so the bar draws no star over one:
    // a permanently greyed control reads as broken rather than as absent.
    await expect(page.locator(sem(SemanticsIds.deckStar))).toHaveCount(0);

    // Stopping it puts the bar away, because radio never enters the queue
    // and there is nothing left for the bar to be about.
    await page.locator(sem(SemanticsIds.deckPlay)).click({ force: true });
    await expect(bar).toHaveCount(0, { timeout: 30_000 });

    // The pin reached the account rather than this browser: which of the
    // household's stations are yours is a fact about you, so it is in the
    // synced preference document and a phone gets it too.
    await expect
      .poll(
        async () => {
          const prefs = await (
            await request.get('/api/v1/users/me/prefs', authed(token))
          ).json();
          return (prefs.radioFavorites ?? []) as string[];
        },
        { timeout: 15_000, message: 'the pin should reach the prefs document' },
      )
      .toEqual([bare.pid]);

    // Unpinning takes the dial with it and clears the stored list: the
    // server drops the field rather than storing `[]`, and no client reads a
    // default set of pins out of an absent one, so both read as none pinned.
    // What has to survive is the *clear*, which is what this checks.
    await page.locator(sem(SemanticsIds.radioFavorite(bare.pid))).click({ force: true });
    await expect(page.locator(sem(SemanticsIds.radioDial))).toHaveCount(0);
    await expect
      .poll(async () => {
        const prefs = await (
          await request.get('/api/v1/users/me/prefs', authed(token))
        ).json();
        return (prefs.radioFavorites ?? []) as string[];
      }, { timeout: 15_000 })
      .toEqual([]);
  });

  test('search reaches the station directory under its own chip', async ({
    page,
    request,
  }) => {
    await ensureAdmin(request);
    await loginAsAdmin(page, page.locator(sem(SemanticsIds.navDestination('radio'))));
    await openRadio(page);

    // The hub carries the search control in its own bar, which is this
    // phase's share of the compact-search entry: the shell owns no top app
    // bar, so every rebuilt screen brings the control with it.
    await expect(page.locator(sem(SemanticsIds.searchAction))).toBeVisible();

    // The sidebar header is the launcher at this width; the screen it
    // opens owns the query.
    await clickThrough(
      page.locator(sem(SemanticsIds.searchLauncher)),
      page.locator(sem(SemanticsIds.searchField)),
    );

    // The chip is a different question of a different surface: with
    // nothing typed it says what it is for rather than showing the
    // library's own empty state.
    await page.locator(sem(SemanticsIds.searchFilter('radio'))).click();
    await expect(page.getByText('Search the station directory')).toBeVisible({
      timeout: 15_000,
    });

    // The directory itself is a public service over the internet, so this
    // stack does not query it: what is pinned here is the chip, the scope
    // it selects, and that the screen offers the add flow rather than a
    // library search with every group hidden. The add path from a
    // directory match is covered by radio_hub_test.dart against a fake.
  });

  test('the device picker lists this device and checks the cast bases', async ({
    page,
    request,
  }) => {
    const token = await ensureAdmin(request);
    const items = await (
      await request.get('/api/v1/library/items', authed(token))
    ).json();
    const target = (items.items as Array<{ pid: string; title: string }>).find(
      (it) => it.title === 'Alpha Song',
    )!;

    await loginAsAdmin(page, page.locator(sem(SemanticsIds.navDestination('music'))));
    // Something has to be playing for the bar's cast control to exist:
    // there is no device to send silence to. A grid tap plays and pushes
    // the player over the chrome, so the bar is behind it until that is
    // left - and the bar's own cast control is what this phase changed.
    const card = await itemRow(page, target.pid);
    await card.waitFor({ timeout: 30_000 });
    await card.click();
    await page.locator(sem(SemanticsIds.playerToggle)).waitFor({ timeout: 30_000 });
    // The player's own back control, by handle: the listing underneath
    // has a back button too, and picking one of two by document order is
    // how this scenario started popping the wrong screen. Forced, like
    // every canvas-rendered click in this suite: a semantics node laid
    // over the content pane reports itself as intercepting the pointer,
    // and playwright's actionability check believes it.
    await page
      .locator(sem(SemanticsIds.playerBack))
      .click({ force: true });
    await page.locator(sem(SemanticsIds.deckBar)).waitFor({ timeout: 30_000 });

    await clickThrough(
      page.locator(sem(SemanticsIds.deckCast)),
      page.locator(sem(SemanticsIds.picker)),
    );

    // Playback is here, and the picker says so rather than offering a trip
    // to where the visitor already is.
    await expect(page.locator(sem(SemanticsIds.pickerThisDevice))).toBeVisible();
    await expect(
      page.locator(sem(SemanticsIds.pickerThisDevice)),
    ).toContainText('Playing here');

    // The connection check, one level in: a cast that fails is silent, and
    // this is the surface that says why. It had no UI at all before this,
    // so reading it meant curling the API.
    // `chooseFromMenu`, not `clickThrough`: that helper re-clicks its
    // trigger while it waits, which is right for a navigation and wrong
    // for a menu - under a loaded stack the second click closed the menu
    // the first had opened, and a third dismissed the sheet under it. A
    // single un-retried click is not the answer either, and was failing
    // about half the time under a full parallel run.
    const preflight = page.locator(sem(SemanticsIds.preflight));
    await chooseFromMenu(
      page.locator(sem(SemanticsIds.pickerOverflow)),
      page.locator(sem(SemanticsIds.pickerCheck)),
      preflight,
    );

    // The server advertises the configured public base, so there is at
    // least one candidate and it is drawn with its verdict.
    await expect(page.locator(sem(SemanticsIds.preflightBase(0)))).toBeVisible();
    await expect(preflight).toContainText('localhost:4420');
  });
});

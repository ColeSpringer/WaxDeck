import { test, expect } from './fixtures';
import { App, T } from './driver';

// The radio slice and the Connect surfaces over the real stack: a station
// added over the API is drawn from the server's own logo proxy, tuned in
// through the browser's real engine, and the cast surfaces (the picker,
// the connection check) render against this client's own endpoint.
//
// The logo host is the same loopback fixture host the podcast scenarios
// use; the stack enables private radio hosts for it, which is also what
// lets the stream proxy relay a loopback URL.
const LOGO_HOST = 'http://127.0.0.1:4421';

/// The station library is server-global, so these names are claims on
/// shared rows and each test owns its own - the two that want a station
/// with no logo want it for different reasons, and one name between them
/// would be a race the moment the serial group went away. A distinct
/// stream URL per station for the same reason the library demands one:
/// it refuses a duplicate.
const LOGO_STATION = { name: 'E2E Logo FM', stream: `${LOGO_HOST}/wd-fixture-ep-002.mp3` };
const BARE_STATION = { name: 'E2E Bare FM', stream: `${LOGO_HOST}/wd-fixture-ep-003.mp3` };
const DIAL_STATION = { name: 'E2E Dial FM', stream: `${LOGO_HOST}/wd-fixture-ep-001.mp3` };
/// Two more pins, so the band has enough on it to be a dial. Never
/// tuned, so their streams only have to be distinct - the library
/// refuses a duplicate and nothing here plays them.
const BAND_STATIONS = [
  { name: 'E2E Band One FM', stream: `${LOGO_HOST}/wd-fixture-band-001.mp3` },
  { name: 'E2E Band Two FM', stream: `${LOGO_HOST}/wd-fixture-band-002.mp3` },
];
/// The station the edit scenario owns, and what it is edited to. Its own
/// name and stream for the reason the rest have theirs: the library is
/// server-global and refuses a duplicate URL.
const EDIT_STATION = { name: 'E2E Edit FM', stream: `${LOGO_HOST}/wd-fixture-edit-001.mp3` };
const EDITED_STATION = {
  name: 'E2E Edited FM',
  stream: `${LOGO_HOST}/wd-fixture-edit-002.mp3`,
};

/// The edit scenario's station, put back to the identity it seeds by.
///
/// Called before the act as well as after it, which is the convention
/// `clearRadioSaved` and `clearPlaylistsNamed` already follow and the
/// reason they give: a run that dies before its cleanup must cost the
/// next one nothing. Here it costs rather a lot. The station library is
/// server-global, `seed.radioStation` matches by name, and this test
/// renames a row - so a failed expect, a timeout, or a Ctrl+C between
/// the edit and the restore leaves `E2E Edit FM` gone and
/// `E2E Edited FM` holding the stream URL the edit moves to. The next
/// run then finds no station by the seed name, creates a second row on
/// the now-free URL, and collides on the edit - permanently, leaking a
/// row per attempt into a five-hundred-capped library shared by every
/// worker.
///
/// Matching on either name is what makes it self-healing: the row is
/// found whichever side of the rename it was left on.
async function resetEditStation(app: App): Promise<string> {
  const held = await app.api.get('/radio/stations');
  const existing = (held.stations ?? []).find(
    (s) => s.name === EDIT_STATION.name || s.name === EDITED_STATION.name,
  );
  if (existing === undefined) {
    return app.seed.radioStation(EDIT_STATION.name, EDIT_STATION.stream);
  }
  if (
    existing.name !== EDIT_STATION.name ||
    existing.streamUrl !== EDIT_STATION.stream
  ) {
    await app.api.put('/radio/stations/{pid}', {
      path: { pid: existing.pid },
      data: { name: EDIT_STATION.name, streamUrl: EDIT_STATION.stream },
    });
  }
  return existing.pid;
}

test('a station logo is served from this origin, not from the station host', async ({
  app,
}) => {
  const withLogo = await app.seed.radioStation(
    LOGO_STATION.name,
    LOGO_STATION.stream,
    `${LOGO_HOST}/station-logo.png`,
  );

  // The reversal API item 12 records: a client never fetches a station
  // host directly, because on web that has no CORS headers to offer, an
  // http logo is mixed content on an https page, and the fetch hands the
  // listener's IP to a stranger.
  const logo = await app.api.raw.get('/radio/stations/{pid}/logo', {
    path: { pid: withLogo },
  });
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
  const revalidated = await app.api.raw.get('/radio/stations/{pid}/logo', {
    path: { pid: withLogo },
    headers: { 'If-None-Match': etag },
  });
  expect(revalidated.status()).toBe(304);

  // The size a client's artwork ladder appends is accepted and changes
  // nothing, so one URL builder serves covers and logos alike.
  const sized = await app.api.raw.get('/radio/stations/{pid}/logo', {
    path: { pid: withLogo },
    query: { size: 256 },
  });
  expect(sized.status()).toBe(200);

  // A station with no logo is a 404 and a monogram, not a broken image.
  const bare = await app.seed.radioStation(BARE_STATION.name, BARE_STATION.stream);
  const none = await app.api.raw.get('/radio/stations/{pid}/logo', {
    path: { pid: bare },
  });
  expect(none.status()).toBe(404);

  // The tokenless 401 is not asserted here: it is covered where a client
  // can actually have no credential at all - TestRadioStationLogoProxy.
});

test('an edit typed into the dialog reaches the server', async ({ app }) => {
  // The reproduction attempt for the report that "Save changes" closed
  // the dialog and left the server holding the old values. It was seen
  // once under Playwright-driven text entry, which is the one thing a
  // widget test cannot be: the entry path that produced it runs through
  // a real browser, a real editing session, and the semantics tree.
  //
  // So this drives exactly that, and the assertion is the server's own
  // copy rather than anything on screen - the dialog closing is the
  // claim under suspicion, not the evidence.
  const station = await resetEditStation(app);

  await app.nav.enter('radio');
  await app.radio.station(station).waitFor({ timeout: T.nav });

  try {
    await app.radio.editStation(station, {
      name: EDITED_STATION.name,
      streamUrl: EDITED_STATION.stream,
    });

    const held = await app.api.get('/radio/stations');
    const saved = (held.stations ?? []).find((s) => s.pid === station);
    expect(saved?.name).toBe(EDITED_STATION.name);
    expect(saved?.streamUrl).toBe(EDITED_STATION.stream);
  } finally {
    // In a finally, so a failing expect above restores too - the assert
    // is the likeliest thing here to leave the row renamed.
    await resetEditStation(app);
  }
});

test('the hub pins a station and tunes it in', async ({ app }) => {
  const station = await app.seed.radioStation(DIAL_STATION.name, DIAL_STATION.stream);
  // Seeded before the hub is entered, all of them: a station added to
  // the library while the grid is already drawn has no tile there, and
  // so no star to click.
  const band: string[] = [];
  for (const s of BAND_STATIONS) {
    band.push(await app.seed.radioStation(s.name, s.stream));
  }
  await app.seed.clearRadioFavorites();

  await app.nav.enter('radio');
  for (const pid of [station, ...band]) {
    await app.radio.station(pid).waitFor({ timeout: T.nav });
  }

  // Nothing pinned, nothing drawn: a band under a needle with nothing on
  // it is a stripe of chrome.
  await expect(app.radio.dial()).toHaveCount(0);
  await expect(app.radio.pinnedRow(station)).toHaveCount(0);

  await app.radio.pin(station);
  // One pin is a row, not a dial: the ticks would sweep a width nothing
  // occupies and the needle would point through it.
  await expect(app.radio.pinnedRow(station)).toBeVisible();
  await expect(app.radio.dial()).toHaveCount(0);

  // Tuning in from the pinned row takes the engine: the deck bar picks
  // the station up, with a live pill and stop rather than pause.
  await app.radio.tuneIn(app.radio.pinnedRow(station));
  await expect(app.radio.deckBar()).toHaveAttribute(
    'aria-label',
    new RegExp(`Live, ${DIAL_STATION.name}`),
    { timeout: T.nav },
  );
  // Stop rather than pause: a paused live stream resumes at the live edge
  // anyway, and the transport does not pretend otherwise. (Or "Tap to
  // resume" where the browser refused the programmatic start, which is
  // the same control saying the other true thing.)
  await expect(app.radio.transport(/^(Stop|Tap to resume)$/)).toBeVisible({
    timeout: T.nav,
  });
  // A station has no per-user state, so the bar draws no star over one.
  await expect(app.radio.deckStar()).toHaveCount(0);

  // Stopping it puts the bar away, because radio never enters the queue
  // and there is nothing left for the bar to be about.
  await app.radio.stop();
  await expect(app.radio.deckBar()).toHaveCount(0, { timeout: T.nav });

  // The pin reached the account rather than this browser: which of the
  // household's stations are yours is a fact about you, so it is in the
  // synced preference document and a phone gets it too. Exactly this one
  // station - the document belongs to this test.
  await expect
    .poll(async () => (await app.api.tryGet('/users/me/prefs'))?.radioFavorites ?? [], {
      message: 'the pin should reach the prefs document',
    })
    .toEqual([station]);

  // Three pins is a dial, and the band arrives with the one control it
  // publishes. Owned by this test rather than a second one, because the
  // preference document is the account's and two tests pinning into it
  // in parallel would each clear the other's.
  //
  // Fired back to back with nothing between them, which is the whole
  // point: the star flips on optimistic client state, and a toggle
  // computed from a document that does not yet hold the one before it
  // used to lose every write but the first. Only the document is
  // asserted, and only once - a poll between the taps is the pacing
  // that hid the bug. Exactly these three, in pin order: a superset
  // would pass a duplicate or a leaked pid, which is the other half of
  // what a burst gets wrong.
  for (const pid of [band[0], band[1]]) {
    await app.radio.pin(pid);
  }
  await expect
    .poll(async () => (await app.api.tryGet('/users/me/prefs'))?.radioFavorites ?? [], {
      message: 'every pin in the run should reach the document',
    })
    .toEqual([station, band[0], band[1]]);
  await expect(app.radio.dial()).toBeVisible();
  await expect(app.radio.tune()).toBeVisible();
  // And the rows are gone: the band is the surface now, not a second
  // copy of one.
  await expect(app.radio.pinnedRow(station)).toHaveCount(0);

  // Unpinning takes both surfaces with it and clears the stored list:
  // the server drops the field rather than storing `[]`, and no client
  // reads a default set of pins out of an absent one, so both read as
  // none pinned. What has to survive is the *clear*, which is what this
  // checks - three unpins in a run, and then the document, for the same
  // reason the pins above are unpaced.
  for (const pid of [band[1], band[0], station]) {
    await app.radio.unpin(pid);
  }
  await expect(app.radio.dial()).toHaveCount(0);
  await expect(app.radio.pinnedRow(station)).toHaveCount(0);
  await expect
    .poll(async () => (await app.api.tryGet('/users/me/prefs'))?.radioFavorites ?? [])
    .toEqual([]);
});

test('search reaches the station directory under its own chip', async ({ app }) => {
  await app.nav.enter('radio');

  // The hub carries the search control in its own bar, which is its
  // share of the compact-search entry: the shell owns no top app bar, so
  // every rebuilt screen brings the control with it.
  await expect(app.radio.searchAction()).toBeVisible();

  // The sidebar header is a live field at this width. Clicking it opens
  // the screen and keeps the caret, so nothing has to be typed to get
  // here - which this case needs, because the chip below answers with
  // an empty query.
  await app.search.open();

  // The chip is a different question of a different surface: with
  // nothing typed it says what it is for rather than showing the
  // library's own empty state.
  await app.search.narrowTo('radio');
  await expect(app.radio.text('Search the station directory')).toBeVisible();

  // The directory itself is a public service over the internet, so this
  // stack does not query it: what is pinned here is the chip, the scope
  // it selects, and that the screen offers the add flow rather than a
  // library search with every group hidden. The add path from a
  // directory match is covered by radio_hub_test.dart against a fake.
});

test('the device picker lists this device and checks the cast bases', async ({ app }) => {
  const target = await app.seed.item('Alpha Song');

  await app.nav.enter('tracks');
  // Something has to be playing for the bar's cast control to exist:
  // there is no device to send silence to. A row tap plays and pushes
  // the player over the chrome, so the bar is behind it until that is
  // left.
  await app.music.play(target.pid);
  await app.player.collapse(app.radio.deckBar());
  await app.radio.deckBar().waitFor({ timeout: T.nav });

  await app.cast.openPicker();

  // Playback is here, and the picker says so rather than offering a trip
  // to where the visitor already is.
  await expect(app.cast.thisDevice()).toBeVisible();
  await expect(app.cast.thisDevice()).toContainText('Playing here');

  // The connection check, one level in: a cast that fails is silent, and
  // this is the surface that says why.
  await app.cast.runCheck();

  // The server advertises the configured public base, so there is at
  // least one candidate and it is drawn with its verdict.
  await expect(app.cast.base(0)).toBeVisible();
  await expect(app.cast.preflight()).toContainText('localhost:4420');
});

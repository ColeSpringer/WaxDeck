import { test, expect } from './fixtures';
import { T } from './driver';

// Songs kept off the air, over the real stack: the list a listener
// builds from the radio, the marker on the ones their library has since
// acquired, the search that finds the ones it has not, and the removal
// that crosses a row off.
//
// The heart itself is deliberately not driven here. Filling it needs a
// station that announces an ICY title, and the loopback fixture host
// speaks plain HTTP - so the tap is covered where it can be: the Go
// integration tests drive the real save path against a real
// announcement, and the widget tests drive the button. What this covers
// is everything downstream of the tap, which is where the surfaces are.
const LOGO_HOST = 'http://127.0.0.1:4421';

/// The station library is server-global, so this name is a claim on a
/// shared row and this spec owns it. Saved songs are per account and
/// need no such care.
const STATION = { name: 'E2E Saved FM', stream: `${LOGO_HOST}/wd-fixture-ep-004.mp3` };

/// A line the parse recognises and one it does not. Both save, which is
/// the point: an announcement in a shape nothing splits is still what
/// the listener heard.
const PARSED = 'Salt Harbour - The Bree Trio';
const RAW = 'E2E Saved FM overnight session';

test('the radio hub opens the songs kept off the air, and rows can be found and forgotten', async ({
  app,
}) => {
  const station = await app.seed.radioStation(STATION.name, STATION.stream);
  // Before as well as after: a run that died before its cleanup must
  // cost the next one nothing, and the empty state below is exactly the
  // assertion yesterday's rows would break.
  await app.seed.clearRadioSaved();

  await app.nav.enter('radio');
  await app.radio.savedDoor().waitFor({ timeout: T.nav });
  await app.radio.savedDoor().click();
  await app.radio.saved().waitFor({ timeout: T.nav });

  // Nothing kept yet says where rows come from rather than sitting
  // blank: the heart is on a surface this screen cannot show.
  await expect(app.radio.text(/Nothing saved yet/)).toBeVisible();

  const parsed = await app.seed.radioSavedSong(station, PARSED);
  const raw = await app.seed.radioSavedSong(station, RAW);

  await app.nav.reload('radioSaved');
  await expect(app.radio.savedEntry(parsed)).toBeVisible({ timeout: T.nav });
  await expect(app.radio.savedEntry(raw)).toBeVisible();
  // A parsed line leads with the song and names the artist under it; an
  // unparsed one leads with the announcement as the station sent it.
  await expect(app.radio.text('The Bree Trio')).toBeVisible();
  await expect(app.radio.text(RAW)).toBeVisible();
  // The station a row was heard on is snapshotted onto it.
  await expect(app.radio.text(new RegExp(STATION.name)).first()).toBeVisible();

  // Crossing one off leaves the list and the account both.
  await app.radio.forgetSaved(raw);
  await expect(app.radio.savedEntry(raw)).toHaveCount(0, { timeout: T.nav });
  await expect
    .poll(
      async () => ((await app.api.get('/radio/saved')).songs ?? []).map((s) => s.pid),
      { timeout: T.nav },
    )
    .toEqual([parsed]);

  // The row's own control is the way into the library, which is what
  // the list is for: nothing on it plays, and every row exists to be
  // hunted down.
  await app.radio.savedFind(parsed).click();
  // The filter chips rather than the field: at sidebar width the chrome
  // carries a search field on every screen, so waiting for one would
  // pass without having gone anywhere.
  await app.search.filter('all').waitFor({ timeout: T.nav });
  // `go`, not `push`: a search is a location a stranger can open, so it
  // reaches the address bar rather than stacking over the list.
  expect(app.nav.location()).toContain('/search?');

  await app.seed.clearRadioSaved();
});

test('a saved song is idempotent on its identity and personal to its account', async ({
  app,
  api,
  otherAccount,
}) => {
  const station = await app.seed.radioStation(STATION.name, STATION.stream);
  await app.seed.clearRadioSaved();

  const first = await app.seed.radioSavedSong(station, PARSED);
  // The same song announced with different case and noise around it is
  // one row, which is what makes a filled heart's tap remove rather than
  // duplicate.
  const again = await app.seed.radioSavedSong(
    station,
    'salt harbour - The Bree Trio (Official Audio)',
  );
  expect(again).toBe(first);
  const mine = (await app.api.get('/radio/saved')).songs ?? [];
  expect(mine.map((s) => s.pid)).toEqual([first]);
  // Album is deliberately absent from the schema: ICY metadata is one
  // line, so a row naming one would be guessing.
  expect(mine[0].artist).toBe('Salt Harbour');
  expect(mine[0].title).toBe('The Bree Trio');
  expect(mine[0].stationPid).toBe(station);

  // Personal, unlike the station library it was heard from.
  const stranger = await otherAccount('listener');
  const theirs = await api.as(stranger.token).get('/radio/saved');
  expect((theirs.songs ?? []).map((s) => s.pid)).not.toContain(first);

  await app.seed.clearRadioSaved();
});

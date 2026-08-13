import { test, expect } from './fixtures';
import { T } from './driver';
import { SemanticsIds } from './semantics-ids';

// The settings surface over the real stack: the searchable sections, a
// per-device preference that survives a reload without touching the
// account, and account preferences that reach the server's document.
//
// Every test owns its account, so the assertions can be exact:
// `PUT /users/me/prefs` replaces the whole document, and two browsers
// writing it at once is last-writer-wins over fields neither touched.

test('the sections are locations, and search finds a setting inside one', async ({ app }) => {
  await app.nav.enter('settings');

  // Every section is a link a stranger can open, which is what makes
  // "it is under Playback" shareable.
  await app.settings.openSection('playback', 'skip-back');
  expect(app.nav.location()).toMatch(/settings\/playback/);

  // The browser's own Back, not another `enter`: a router that pushed
  // where it should have gone leaves Back unloading the SPA.
  await app.nav.back('settings');

  // A word that appears in no setting's name still finds it: the
  // registry's keywords are what make another app's vocabulary land.
  await app.settings.findAndOpen('loudness', 'replay-gain', 'replay-gain');
  expect(app.nav.location()).toMatch(/settings\/playback/);
});

test('a per-device setting survives a reload without reaching the account', async ({ app }) => {
  await app.nav.enter('settings');
  await app.settings.openSection('playback', 'skip-back');

  await app.settings.choose('skip-back', app.settings.option('skip-back', 45));
  const chosen = app.settings.buttonNamed('Skip back by, 45 seconds');
  await expect(chosen).toBeVisible();

  // The point of the per-device store: this browser's own storage keeps
  // it and the account's document never hears. The nav tier, because a
  // reload is a full wasm boot rather than a value settling.
  await app.nav.reload();
  await expect(chosen).toBeVisible({ timeout: T.nav });

  const prefs = await app.api.get('/users/me/prefs');
  expect(Object.keys(prefs)).not.toContain('skipBackSeconds');
  expect(Object.keys(prefs)).not.toContain('skipForwardSeconds');
});

test('About reports both versions', async ({ app }) => {
  const health = await app.api.get('/health');
  await app.nav.enter('settings');

  // From Account, which is where a listener looks: Server's version row
  // is administrators-only.
  //
  // About sits under the device list, so a long list would push it past
  // the fold and it would publish no node to click. `mintAccount` revokes
  // an existing account's old sessions, keeping the list one row.
  await app.settings.openSection('account', 'about');
  await app.settings.openSetting('about', SemanticsIds.aboutLicenses);

  // The two numbers a bug report is asked for, from the server that
  // answered rather than from a constant.
  await expect(app.settings.text(health.version)).toBeVisible();
  await expect(app.settings.text(`v${health.apiVersion}`, { exact: true })).toBeVisible();
});

test('an account setting reaches the preference document', async ({ app }) => {
  await app.nav.enter('settings');
  await app.settings.openSection('playback', 'crossfade');

  await app.settings.choose('crossfade', app.settings.option('crossfade', 6));
  await expect
    .poll(async () => (await app.api.tryGet('/users/me/prefs'))?.crossfadeSeconds)
    .toBe(6);

  // The contract says "zero or absent is a gapless butt join", so
  // dropping the zero is a legal way to store off. What must not pass as
  // off is a document that never arrived, which a plain `?? 0` would:
  // `tryGet` answers undefined on any non-2xx, so the read and the field
  // are checked separately.
  await app.settings.choose('crossfade', app.settings.option('crossfade', 0));
  await expect
    .poll(async () => {
      const prefs = await app.api.tryGet('/users/me/prefs');
      return prefs === undefined ? 'the prefs document did not read' : prefs.crossfadeSeconds ?? 0;
    })
    .toBe(0);
});

test('the radio scrobbling switch stores the opt-out inverted', async ({ app }) => {
  // Seeded on, because nothing puts it back: the account outlives the
  // run, so a second run would meet the switch already off.
  await app.seed.prefs({ radioScrobbleOptOut: false });
  await app.nav.enter('settings');
  await app.settings.openSectionShowing(
    'integrations',
    SemanticsIds.radioScrobbleSwitch,
  );

  const radio = app.settings.switchNamed(/Scrobble radio/);
  await expect(radio).toBeChecked();
  await radio.click();
  await expect(radio).not.toBeChecked();

  await expect
    .poll(async () => (await app.api.tryGet('/users/me/prefs'))?.radioScrobbleOptOut)
    // The switch says "scrobble radio" and the document says "opt out",
    // so the two are inverses and this is where that stays honest.
    .toBe(true);

  // And back on: a switch that writes the opt-out and never clears it
  // satisfies everything above. The other direction, not cleanup.
  await radio.click();
  await expect(radio).toBeChecked();
  await expect
    .poll(async () => (await app.api.tryGet('/users/me/prefs'))?.radioScrobbleOptOut ?? false)
    .toBe(false);
});

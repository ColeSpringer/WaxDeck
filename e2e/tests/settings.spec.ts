import { test, expect } from './fixtures';
import { T } from './driver';
import { SemanticsIds } from './semantics-ids';

// The settings surface over the real stack: the searchable sections, a
// per-device preference that survives a reload without touching the
// account, and account preferences that reach the server's own document.
//
// Every test here owns its account, which is what lets the last two say
// what they mean. They used to be a serial group with a comment
// explaining that `PUT /users/me/prefs` replaces the whole document, so
// two browsers writing different keys at once was last-writer-wins over
// fields neither meant to touch - and that key disjointness was not the
// protection it read as, because the clobbering is per document. Nothing
// else writes this account's document now, so the group is gone, the
// assertions are exact, and nothing has to be put back at the end.

test('the sections are locations, and search finds a setting inside one', async ({ app }) => {
  await app.nav.enter('settings');

  // Every section is a link a stranger can open, which is what makes
  // "it is under Playback" shareable.
  await app.settings.openSection('playback', 'skip-back');
  expect(app.nav.location()).toMatch(/settings\/playback/);

  // Back lands on the settings home rather than leaving the app - which
  // is the assertion, and the reason this is the browser's own Back and
  // not another `enter`: a router that pushed where it should have gone
  // leaves Back unloading the SPA, and a re-entry could never see it.
  await app.nav.back('settings');

  // A word that appears in no setting's name still finds it: the
  // registry's keywords are what make another app's vocabulary land.
  await app.settings.findAndOpen('loudness', 'replay-gain', 'replay-gain');
  expect(app.nav.location()).toMatch(/settings\/playback/);
});

test('a per-device setting survives a reload without reaching the account', async ({ app }) => {
  await app.nav.enter('settings');
  await app.settings.openSection('playback', 'skip-back');

  await app.settings.choose('skip-back', app.settings.menuItem('45 seconds'));
  const chosen = app.settings.buttonNamed('Skip back by, 45 seconds');
  await expect(chosen).toBeVisible();

  // The whole point of the per-device store: it is on this browser's
  // own storage, so a reload keeps it and the account's document never
  // hears about it. The nav tier, because what follows the reload is a
  // full wasm boot rather than a value settling.
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
  // Account's About row sits under the device list, which is what used
  // to push it past the fold - the shared administrator collected a
  // session per worker per run, and a row that is not laid out publishes
  // no semantics node to click. What keeps it reachable is upstream, in
  // `mintAccount`: an account that already exists has its old sessions
  // revoked before this run's login, so the list is one row long however
  // many times the stack has been reused.
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

  await app.settings.choose('crossfade', app.settings.menuItem('6 seconds'));
  await expect
    .poll(async () => (await app.api.tryGet('/users/me/prefs'))?.crossfadeSeconds)
    .toBe(6);

  // Off has to survive the round trip too, and the contract says what
  // that means: "Zero or absent is a gapless butt join". So the server
  // dropping the zero is a legal way to store off, and asserting a
  // literal 0 on the field would be asserting something nobody promised.
  //
  // What must NOT pass as off is a document that never arrived - which a
  // plain `?? 0` would, since `tryGet` answers undefined on any non-2xx.
  // So the read and the field are separated: an unread document reports
  // itself and keeps polling, and only then is absent read as zero.
  await app.settings.choose('crossfade', app.settings.menuItem('Off'));
  await expect
    .poll(async () => {
      const prefs = await app.api.tryGet('/users/me/prefs');
      return prefs === undefined ? 'the prefs document did not read' : prefs.crossfadeSeconds ?? 0;
    })
    .toBe(0);
});

test('the radio scrobbling switch stores the opt-out inverted', async ({ app }) => {
  // Seeded on, because nothing puts it back at the end. The account is
  // this test's own and nobody else reads it, so restoring it for a
  // sibling is one of the things the account model removes - but the
  // account outlives the run, and a second run against the same stack
  // would meet the switch already off and fail on its first assertion.
  // The precondition is "scrobbling is on"; establishing it is seeding.
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

  // And back on, which is the half that makes it a round trip: a switch
  // that writes the opt-out and never clears it satisfies everything
  // above. Not cleanup - the account is this test's own and the seed at
  // the top is what guarantees the starting state - but the other
  // direction of the same claim.
  await radio.click();
  await expect(radio).toBeChecked();
  await expect
    .poll(async () => (await app.api.tryGet('/users/me/prefs'))?.radioScrobbleOptOut ?? false)
    .toBe(false);
});

import { test, expect, Page } from './fixtures';
import {
  authed,
  chooseFromMenu,
  clickThrough,
  ensureAdmin,
  loginAsAdmin,
  typeInto,
} from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The settings surface over the real stack: the searchable sections, a
// per-device preference that survives a reload without touching the
// account, and an account preference that reaches the server's own
// document.
//
// Everything here runs against the shared admin account (one server, one
// admin, four workers), so it deliberately touches only the preference
// keys no other spec reads: crossfade and radio scrobbling. The theme is
// not among them - identity.spec.ts drives it - and neither is anything
// server-global.
//
// That is not enough on its own, and the two tests that write those keys
// are serialized below. `PUT /users/me/prefs` replaces the whole
// document and the client builds its body from a snapshot it loaded
// earlier, so two browsers writing different keys at once is a
// last-writer-wins race that clears the other one's field - and the
// loser is whichever poll is still watching for it. Same hazard, and the
// same answer, as admin-ops.spec.ts's server-global switches.

async function openSettings(page: Page) {
  await loginAsAdmin(page, page.locator(sem(SemanticsIds.navDestination('music'))));
  await clickThrough(
    page.locator(sem(SemanticsIds.navDestination('settings'))),
    page.locator(sem(SemanticsIds.settingsSearch)),
  );
}

test('the sections are locations, and search finds a setting inside one', async ({
  page,
}) => {
  await openSettings(page);

  // Every section is a link a stranger can open, which is what makes
  // "it is under Playback" shareable.
  await clickThrough(
    page.locator(sem(SemanticsIds.settingsSection('playback'))),
    page.locator(sem(SemanticsIds.setting('skip-back'))),
  );
  await expect(page).toHaveURL(/settings\/playback/);

  // Back lands on the settings home rather than leaving the app.
  await page.goBack();
  await page.locator(sem(SemanticsIds.settingsSearch)).waitFor({ timeout: 15_000 });

  // A word that appears in no setting's name still finds it: the
  // registry's keywords are what make another app's vocabulary land.
  await typeInto(page, page.locator(sem(SemanticsIds.settingsSearch)), 'loudness');
  await clickThrough(
    page.locator(sem(SemanticsIds.settingsResult('replay-gain'))),
    page.locator(sem(SemanticsIds.setting('replay-gain'))),
  );
  await expect(page).toHaveURL(/settings\/playback/);
});

test('a per-device setting survives a reload without reaching the account', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);

  await openSettings(page);
  await clickThrough(
    page.locator(sem(SemanticsIds.settingsSection('playback'))),
    page.locator(sem(SemanticsIds.setting('skip-back'))),
  );

  const skipBack = page.locator(sem(SemanticsIds.setting('skip-back')));
  await chooseFromMenu(
    skipBack,
    page.getByRole('menuitem', { name: '45 seconds' }),
  );
  await expect(
    page.getByRole('button', { name: 'Skip back by, 45 seconds' }),
  ).toBeVisible({ timeout: 15_000 });

  // The whole point of the per-device store: it is on this browser's
  // own storage, so a reload keeps it and the account's document never
  // hears about it.
  await page.reload();
  await expect(
    page.getByRole('button', { name: 'Skip back by, 45 seconds' }),
  ).toBeVisible({ timeout: 30_000 });

  // Asserted key by key rather than as a snapshot of the whole
  // document: the suite shares one admin account across four workers, so
  // another spec's own preference write lands in between and a deep
  // equality here would fail on somebody else's setting.
  const prefs = await (await request.get('/api/v1/users/me/prefs', authed(token))).json();
  expect(Object.keys(prefs)).not.toContain('skipBackSeconds');
  expect(Object.keys(prefs)).not.toContain('skipForwardSeconds');
});

test('About reports both versions', async ({ page, request }) => {
  const health = await (await request.get('/api/v1/health')).json();
  await openSettings(page);
  // Opened from Server rather than from Account. Both offer the same
  // row; Account's sits under a device list that this shared account
  // fills with a session per worker per run, which puts it far enough
  // below the fold that its semantics node is never published.
  await clickThrough(
    page.locator(sem(SemanticsIds.settingsSection('server'))),
    page.locator(sem(SemanticsIds.setting('server-summary'))),
  );
  await clickThrough(
    page.locator(sem(SemanticsIds.setting('server-summary'))),
    page.locator(sem(SemanticsIds.aboutLicenses)),
  );
  // The two numbers a bug report is asked for, from the server that
  // answered rather than from a constant.
  await expect(page.getByText(health.version, { exact: false }).first()).toBeVisible();
  await expect(page.getByText(`v${health.apiVersion}`, { exact: true })).toBeVisible();
});

// Serialized: both of these write the shared account's preference
// document, and a full-replace PUT built from a stale snapshot drops
// whichever key the other one just set.
test.describe.serial('account preferences', () => {
  test('an account setting reaches the preference document', async ({ page, request }) => {
    const token = await ensureAdmin(request);
    await openSettings(page);
    await clickThrough(
      page.locator(sem(SemanticsIds.settingsSection('playback'))),
      page.locator(sem(SemanticsIds.setting('crossfade'))),
    );

    const crossfade = page.locator(sem(SemanticsIds.setting('crossfade')));
    await chooseFromMenu(
      crossfade,
      page.getByRole('menuitem', { name: '6 seconds' }),
    );

    await expect(async () => {
      const prefs = await (
        await request.get('/api/v1/users/me/prefs', authed(token))
      ).json();
      expect(prefs.crossfadeSeconds).toBe(6);
    }).toPass({ timeout: 20_000 });

    // Off has to survive the round trip too: zero is a value, not an
    // absent field the next write would keep.
    await chooseFromMenu(crossfade, page.getByRole('menuitem', { name: 'Off' }));
    await expect(async () => {
      const prefs = await (
        await request.get('/api/v1/users/me/prefs', authed(token))
      ).json();
      expect(prefs.crossfadeSeconds ?? 0).toBe(0);
    }).toPass({ timeout: 20_000 });
  });

  test('the radio scrobbling switch stores the opt-out inverted', async ({
    page,
    request,
  }) => {
    const token = await ensureAdmin(request);
    await openSettings(page);
    await clickThrough(
      page.locator(sem(SemanticsIds.settingsSection('integrations'))),
      page.locator(sem(SemanticsIds.radioScrobbleSwitch)),
    );

    // Not a forced click, unlike the rest of the suite. The scrobbling
    // rows above this one load their connection state asynchronously and
    // the section grows under it, so a click forced at coordinates read a
    // moment earlier lands on whatever moved into that spot - which is how
    // this first ran: it opened the ListenBrainz connect dialog.
    // Playwright's own stability wait is the fix, and it applies here
    // because a settings screen does settle, where an animating seek bar
    // never does.
    const radio = page.getByRole('switch', { name: /Scrobble radio/ });
    await expect(radio).toBeChecked({ timeout: 15_000 });
    await radio.click();
    await expect(radio).not.toBeChecked({ timeout: 15_000 });

    await expect(async () => {
      const prefs = await (
        await request.get('/api/v1/users/me/prefs', authed(token))
      ).json();
      // The switch says "scrobble radio" and the document says "opt out",
      // so the two are inverses and this is where that stays honest.
      expect(prefs.radioScrobbleOptOut).toBe(true);
    }).toPass({ timeout: 20_000 });

    // Put it back: the shared account is what every other spec runs on.
    await radio.click();
    await expect(radio).toBeChecked({ timeout: 15_000 });
    await expect(async () => {
      const prefs = await (
        await request.get('/api/v1/users/me/prefs', authed(token))
      ).json();
      expect(prefs.radioScrobbleOptOut ?? false).toBe(false);
    }).toPass({ timeout: 20_000 });
  });
});

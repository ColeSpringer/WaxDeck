import type { Request } from '@playwright/test';
import { test, expect } from './fixtures';
import { T } from './driver';
import { clickThrough, clickToward, clickUntilRequested, typeInto } from './driver/gestures';
import { SemanticsIds } from './semantics-ids';

// The console's oversight surfaces over the real stack. Each write is a
// test's own (a share it revokes, a profile it deletes), so the file stays
// parallel; listings are everyone's, so assertions scope to their own pids.

test('a share link is listed with its owner and revoked from the console', async ({
  app,
}) => {
  // A fixture track, not a minted one: seed.item finds by exact title
  // in the shared library, and the share below is this test's own.
  const { pid } = await app.seed.item('Alpha Song');
  const share = await app.api.post('/shares', {
    data: { pid, allowDownload: false },
  });
  expect(share.pid).toMatch(/^sh-/);
  // The mint answers the caller's own row, which names nobody: the
  // owner rides the administrative listing alone.
  expect(share.owner).toBeUndefined();

  await app.nav.enter('adminShares');

  const row = app.sharing.row(share.pid);
  await expect(row).toBeVisible();
  // Who minted it, on the row, which is what makes the listing an
  // oversight surface rather than a longer copy of the personal one.
  await expect(row).toContainText(app.account.username);

  await app.sharing.revoke(share.pid).click();
  await expect(row).toBeHidden();

  // Revoked here means revoked everywhere: the capability URL stops
  // resolving for the anonymous holder, which is the point of the
  // affordance.
  const gone = await app.api.raw.get('/shares', { query: { all: true } });
  expect(gone.ok()).toBeTruthy();
  const listed = (await gone.json()).shares as Array<{ pid: string }>;
  expect(listed.some((s) => s.pid === share.pid)).toBe(false);
});

test('the transcoding limits say what the engine is running', async ({ app }) => {
  await app.nav.enter('adminSettings');

  // The count itself belongs to the whole stack - other workers stream
  // through it - so what is asserted is that the limits are read beside
  // a real number rather than set blind, and that the caveat travels
  // with it.
  const line = app.admin.control(SemanticsIds.transcodingActivity);
  await expect(line).toBeVisible();
  await expect(line).toContainText(/\d+ engine-backed sessions? right now\./);
  // A gapless queue rides the same limiter, and the row says how much
  // of its count is that rather than leaving it out of the number.
  await expect(line).toContainText(/(None|One|\d+) of them (is|are) (a )?gapless queue/);
  await expect(line).toContainText('holds one slot');

  // Refreshing is the freshness story: no timer, one affordance.
  await app.admin.control(SemanticsIds.transcodingActivityRefresh).click();
  await expect(line).toContainText(/\d+ engine-backed sessions? right now\./);
});

test('a role granted mid-session reaches the app that is already open', async ({
  app,
  device,
  otherAccount,
}) => {
  const promoted = await otherAccount('promoted');
  // Levelled first, because a previous run against this stack left the
  // account holding the role this test is about to grant it.
  const session = await app.api.as(promoted.token).get('/auth/session');
  const id = session.user!.id;
  await app.api.patch('/users/{userId}', {
    path: { userId: id },
    data: { roles: ['user'] },
  });

  const theirs = await device({ as: promoted });
  // The client mints its server cursor on the way up and reports
  // nothing from before it, so a promotion that lands during the mint
  // is swallowed by it. Armed ahead of the navigation that causes it.
  const minted = theirs.page.waitForResponse(
    (r) => r.url().includes('/sync/server') && !r.url().includes('since='),
    { timeout: T.nav },
  );
  await theirs.nav.enter('settings');
  // Absent for a plain account, not merely empty.
  await expect(theirs.settings.section('server')).toHaveCount(0);
  await minted;

  await app.api.patch('/users/{userId}', {
    path: { userId: id },
    data: { roles: ['user', 'admin'] },
  });

  // No reload anywhere: the server marks the account changed, the app
  // re-reads its session, and the gates that watch it follow.
  await expect(theirs.settings.section('server')).toBeVisible({ timeout: T.fetch });
});

// An organize profile made in the console lists with its sample, lays out
// a preview, and goes again. The name is this test's, so a profile a
// failed run left behind is cleared first rather than assumed absent.
test('an organize profile is made, previewed under and deleted', async ({ app }) => {
  const name = 'e2e-flat';
  await app.api.raw.delete('/organize/profiles/{name}', { path: { name } });
  const page = app.page;
  const control = (id: string) => app.admin.control(id);
  await app.nav.enter('adminOrganize');
  await clickThrough(control(SemanticsIds.organizeProfileNew), control(SemanticsIds.organizeProfileName));
  await typeInto(page, control(SemanticsIds.organizeProfileName), name);
  await typeInto(page, control(SemanticsIds.organizeProfileMusic), '{title}.{ext}');
  await expect(app.admin.text('Track: Amber Waves.flac')).toBeVisible({ timeout: T.fetch });
  await expect(async () => {
    await clickToward(control(SemanticsIds.organizeProfileSave), {
      gone: control(SemanticsIds.organizeProfileSheet),
    });
  }).toPass({ timeout: T.nav });

  const option = control(SemanticsIds.organizeProfileOption(name));
  await clickThrough(option, control(SemanticsIds.organizeProfileEdit(name)));
  const previewed = page.waitForResponse((r) => r.url().includes('/organize/preview'), {
    timeout: T.fetch,
  });
  await clickUntilRequested(page, control(SemanticsIds.organizePreview), (r) =>
    r.url().includes('/organize/preview'),
  );
  const response = await previewed;
  expect(response.status()).toBe(200);
  expect(response.request().postDataJSON().profile).toBe(name);

  await clickThrough(
    control(SemanticsIds.organizeProfileEdit(name)),
    control(SemanticsIds.organizeProfileDelete(name)),
  );
  await clickThrough(
    control(SemanticsIds.organizeProfileDelete(name)),
    control(SemanticsIds.organizeProfileDeleteConfirm),
  );
  // Not a wait for the option to go: the sheet already hides it.
  const isDelete = (r: Request) =>
    r.method() === 'DELETE' && r.url().endsWith(`/organize/profiles/${name}`);
  const deleted = page.waitForResponse((r) => isDelete(r.request()), { timeout: T.fetch });
  await clickUntilRequested(page, control(SemanticsIds.organizeProfileDeleteConfirm), isDelete);
  expect((await deleted).status()).toBe(204);
  await expect(option).toBeHidden({ timeout: T.fetch });
  const listed = await app.api.get('/organize/profiles');
  expect(listed.profiles.map((p) => p.name)).not.toContain(name);
});

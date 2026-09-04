import { test, expect } from './fixtures';
import { SemanticsIds } from './semantics-ids';

// The console's oversight surfaces, over the real stack: the share
// links every account has minted, and the transcoding limits read
// beside what the engine is actually running.
//
// Read-mostly on purpose. The only write is a share this test minted
// itself and then revokes, so nothing here is a server-global switch
// and the file stays in the parallel project. The listing is everyone's
// by construction, so every assertion is scoped to this account's own
// pid: a sibling worker's link is legitimately on the same page.

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

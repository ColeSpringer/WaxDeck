import { legacyTest as test, expect } from './fixtures';
import { ADMIN_PASS, ADMIN_USER, typeInto } from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// First-run setup through the real UI: a fresh server has no accounts,
// the app routes to the setup screen, and creating the administrator
// lands signed in. This spec runs as the `setup` project before every
// other spec (they all assume the administrator exists).


test('first run creates the administrator through the setup screen', async ({ page, request }) => {
  const status = await (await request.get('/api/v1/auth/bootstrap')).json();
  test.skip(!status.required, 'stack already bootstrapped (reused dev server)');

  await page.goto('/');

  // The setup screen, not the login screen, greets a fresh server.
  const username = page.locator(sem(SemanticsIds.setupUsername));
  await username.waitFor({ timeout: 30_000 });

  await typeInto(page, username, ADMIN_USER);
  await typeInto(page, page.locator(sem(SemanticsIds.setupPassword)), ADMIN_PASS);
  await typeInto(page, page.locator(sem(SemanticsIds.setupConfirm)), ADMIN_PASS);
  await page.locator(sem(SemanticsIds.setupSubmit)).click();

  // Setup logs straight in: the library shell appears without a
  // separate login step.
  await page.locator(sem(SemanticsIds.navDestination('settings'))).waitFor({ timeout: 30_000 });

  // The door is closed for good.
  await expect
    .poll(async () => (await (await request.get('/api/v1/auth/bootstrap')).json()).required)
    .toBe(false);

  // And the created session is an administrator.
  const session = await (await page.request.get('/api/v1/auth/session')).json();
  expect(session.authenticated).toBe(true);
  expect(session.user.roles).toContain('admin');
});

import { test, expect } from './fixtures';
import { ensureAdmin, authed, typeInto, clickThrough } from './helpers';
import { SemanticsIds, sem } from './semantics-ids';


// The self-serve door as a person meets it: the login screen's invite
// path, end to end, without touching the global open-signup toggle
// (admin-ops.spec owns that; specs run fully parallel).
test('an invite token walks a visitor in from the login screen', async ({ page, request }) => {
  test.setTimeout(180_000);
  const token = await ensureAdmin(request);
  const invite = await request.post('/api/v1/invites', {
    ...authed(token),
    data: { note: 'ui walk-up', maxUses: 1 },
  });
  expect(invite.status()).toBe(201);
  const inviteBody = await invite.json();

  const username = `walkup-${Date.now().toString(36)}`;
  // A fresh context carries no session, so the app lands on login;
  // with open signup off the affordance reads as the invite path.
  await page.goto('/');
  await clickThrough(page.locator(sem(SemanticsIds.signupOpen)), page.locator(sem(SemanticsIds.signupUsername)));
  await typeInto(page, page.locator(sem(SemanticsIds.signupUsername)), username);
  await typeInto(page, page.locator(sem(SemanticsIds.signupPassword)), 'walkup-pass-123');
  await typeInto(page, page.locator(sem(SemanticsIds.signupInviteToken)), inviteBody.token);
  // An invited signup activates immediately, so the screen pops back
  // to the login form prefilled (signup-result renders only for the
  // pending path).
  await clickThrough(page.locator(sem(SemanticsIds.signupSubmit)), page.locator(sem(SemanticsIds.loginUsername)));

  // The invite admitted an active account: it can log in immediately.
  const login = await request.post('/api/v1/auth/login', {
    data: { username, password: 'walkup-pass-123' },
  });
  expect(login.ok()).toBeTruthy();

  const listed = await request.get('/api/v1/invites', authed(token));
  const spent = (await listed.json()).invites.find(
    (iv: { id: string }) => iv.id === inviteBody.id,
  );
  expect(spent.usedCount).toBe(1);
});

import { test, expect } from './fixtures';
import { ADMIN_PASS, ADMIN_USER } from './accounts';

// First-run setup through the real UI: a fresh server has no accounts,
// the app routes to the setup screen, and creating the administrator
// lands signed in. This spec runs as the `setup` project before every
// other spec (they all assume the administrator exists).

// The one spec that mints nothing and opens no door. Every other test
// gets an account of its own, minted by the administrator this one
// creates - so a fixture that reached for that authority here would
// walk through the one-shot door before the assertion below could look
// at it, and this spec would skip on the only stack it can say anything
// about.
test.use({ session: 'virgin' });

test('first run creates the administrator through the setup screen', async ({ app }) => {
  const status = await app.api.get('/auth/bootstrap');
  test.skip(!status.required, 'stack already bootstrapped (reused dev server)');

  // The setup screen, not the login screen, greets a fresh server; and
  // it logs straight in, so the chrome appears with no separate login
  // step.
  await app.auth.completeSetup({ username: ADMIN_USER, password: ADMIN_PASS });

  // The door is closed for good.
  await expect
    .poll(async () => (await app.api.tryGet('/auth/bootstrap'))?.required)
    .toBe(false);

  // And the session the browser is holding is an administrator's.
  const session = await app.auth.session();
  expect(session.authenticated).toBe(true);
  expect(session.user?.roles).toContain('admin');
});

import { test, expect } from './fixtures';
import { ADMIN_PASS, ADMIN_USER } from './accounts';

// First-run setup through the real UI: a fresh server has no accounts,
// the app routes to the setup screen, and creating the administrator
// lands signed in. This spec runs as the `setup` project before every
// other spec (they all assume the administrator exists), and stops the
// stack's schedules for them, on a fresh stack and a reused one alike.

// The one spec that mints nothing. Every other test gets an account of
// its own, minted by the administrator the first test here creates - so
// a fixture that reached for that authority before it ran would walk
// through the one-shot door before its assertion could look at it, and
// it would skip on the only stack it can say anything about. The second
// test takes the authority only once the door has closed.
test.use({ session: 'virgin' });

// In order: the second test waits for the administrator the first makes,
// and a reused stack, where the first skips, still needs its schedules off.
test.describe.configure({ mode: 'serial' });

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

// A nightly job firing mid-run changes the catalog the specs read, so the
// stack runs none of the schedules that ship enabled.
test('the stack runs none of its schedules during the run', async ({ api, adminToken }) => {
  const admin = api.as(await adminToken());
  for (const schedule of (await admin.get('/admin/schedules')).schedules) {
    if (!schedule.enabled) continue;
    await admin.put('/admin/schedules/{kind}', {
      path: { kind: schedule.kind },
      data: { cron: schedule.cron, enabled: false },
    });
  }
  const left = (await admin.get('/admin/schedules')).schedules.filter((s) => s.enabled);
  expect(left, 'no schedule should fire during the run').toEqual([]);
});

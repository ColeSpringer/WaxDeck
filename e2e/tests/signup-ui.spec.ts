import { test, expect } from './fixtures';
import { J } from './driver';

// The self-serve door as a person meets it: the login screen's invite
// path, end to end, without touching the global open-signup toggle
// (admin-ops.spec owns that switch; it is server-global and the project
// graph is what keeps the two apart).
//
// Signed out, because the door is the subject. The account this test
// mints is the administrator that writes the invite; the account it
// creates is the walk-up visitor, made through the form.
test.use({ session: 'signed-out' });

test('an invite token walks a visitor in from the login screen', async ({ app }) => {
  test.setTimeout(J.long);
  const invite = await app.api.post('/invites', {
    data: { note: 'ui walk-up', maxUses: 1 },
  });
  expect(invite.token).toBeTruthy();

  // Fresh every run: a signup is the thing under test, so the visitor
  // has to be somebody the server has never seen. The name is not
  // cleaned up - a walk-up account is what the invite produced, and
  // deleting it would delete the evidence.
  const username = `walkup-${Date.now().toString(36)}`;
  const password = 'walkup-pass-123';

  // A fresh context carries no session, so the app lands on login;
  // with open signup off the affordance reads as the invite path.
  await app.auth.enterLogin();
  await app.auth.signUpViaForm({ username, password, invite: invite.token });

  // The invite admitted an active account: it can log in immediately.
  // As nobody, which is what a walk-up visitor is - an empty token sends
  // no Authorization header, so the credentials are what answer.
  const login = await app.api.as('').raw.post('/auth/login', {
    data: { username, password },
  });
  expect(login.ok()).toBeTruthy();

  const listed = await app.api.get('/invites');
  const spent = (listed.invites ?? []).find((iv) => iv.id === invite.id);
  expect(spent?.usedCount).toBe(1);
});

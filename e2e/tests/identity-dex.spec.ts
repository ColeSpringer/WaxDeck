import { test, expect } from './fixtures';

// The same single sign-on journey identity.spec.ts runs, against a real
// identity provider instead of the harness one.
//
// What the test IdP cannot prove: that WaxDeck's discovery, client
// authentication, token exchange and claim reading agree with a server
// somebody actually deploys. The bare binary answers exactly what this
// app asks for, which is the definition of a harness that cannot
// disagree with its subject. Dex can, and does - it authenticates the
// client with a secret, sets `preferred_username` from its own record,
// and would show a consent screen if its config did not say otherwise.
//
// Runs only under run-sso-dex.sh, which brings the container up and
// points the stack at it; the project itself does not exist otherwise.
test.describe('through a real identity provider', () => {
  test.skip(!process.env.WAXDECK_DEX_SSO, 'run through e2e/run-sso-dex.sh');

  // The one scenario that must meet the door: what it is about is the
  // provider putting a session there, so a planted one would answer a
  // different question entirely.
  test.use({ session: 'signed-out' });

  test('single sign-on logs in through dex', async ({ app }) => {
    await app.auth.enterLogin();
    await app.sso.signIn(
      'dex',
      { username: 'gandalf@waxdeck.e2e', password: 'mithrandir-e2e' },
      /127\.0\.0\.1:5556\/dex\/auth/,
      'dex',
    );

    // Signed in as the provisioned account rather than as this test's
    // own - which is why this reads the browser's session rather than
    // the spec's API hand.
    const browser = app.auth.browserApi();
    const session = await browser.get('/auth/session');
    expect(session.authenticated).toBe(true);
    expect(session.user?.username).toBe('gandalf');
    // No admin group is configured for the harness provider either, so
    // the account is a plain user and the admin surface refuses it.
    expect(session.user?.roles).not.toContain('admin');
    expect((await browser.raw.get('/users')).status()).toBe(403);
  });
});

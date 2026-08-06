import { test, expect } from './fixtures';

// Multi-user acceptance over the real stack: isolated per-user state,
// device revocation, and browser-driven single sign-on against the
// harness identity provider.

test("two listeners share the catalog but never each other's state", async ({
  app,
  otherAccount,
}) => {
  // Two accounts of this test's own. The second used to be a fixed
  // `merry` that every run and every worker shared, which is the same
  // aliasing the first half of this file is about.
  const merry = await otherAccount('merry');
  const mine = app.api;
  const theirs = app.api.as(merry.token);

  // Both see the same shared catalog. Podcast episodes are the one
  // deliberate exception (they scope to each user's own subscriptions),
  // so the shared half is everything else.
  const shared = (items: { pid: string; mediaType?: string }[]) =>
    items.filter((it) => it.mediaType !== 'podcast');
  const items = shared((await mine.get('/library/items')).items ?? []);
  const theirItems = shared((await theirs.get('/library/items')).items ?? []);
  expect(theirItems.length).toBe(items.length);
  const [first, second] = [items[0].pid, items[1].pid];

  // One stars and rates an item; the other's view stays untouched.
  await mine.put('/items/{pid}/star', { path: { pid: first }, data: { starred: true } });
  const rated = await mine.put('/items/{pid}/rating', {
    path: { pid: first },
    data: { rating: 80 },
  });
  expect(rated.rating).toBe(80);

  const theirState = await theirs.get('/items/{pid}/play-state', { path: { pid: first } });
  expect(theirState.starred).toBe(false);
  expect(theirState.rating ?? null).toBeNull();

  // The other stars a different item; the starred lists diverge - and
  // exactly, because both accounts belong to this test and neither has
  // starred anything else.
  await theirs.put('/items/{pid}/star', { path: { pid: second }, data: { starred: true } });
  const starredOf = async (who: typeof mine) =>
    ((await who.get('/library/browse', { query: { list: 'starred' } })).items ?? []).map(
      (it) => it.pid,
    );
  expect(await starredOf(mine)).toEqual([first]);
  expect(await starredOf(theirs)).toEqual([second]);

  // Neither is an administrator: the user admin surface refuses.
  expect((await theirs.raw.get('/users')).status()).toBe(403);
});

test('revoking a session kills the device immediately', async ({ app }) => {
  // A named device logs in as this test's own account.
  const phone = await app.api.as('').post('/auth/login', {
    data: {
      username: app.account.username,
      password: app.account.password,
      deviceName: 'Playwright Phone',
    },
  });
  const asPhone = app.api.as(phone.token);

  // It works, and it shows up in the device list. Exactly one row: the
  // account is this test's, so what is listed is the session the
  // fixture minted plus this one.
  expect((await asPhone.get('/auth/session')).authenticated).toBe(true);
  const sessions = (await app.api.get('/auth/sessions')).sessions ?? [];
  const entry = sessions.find((s) => s.deviceName === 'Playwright Phone');
  expect(entry, 'the named device should be listed').toBeTruthy();
  expect(entry!.kind).toBe('device');

  // Revoke it from the other session; the device's next request fails.
  const revoke = await app.api.raw.delete('/auth/sessions/{sessionId}', {
    path: { sessionId: entry!.id },
  });
  expect(revoke.status()).toBe(204);
  expect((await asPhone.raw.get('/library/items')).status()).toBe(401);
});

test.describe('through the identity provider', () => {
  // The one scenario that must meet the door: what it is about is the
  // provider putting a session there, so a planted one would answer a
  // different question entirely.
  test.use({ session: 'signed-out' });

  test('single sign-on logs in through the identity provider', async ({ app }) => {
    await app.auth.enterLogin();
    await app.sso.signIn(
      'testidp',
      { username: 'gandalf', password: 'mithrandir-e2e' },
      /127\.0\.0\.1:4419\/authorize/,
    );

    // Signed in as the provisioned account rather than as this test's
    // own - which is why this reads the browser's session rather than
    // the spec's API hand.
    const browser = app.auth.browserApi();
    const session = await browser.get('/auth/session');
    expect(session.authenticated).toBe(true);
    expect(session.user?.username).toBe('gandalf');
    // No admin group is configured for the harness IdP, so the account is
    // a plain user and the admin surface refuses it.
    expect(session.user?.roles).not.toContain('admin');
    expect((await browser.raw.get('/users')).status()).toBe(403);
  });
});

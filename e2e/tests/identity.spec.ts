import { test, expect } from '@playwright/test';
import { ADMIN_PASS, authed, ensureAdmin, waitForLibrary } from './helpers';

// Multi-user acceptance over the real stack: isolated per-user state,
// device revocation, and browser-driven single sign-on against the
// harness identity provider.

const sem = (id: string) => `[flt-semantics-identifier="${id}"]`;

test('two users share the catalog but never each other\'s state', async ({ request }) => {
  const adminToken = await ensureAdmin(request);
  await waitForLibrary(request, adminToken);

  // A second account (idempotent across reruns on a reused stack).
  const create = await request.post('/api/v1/users', {
    ...authed(adminToken),
    data: { username: 'merry', password: ADMIN_PASS },
  });
  expect([201, 409]).toContain(create.status());
  const merryLogin = await request.post('/api/v1/auth/login', {
    data: { username: 'merry', password: ADMIN_PASS },
  });
  expect(merryLogin.ok()).toBeTruthy();
  const merryToken = (await merryLogin.json()).token as string;

  // Both see the same shared catalog. Podcast episodes are the one
  // deliberate exception (they scope to each user's own subscriptions,
  // and a parallel spec may have subscribed the admin), so the shared
  // half is everything else.
  const shared = (items: { pid: string; mediaType: string }[]) =>
    items.filter((it) => it.mediaType !== 'podcast');
  const adminItems = shared(
    (await (await request.get('/api/v1/library/items', authed(adminToken))).json()).items,
  );
  const merryItems = shared(
    (await (await request.get('/api/v1/library/items', authed(merryToken))).json()).items,
  );
  expect(merryItems.length).toBe(adminItems.length);
  const [first, second] = [adminItems[0].pid, adminItems[1].pid];

  // Admin stars and rates the first item; merry's view stays zero.
  const star = await request.put(`/api/v1/items/${first}/star`, {
    ...authed(adminToken),
    data: { starred: true },
  });
  expect(star.ok()).toBeTruthy();
  const rate = await request.put(`/api/v1/items/${first}/rating`, {
    ...authed(adminToken),
    data: { rating: 80 },
  });
  expect((await rate.json()).rating).toBe(80);

  const merryState = await (
    await request.get(`/api/v1/items/${first}/play-state`, authed(merryToken))
  ).json();
  expect(merryState.starred).toBe(false);
  expect(merryState.rating ?? null).toBeNull();

  // Merry stars the second item; the starred lists diverge.
  await request.put(`/api/v1/items/${second}/star`, {
    ...authed(merryToken),
    data: { starred: true },
  });
  const adminStarred = (
    await (await request.get('/api/v1/library/browse?list=starred', authed(adminToken))).json()
  ).items.map((it: { pid: string }) => it.pid);
  const merryStarred = (
    await (await request.get('/api/v1/library/browse?list=starred', authed(merryToken))).json()
  ).items.map((it: { pid: string }) => it.pid);
  expect(adminStarred).toContain(first);
  expect(adminStarred).not.toContain(second);
  expect(merryStarred).toContain(second);
  expect(merryStarred).not.toContain(first);

  // Merry is no administrator: the user admin surface refuses.
  const forbidden = await request.get('/api/v1/users', authed(merryToken));
  expect(forbidden.status()).toBe(403);
});

test('revoking a session kills the device immediately', async ({ request }) => {
  const adminToken = await ensureAdmin(request);

  // A named device logs in.
  const phone = await request.post('/api/v1/auth/login', {
    data: { username: 'admin', password: ADMIN_PASS, deviceName: 'Playwright Phone' },
  });
  expect(phone.ok()).toBeTruthy();
  const phoneToken = (await phone.json()).token as string;

  // It works, and it shows up in the device list.
  const probe = await request.get('/api/v1/auth/session', authed(phoneToken));
  expect((await probe.json()).authenticated).toBe(true);
  const sessions = (
    await (await request.get('/api/v1/auth/sessions', authed(adminToken))).json()
  ).sessions as Array<{ id: string; deviceName?: string; kind: string }>;
  const entry = sessions.find((s) => s.deviceName === 'Playwright Phone');
  expect(entry).toBeTruthy();
  expect(entry!.kind).toBe('device');

  // Revoke it from the other session; the device's next request fails.
  const revoke = await request.delete(`/api/v1/auth/sessions/${entry!.id}`, authed(adminToken));
  expect(revoke.status()).toBe(204);
  const dead = await request.get('/api/v1/library/items', authed(phoneToken));
  expect(dead.status()).toBe(401);
});

test('single sign-on logs in through the identity provider', async ({ page, request }) => {
  // Local accounts must exist first so the SSO account lands on a
  // bootstrapped server (and the setup door stays closed).
  await ensureAdmin(request);

  await page.goto('/');

  // The login screen offers the configured provider.
  const sso = page.locator(sem('oidc-login-testidp'));
  await sso.waitFor({ timeout: 30_000 });
  await sso.click();

  // The browser lands on the identity provider's own login form.
  await page.waitForURL(/127\.0\.0\.1:4419\/authorize/, { timeout: 30_000 });
  await page.locator('input[name="idp_username"]').fill('gandalf');
  await page.locator('input[name="idp_password"]').fill('mithrandir-e2e');
  await page.locator('button[type="submit"]').click();

  // The provider bounces through the server callback and the SPA loads
  // signed in as the provisioned account.
  await page.waitForURL(/localhost:4420/, { timeout: 30_000 });
  await page.locator(sem('settings-open')).waitFor({ timeout: 30_000 });

  const session = await (await page.request.get('/api/v1/auth/session')).json();
  expect(session.authenticated).toBe(true);
  expect(session.user.username).toBe('gandalf');
  // No admin group is configured for the harness IdP, so the account is
  // a plain user and the admin surface refuses it.
  expect(session.user.roles).not.toContain('admin');
  const forbidden = await page.request.get('/api/v1/users');
  expect(forbidden.status()).toBe(403);
});

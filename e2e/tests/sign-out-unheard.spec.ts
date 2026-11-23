import type { Response } from '@playwright/test';
import { test, expect, SpecPage } from './fixtures';
import type { components } from './api-types';
import { T } from './driver/budgets';

// A browser's session is the server's cookie, which the page cannot
// remove. A sign-out pressed while the server is out of reach still signs
// the browser out: the revoke is owed, naming the session the cookie held,
// and the next page load delivers it before it reads the session. A
// session made since is left alone.

type SessionInfo = components['schemas']['SessionInfo'];

/// Where the page keeps which session its cookie holds, for every tab.
const heldKey = 'waxdeck.auth.heldSession';

/// The id of the session the page holds, from the answer that says so,
/// once the page has kept it where its sign-out reads it: what that
/// sign-out names. The answer is waited for from before [open] starts.
async function ownSession(page: SpecPage, open: () => Promise<void>): Promise<string> {
  const answer = page.waitForResponse(
    (r) => r.request().method() === 'GET' && new URL(r.url()).pathname.endsWith('/auth/session'),
  );
  await open();
  const read = (await (await answer).json()) as SessionInfo;
  expect(read.sessionId, 'the page read its own session').toBeDefined();
  const id = read.sessionId!;
  await expect
    .poll(() => page.evaluate((key) => localStorage.getItem(key), heldKey), { timeout: T.assert })
    .toBe(id);
  return id;
}

/// Everything [page] hears until `stop`, in order.
function hear(page: SpecPage) {
  const heard: { method: string; path: string; status: number }[] = [];
  const record = (r: Response) =>
    heard.push({
      method: r.request().method(),
      path: new URL(r.url()).pathname,
      status: r.status(),
    });
  page.on('response', record);
  return {
    heard,
    stop: () => page.off('response', record),
    first: (method: string, path: string) =>
      heard.findIndex((r) => r.method === method && r.path.endsWith(path)),
    last: (method: string, path: string) =>
      heard.findLastIndex((r) => r.method === method && r.path.endsWith(path)),
  };
}

test('a sign-out the server never heard still holds after a reload', async ({ app, page }) => {
  const network = await app.network();
  const ours = await ownSession(page, () => app.nav.enter('home'));

  // Off the network, so the sign-out's request fails on its way.
  await network.off();
  await app.auth.signOut();
  await app.auth.expectAtLogin();
  // The server never heard it. The test's own hand holds the token the
  // browser's cookie carries, and the session still answers for it.
  expect((await app.api.get('/auth/session')).authenticated).toBe(true);

  const traffic = hear(page);
  await network.on();
  await app.nav.reload(app.auth.submit());
  traffic.stop();

  // The revoke named the session, with the proof a session read handed
  // the fresh page, and the read the page went by came after it.
  const log = JSON.stringify(traffic.heard);
  const revoked = traffic.first('DELETE', `/auth/sessions/${ours}`);
  expect(revoked, log).toBeGreaterThanOrEqual(0);
  expect(traffic.heard[revoked].status).toBe(204);
  expect(traffic.last('GET', '/auth/session'), log).toBeGreaterThan(revoked);

  // The server ended the session itself, and nobody is signed in.
  expect((await app.api.get('/auth/session')).authenticated).toBe(false);
  expect((await app.auth.session()).authenticated).toBe(false);
  await expect(app.auth.submit()).toBeVisible();
  await expect(app.shell.region()).toHaveCount(0);
});

test('a sign-out the server never heard leaves a session signed in since on the same browser, and ends the one owed', async ({
  app,
  page,
}) => {
  const network = await app.network();
  const ours = await ownSession(page, () => app.nav.enter('home'));

  await network.off();
  await app.auth.signOut();
  await app.auth.expectAtLogin();

  // The account signs in again on this browser, as another tab would,
  // before the page is back: the cookie names a session of its own now.
  const again = await app.auth.browserApi().post('/auth/login', {
    data: { username: app.account.username, password: app.account.password },
  });
  expect(again.user.username).toBe(app.account.username);

  const traffic = hear(page);
  await network.on();
  await app.nav.reload();
  traffic.stop();

  // The session owed is ended by id, an older session of the account now;
  // the one signed in since is the one the browser holds, and the page
  // shows it.
  const log = JSON.stringify(traffic.heard);
  expect(traffic.first('POST', '/auth/logout'), log).toBe(-1);
  const revoked = traffic.first('DELETE', `/auth/sessions/${ours}`);
  expect(revoked, log).toBeGreaterThanOrEqual(0);
  expect(traffic.heard[revoked].status).toBe(204);
  expect((await app.api.get('/auth/session')).authenticated).toBe(false);
  const held = await app.auth.session();
  expect(held.authenticated).toBe(true);
  expect(held.user?.username).toBe(app.account.username);
  await expect(app.shell.region()).toBeVisible();
});

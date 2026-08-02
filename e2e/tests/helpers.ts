import { expect, APIRequestContext, Locator, Page } from '@playwright/test';
import { SemanticsIds, sem } from './semantics-ids';

// Type into a flutter text field and verify every keystroke landed.
// Clicking focuses the DOM input, but flutter attaches its editing
// session asynchronously and quietly drops keys typed in the gap, so
// the only reliable protocol is: select-all, type, check the value,
// and redo the whole round if anything went missing.
export async function typeInto(page: Page, field: Locator, text: string) {
  // Bounded: an absent field must fail here with a page snapshot, not
  // silently consume the whole test budget.
  await field.waitFor({ timeout: 30_000 });
  // The locator may be the input itself (role-based) or a semantics
  // container wrapping it (identifier-based).
  const inner = field.locator('input, textarea');
  const input = (await inner.count()) > 0 ? inner.first() : field;
  await input.click();
  await expect(input).toBeFocused();
  await expect(async () => {
    await page.keyboard.press('ControlOrMeta+a');
    await page.keyboard.type(text);
    await expect(input).toHaveValue(text, { timeout: 1_000 });
  }).toPass({ timeout: 20_000 });
}

// The stack starts with no accounts. Every spec funnels through
// ensureAdmin: the first caller bootstraps the administrator, later
// callers (and reruns against a reused stack) fall through to a normal
// login. Specs may race; both outcomes converge on the same account.
export const ADMIN_USER = 'admin';
export const ADMIN_PASS = 'wax-e2e-pass';

export async function ensureAdmin(request: APIRequestContext): Promise<string> {
  const boot = await request.post('/api/v1/auth/bootstrap', {
    data: { username: ADMIN_USER, password: ADMIN_PASS },
  });
  if (boot.ok()) {
    return (await boot.json()).token as string;
  }
  expect(boot.status(), 'bootstrap either succeeds or reports the door closed').toBe(409);
  const login = await request.post('/api/v1/auth/login', {
    data: { username: ADMIN_USER, password: ADMIN_PASS },
  });
  expect(login.ok()).toBeTruthy();
  return (await login.json()).token as string;
}

export function authed(token: string) {
  return { headers: { Authorization: `Bearer ${token}` } };
}

// Drives the login form as the shared administrator and waits for
// whatever the caller treats as proof the app is past it (specs settle
// on different post-login markers). New specs use this; the older ones
// still carry their own inlined copies from before it existed.
export async function loginAsAdmin(page: Page, settledOn: Locator) {
  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, ADMIN_USER);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), ADMIN_PASS);
  await page.getByRole('button', { name: 'Log in' }).click();
  await settledOn.waitFor({ timeout: 30_000 });
}

// Click a canvas-rendered control and wait for what it opens, as one
// retried unit: flutter web can swallow a click while its handlers are
// still attaching (the click cousin of the keystroke gap typeInto
// retries around), and a swallowed navigation click means the next
// screen never appears at all.
export async function clickThrough(trigger: Locator, appears: Locator) {
  await expect(async () => {
    // A prior attempt's click may have landed with the destination
    // just slow, and navigating away removes the trigger; so the click
    // is skipped once the destination shows and is best-effort
    // otherwise (a swallowed click retries, a vanished trigger means
    // the navigation is already underway).
    if (!(await appears.isVisible())) {
      // Forced, like the a11y suite's canvas clicks: semantics nodes
      // over an animating canvas (a live seek bar) never satisfy the
      // stability heuristics, so an actionability wait just times out.
      await trigger.click({ timeout: 2_000, force: true }).catch(() => {});
    }
    await appears.waitFor({ timeout: 5_000 });
  }).toPass({ timeout: 30_000 });
}

// Open a menu and choose a row from it, as one retried unit.
//
// `clickThrough` is wrong for a menu and this is the difference: it
// re-clicks its trigger whenever the destination is not showing, and on
// a retry that click lands on the modal barrier and closes the menu the
// previous attempt opened. So the trigger is clicked only when the row
// is not already visible, and the whole open-and-choose repeats from a
// closed menu when a click is swallowed.
//
// `settled` is what proves the choice took: a sheet the row opens, or -
// by default - the menu going away, which is what a value picker does.
// It is also checked before anything else, for the choice that took and
// then outran its own wait: the menu is gone by the next attempt, so
// every one after it re-opens the menu over the surface the choice
// already reached and none of them ever look at what they were waiting
// for - a helper that fails its whole budget after having succeeded.
// That check is why `settled` has to be something only the chosen row
// can produce: one already on screen when this is called reads as a
// choice that already happened, and the menu is never opened at all.
export async function chooseFromMenu(
  trigger: Locator,
  item: Locator,
  settled?: Locator,
) {
  await expect(async () => {
    if (settled && (await settled.isVisible())) return;
    if (!(await item.isVisible())) {
      await trigger.click({ timeout: 2_000, force: true }).catch(() => {});
      await item.waitFor({ timeout: 5_000 });
    }
    // The menu animates into place - and near a screen edge it is
    // repositioned as it grows - while a forced click dispatches at
    // whatever rect the semantics overlay held a frame earlier. That
    // one-frame disagreement is how choosing "Off" from a menu at the
    // bottom of the screen landed on the row beneath it and silently
    // stored the wrong value. Two matching reads a beat apart is the
    // menu at rest; until then the click would be a coin toss.
    await expect(async () => {
      const before = await item.boundingBox();
      await new Promise((resolve) => setTimeout(resolve, 120));
      const after = await item.boundingBox();
      expect(before).toBeTruthy();
      expect(after).toEqual(before);
    }).toPass({ timeout: 4_000 });
    await item.click({ force: true });
    if (settled) {
      await settled.waitFor({ timeout: 5_000 });
    } else {
      await expect(item).toBeHidden({ timeout: 5_000 });
    }
  }).toPass({ timeout: 45_000 });
}

// The startup scan is asynchronous; poll until the fixture library shows up.
export async function waitForLibrary(request: APIRequestContext, token: string) {
  await expect
    .poll(
      async () => {
        const resp = await request.get('/api/v1/library/items', authed(token));
        if (!resp.ok()) return 0;
        return ((await resp.json()).items ?? []).length;
      },
      { timeout: 60_000, message: 'startup scan should populate the library' },
    )
    .toBeGreaterThanOrEqual(4);
}

// A loopback JSON sink for notification-delivery scenarios: captures
// every POSTed body so a spec can assert the server actually delivered.
// The e2e server is a host process, so 127.0.0.1 is reachable, and
// server-scope targets are deliberately unguarded, so no stack or
// environment change is needed.
export async function startJsonSink(): Promise<{
  url: string;
  received: () => unknown[];
  close: () => Promise<void>;
}> {
  const { createServer } = await import('node:http');
  const received: unknown[] = [];
  const server = createServer((req, res) => {
    const chunks: Buffer[] = [];
    req.on('data', (chunk) => chunks.push(chunk));
    req.on('end', () => {
      try {
        received.push(JSON.parse(Buffer.concat(chunks).toString('utf8')));
      } catch {
        received.push(Buffer.concat(chunks).toString('utf8'));
      }
      res.writeHead(200).end();
    });
  });
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  if (address === null || typeof address === 'string') {
    throw new Error('sink did not bind a port');
  }
  return {
    url: `http://127.0.0.1:${address.port}`,
    received: () => [...received],
    close: () => new Promise((resolve) => server.close(() => resolve())),
  };
}

// Playlists is one of the ways into music now, so the sidebar lists it
// under the Music hub in a section that stays closed until it holds
// where you are. Every spec that reaches playlists from the chrome opens
// it first; clickThrough makes that idempotent, so calling this twice
// costs nothing.
export async function openMusicSection(page: Page) {
  await clickThrough(
    page.locator(sem(SemanticsIds.navDisclose('music'))),
    page.locator(sem(SemanticsIds.navDestination('playlists'))),
  );
}

// The tracks index: every item in the library, each row addressed by its
// pid. Home is shelves now, and a shelf is a dozen cards drawn from a
// list rather than an enumeration, so a spec that wants one known track
// comes here - which is what the deleted library grid was doing for it.
export async function itemRow(page: Page, pid: string): Promise<Locator> {
  const row = page.locator(sem(SemanticsIds.item(pid)));
  if (await row.count()) return row;
  // The chrome first. Several callers reach here straight off a login
  // click, and a goto issued while that request is in flight aborts it -
  // the app never signs in and the row never arrives, which reads as a
  // missing track rather than as a cancelled login.
  await page
    .locator(sem(SemanticsIds.navDestination('music')))
    .waitFor({ timeout: 30_000 });
  await page.goto('/#/music/tracks');
  await row.waitFor({ timeout: 30_000 });
  return row;
}

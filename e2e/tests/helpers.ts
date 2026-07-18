import { expect, APIRequestContext, Locator, Page } from '@playwright/test';

// Type into a flutter text field and verify every keystroke landed.
// Clicking focuses the DOM input, but flutter attaches its editing
// session asynchronously and quietly drops keys typed in the gap, so
// the only reliable protocol is: select-all, type, check the value,
// and redo the whole round if anything went missing.
export async function typeInto(page: Page, field: Locator, text: string) {
  await field.waitFor();
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

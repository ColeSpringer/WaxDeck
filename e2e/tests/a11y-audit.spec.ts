import { test, expect } from './fixtures';
import { ADMIN_PASS, ADMIN_USER, ensureAdmin, typeInto, waitForLibrary } from './helpers';

// The screen-reader groundwork audit: complete login, browse, and play
// using only the accessibility tree (roles and accessible names), never
// the test-only semantics identifiers. This is the tree NVDA and
// VoiceOver consume; passing here means the journey is exposed, and the
// remaining verdict is how real screen readers narrate it on their own
// platforms.

test('login, browse, and play are completable through roles and names', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);

  await page.goto('/');

  // Login: labeled text fields and a named button.
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, ADMIN_USER);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), ADMIN_PASS);
  await page.getByRole('button', { name: 'Log in' }).click();

  // Browse: the item is reachable by its accessible text, not a
  // test hook.
  const card = page.getByText('Alpha Song').first();
  await card.waitFor({ timeout: 30_000 });
  await card.click();

  // Player: the controls expose names and state. The star announces
  // its action (Star/Unstar) and the transport its action
  // (Play/Pause), flipping as state changes.
  const toggle = page.getByRole('button', { name: /^(Play|Pause)$/ });
  await toggle.waitFor({ timeout: 30_000 });
  await expect(
    page.getByRole('button', { name: /^(Star|Unstar)$/ }),
  ).toBeVisible();

  // State changes surface in accessible names: activating the star
  // renames it. (The transport also carries a stateful Play/Pause name,
  // asserted above; its flip cannot be pinned against the two-second
  // fixture, which completes before any assertion lands.) Semantics
  // nodes over canvas fail Playwright's stability heuristics, so the
  // click is forced; and because a forced click uses coordinates that
  // an animating player can shift under it, each activation retries as
  // a unit until the name flips. A control whose activation were
  // genuinely broken would fail every retry, so the pinned property
  // survives.
  await expect(async () => {
    await page
      .getByRole('button', { name: 'Star', exact: true })
      .click({ force: true });
    await page
      .getByRole('button', { name: 'Unstar', exact: true })
      .waitFor({ timeout: 3_000 });
  }).toPass({ timeout: 20_000 });
  await expect(async () => {
    await page
      .getByRole('button', { name: 'Unstar', exact: true })
      .click({ force: true });
    await page
      .getByRole('button', { name: 'Star', exact: true })
      .waitFor({ timeout: 3_000 });
  }).toPass({ timeout: 20_000 });
});

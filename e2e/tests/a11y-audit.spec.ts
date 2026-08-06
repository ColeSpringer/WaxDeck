import { legacyTest as test, expect } from './fixtures';
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

  // The shell puts its navigation before the content, so the first
  // thing in the page's reading order has to be the way past it. This
  // is the whole claim of a skip link, and it is only true if the link
  // really is first: assert it as the document's first button rather
  // than merely present somewhere.
  const skip = page.getByRole('button', { name: 'Skip to content' });
  await skip.waitFor({ timeout: 30_000 });
  await expect(page.getByRole('button').first()).toHaveAccessibleName(
    'Skip to content',
  );

  // The navigation is the only way around the app now, so it has to be
  // operable from a keyboard. This fails the moment the chrome stops
  // declaring itself focusable: web turns that flag into a tabindex, and
  // without one `focus()` is a silent no-op and the key goes nowhere.
  // Space rather than Enter, which is the key a role=button takes here.
  const settings = page.getByRole('button', { name: 'Settings', exact: true });
  await settings.waitFor({ timeout: 30_000 });
  await settings.focus();
  await page.keyboard.press(' ');
  // The destination itself is the assertion: settings is a long scroller
  // whose rows build lazily, so any control on it is a race, and what is
  // under test here is that a key press on a focused destination
  // navigates at all.
  await expect(page).toHaveURL(/settings/, { timeout: 15_000 });
  await page.goBack();

  // Browse: through the chrome by accessible name, to the listing that
  // enumerates the library, and the item is reachable by its own text
  // rather than by a test hook. Home is shelves, which are a dozen cards
  // drawn off a discovery list - a fine landing surface and the wrong
  // place to look for one named track.
  const music = page.getByRole('button', { name: 'Music', exact: true });
  await music.waitFor({ timeout: 30_000 });
  await music.click();
  const tracks = page.getByRole('button', { name: /^Tracks/ }).first();
  await tracks.waitFor({ timeout: 30_000 });
  await tracks.click();

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

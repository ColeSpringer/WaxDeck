import { test, expect } from './fixtures';
import { T } from './driver';

// Prose rebuilt across the browser-menu switch. The app turns the
// browser's own context menu off while the pointer is over anything with
// a menu of its own, prose included, and a selection area builds a
// different subtree while that menu is on. Until Flutter 3.50 an area
// rebuilt across the switch lost its selection state and threw on the
// next one, blanking what it was in. A VM test cannot see any of this:
// the switch exists only in a browser.
const HELP = 'Off: a handed-over queue waits to be tapped';

test('prose rebuilt while the browser menu switches neither throws nor blanks', async ({
  app,
  page,
}) => {
  const problems: string[] = [];
  page.on('console', (message) => {
    if (message.type() === 'error') problems.push(message.text().slice(0, 300));
  });
  page.on('pageerror', (error) => problems.push(`pageerror: ${error.message.slice(0, 300)}`));

  await app.nav.enter('settings');
  await app.settings.findAndOpen('without asking', 'autoplay', 'autoplay');
  const toggle = app.settings.setting('autoplay');
  const help = app.settings.text(HELP);
  await expect(help).toBeVisible();

  // The setting changed elsewhere rebuilds the row the prose is in,
  // wherever the pointer rests: the prefs event reaches this page. PUT
  // replaces the whole document, so the rest of it is carried over.
  const rebuild = async () => {
    const before = await toggle.getAttribute('aria-checked');
    const prefs = await app.api.get('/users/me/prefs');
    await app.api.put('/users/me/prefs', {
      data: { ...prefs, autoplay: !(prefs.autoplay ?? true) },
    });
    await expect(toggle).not.toHaveAttribute('aria-checked', before ?? '', { timeout: T.assert });
  };
  const menuHeld = (held: boolean) =>
    expect.poll(() => app.shell.browserMenuHeld(), { timeout: T.step }).toBe(held);

  for (let round = 0; round < 3; round++) {
    await app.shell.pointAt(help);
    await menuHeld(true);
    await rebuild();
    await app.shell.pointAway();
    await menuHeld(false);
    await rebuild();
  }
  // And a switch each way after the last rebuild.
  await app.shell.pointAt(help);
  await menuHeld(true);
  await app.shell.pointAway();
  await menuHeld(false);

  await expect(help, 'the prose is still drawn').toBeVisible();
  expect(problems, 'nothing threw').toEqual([]);
});

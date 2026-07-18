import { test, expect, APIRequestContext } from '@playwright/test';

// The first-party web UI journey: log in through the real login form,
// find a scanned fixture track in the library grid, open the player,
// and observe the stream actually being fetched through the media
// proxy. The flutter app enables semantics at startup; widgets carry
// flt-semantics-identifier attributes for exactly this suite.

const sem = (id: string) => `[flt-semantics-identifier="${id}"]`;

// Wait for the startup scan through a separate cookie jar, so the page
// context still sees the login screen.
async function waitForAlpha(request: APIRequestContext): Promise<string> {
  const login = await request.post('/api/v1/auth/login', {
    data: { username: 'admin', password: 'e2e' },
  });
  const token = (await login.json()).token as string;
  let pid = '';
  await expect
    .poll(
      async () => {
        const resp = await request.get('/api/v1/library/search?q=Alpha', {
          headers: { Authorization: `Bearer ${token}` },
        });
        if (!resp.ok()) return false;
        const tracks = (await resp.json()).tracks ?? [];
        if (tracks.length === 0) return false;
        pid = tracks[0].pid;
        return true;
      },
      { timeout: 60_000, message: 'startup scan should index Alpha Song' },
    )
    .toBeTruthy();
  return pid;
}

test('login, browse the grid, and play a track', async ({ page, request }) => {
  const pid = await waitForAlpha(request);

  await page.goto('/');

  // The login form is the first thing an unauthenticated visitor sees.
  // Click-and-type drives flutter's real text-editing path; a direct
  // value fill can leave the framework-side controller empty.
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await username.click();
  await page.keyboard.type('admin');
  await page.getByRole('textbox', { name: 'Password' }).click();
  await page.keyboard.type('hunter2');
  await page.getByRole('button', { name: 'Log in' }).click();

  // The library grid renders the scanned fixture album.
  const card = page.locator(sem(`item-${pid}`));
  await card.waitFor({ timeout: 30_000 });

  // Opening the item starts playback through the single-origin media
  // proxy. The rendered duration proves the stream's metadata decoded.
  await card.click();
  await page.locator(sem('player-toggle')).waitFor({ timeout: 30_000 });
  await expect(page.getByText(/0:0[2-9]/).first()).toBeVisible({ timeout: 30_000 });

  // The fixture is two seconds long; when it completes, the client
  // reports its listen session and checkpoints state. Observing the
  // server mark the item played closes the whole loop: UI login, grid,
  // stream fetch, engine completion, listen ingest. page.request rides
  // the session cookie the login form just established.
  await expect
    .poll(
      async () => {
        const resp = await page.request.get(`/api/v1/items/${pid}/play-state`);
        if (!resp.ok()) return false;
        const state = await resp.json();
        return state.played === true && state.playCount >= 1;
      },
      { timeout: 45_000, message: 'completed playback should be accounted as a play' },
    )
    .toBeTruthy();
});

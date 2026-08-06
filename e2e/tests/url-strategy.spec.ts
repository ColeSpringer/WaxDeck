import { legacyTest as test, expect } from './fixtures';
import {
  ADMIN_PASS,
  ADMIN_USER,
  ensureAdmin,
  typeInto,
  waitForLibrary,
} from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The path-URL flip. Locations are paths the server answers for, so a
// typed URL, a shared link, and a reload all reach the screen they name;
// and the `/#/...` links minted before the flip - months of them, in
// bookmarks and in share messages - are rewritten by the shim in
// index.html before the engine boots, so they land rather than break.

test('the server answers a deep path with the app shell', async ({ request }) => {
  // The whole requirement path URLs stand on: a location the router owns
  // and the server has never heard of is a document navigation, and the
  // fallback hands it the shell for the client to route.
  const deep = await request.get('/music/artists/ar-01JQZX0000000000000000000/tracks', {
    headers: { 'Sec-Fetch-Mode': 'navigate' },
  });
  expect(deep.ok(), 'a deep app location is served the shell').toBeTruthy();
  expect(deep.headers()['content-type']).toContain('text/html');

  // And the fallback stays a fallback for navigations only: a subresource
  // miss under the same path must 404 rather than be handed HTML, which
  // is what the engine's font probes and its wasm loader depend on.
  const asset = await request.get('/music/artists/main.dart.wasm', {
    headers: { 'Sec-Fetch-Mode': 'no-cors' },
  });
  expect(asset.status(), 'a subresource miss is a 404, not the shell').toBe(404);
});

test('an old hash link lands on the location it names', async ({ page, request }) => {
  const token = await ensureAdmin(request);
  // The artists index has to have artists in it: without this a cold
  // stack fails here as "the shim is broken" when the scan simply has
  // not finished. Every sibling spec that asserts on a bucket waits.
  await waitForLibrary(request, token);

  // A bookmark from before the flip, opened cold and signed out. The
  // fragment never reaches the server, so the shim is the only thing that
  // can see it: it rewrites the path before the engine boots, and the
  // signed-out redirect then carries the location through the login form.
  await page.goto('/#/music/artists');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  // Encoding-tolerant on the separator alone: what this asserts is that
  // the fragment is gone and the location it carried survived into the
  // query the login form reads.
  await expect(page, 'the hash is rewritten into the path').toHaveURL(
    /\/login\?from=(%2F|\/)music(%2F|\/)artists$/,
  );

  await typeInto(page, username, ADMIN_USER);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), ADMIN_PASS);
  await page.getByRole('button', { name: 'Log in' }).click();

  await page.locator(sem(SemanticsIds.indexBucket(0))).waitFor({ timeout: 30_000 });
  await expect(page, 'and the deep link survives the login').toHaveURL(/\/music\/artists$/);

  // A query sitting before the fragment is part of the link, not
  // scenery: a share message picks up tracking parameters, and the
  // rewrite has to be a change of form rather than of content. Nothing
  // in the app reads one at boot today, which is exactly why a shim
  // that eats them would be found late.
  await page.goto('/?ref=share#/music/artists');
  await page.locator(sem(SemanticsIds.indexBucket(0))).waitFor({ timeout: 30_000 });
  await expect(page, 'the query rides across the rewrite').toHaveURL(
    /\/music\/artists\?ref=share$/,
  );
});

test('a fragment that names another origin is refused', async ({ page, request }) => {
  await ensureAdmin(request);

  // `#/` is not enough of a check on its own: a second slash makes the
  // rest protocol-relative, and the shim would hand a self-hosted origin
  // a way to bounce its own visitors off-site. The backslash spelling is
  // the same attack - the URL parser folds it - and the tab is stripped
  // before resolution, which rebuilds either. None of them may leave.
  await page.goto('/');
  const origin = new URL(page.url()).origin;

  for (const hostile of ['#//example.invalid/', '#/\\example.invalid/', '#/\t/example.invalid/']) {
    await page.goto('/' + hostile);
    // The login form proves the app booted rather than the page sitting
    // on a failed cross-origin fetch, and the origin proves where.
    await page.getByRole('textbox', { name: 'Username' }).waitFor({ timeout: 30_000 });
    expect(new URL(page.url()).origin, `${hostile} must not leave the origin`).toBe(origin);
  }

  // And the refusal is a refusal, not a silent rewrite to something
  // else: an unusable fragment leaves the path alone, and the app lands
  // where a bare visit would.
  await expect(page).toHaveURL(/\/login$/);
});

test('a hash pasted into a running tab still navigates', async ({ page, request }) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  await page.goto('/');
  const username = page.getByRole('textbox', { name: 'Username' });
  await username.waitFor({ timeout: 30_000 });
  await typeInto(page, username, ADMIN_USER);
  await typeInto(page, page.getByRole('textbox', { name: 'Password' }), ADMIN_PASS);
  await page.getByRole('button', { name: 'Log in' }).click();
  await page.locator(sem(SemanticsIds.navDestination('music'))).waitFor({ timeout: 30_000 });

  // Setting only the fragment is a same-document navigation: no request,
  // no reboot, and under the path strategy the engine never sees it. The
  // shim's hashchange listener reloads onto the rewritten path, which is
  // the difference between a shared link working and doing nothing at
  // all when the app is already open.
  await page.evaluate(() => {
    window.location.hash = '#/music/artists';
  });
  await page.locator(sem(SemanticsIds.indexBucket(0))).waitFor({ timeout: 30_000 });
  await expect(page).toHaveURL(/\/music\/artists$/);
});

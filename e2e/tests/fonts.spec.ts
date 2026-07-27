import { test, expect } from './fixtures';
import { authed, ensureAdmin, loginAsAdmin, waitForLibrary, openMusicSection } from './helpers';
import { SemanticsIds, sem } from './semantics-ids';

// The owned-type contract, on the wire: WaxDeck serves every byte of its
// UI from its own origin, because LAN-only and air-gapped instances
// cannot reach a CDN. Fonts are where that quietly breaks (Flutter web's
// default is to fetch Roboto and Noto fallbacks from Google), so this
// spec pins both halves: the deferred CJK face downloads from this
// origin exactly when CJK metadata appears, and the whole journey makes
// no request anywhere else.

const CJK_NAME = '漢字テスト 한글';

test('CJK metadata pulls its face from this origin and nothing leaves it', async ({
  page,
  request,
}) => {
  const token = await ensureAdmin(request);
  await waitForLibrary(request, token);
  const created = await request.post('/api/v1/playlists', {
    ...authed(token),
    data: { name: CJK_NAME, kind: 'static' },
  });
  expect(created.ok()).toBeTruthy();
  const pid = (await created.json()).pid as string;

  const requested: string[] = [];
  page.on('request', (r) => requested.push(r.url()));
  try {
    await loginAsAdmin(page, page.locator(sem(SemanticsIds.navDestination('music'))));
    await openMusicSection(page);
    await page.locator(sem(SemanticsIds.navDestination('playlists'))).click();
    await page.getByText(CJK_NAME).first().waitFor({ timeout: 30_000 });

    // The playlist listing carries a CJK name, so the deferred face must
    // come down, and from this server.
    await expect
      .poll(
        () => requested.some((u) => u.endsWith('assets/fonts/NotoSansCJK.otf')),
        { timeout: 15_000, message: 'the CJK face should be fetched on demand' },
      )
      .toBeTruthy();

    // Fetched is not installed: a face the engine rejected (or one
    // registered under the wrong family) looks identical on the wire
    // and still renders tofu. The app publishes families only after
    // FontLoader.load succeeded, meaning the engine parsed the bytes.
    await expect
      .poll(
        () => page.evaluate('window.__waxFontsLoaded ?? []'),
        { timeout: 10_000, message: 'the CJK face should install, not just download' },
      )
      .toContain('NotoSansCJK');

    // Nothing in the journey so far (engine, fonts, artwork, API) may
    // have left the origin: this is the air-gap promise as an assertion.
    const origin = new URL(page.url()).origin;
    const offOrigin = requested.filter(
      (u) => !u.startsWith(origin) && !u.startsWith(`blob:${origin}`),
    );
    expect(offOrigin, 'every request stays on the WaxDeck origin').toEqual([]);
  } finally {
    await request.delete(`/api/v1/playlists/${pid}`, authed(token));
  }
});

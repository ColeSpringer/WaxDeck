import { test, expect } from './fixtures';

// The owned-type contract, on the wire: WaxDeck serves every byte of its
// UI from its own origin, because LAN-only and air-gapped instances
// cannot reach a CDN. Fonts are where that quietly breaks (Flutter web's
// default is to fetch Roboto and Noto fallbacks from Google), so this
// spec pins both halves: the deferred CJK face downloads from this
// origin exactly when CJK metadata appears, and the whole journey makes
// no request anywhere else.

const CJK_NAME = '漢字テスト 한글';

test('CJK metadata pulls its face from this origin and nothing leaves it', async ({
  app,
  page,
}) => {
  // Named rather than counted, and reused rather than recreated: this
  // account is keyed on the test's title, so a stack that has been
  // reused already has last run's playlist on it. Nothing is deleted
  // afterwards for the same reason - there is one, and it is this
  // test's.
  const pid = await app.seed.playlistNamed(CJK_NAME);

  const requested: string[] = [];
  page.on('request', (r) => requested.push(r.url()));

  // Attached before the first navigation, so the engine's own boot -
  // wasm, canvas kit, the base faces - is inside the audit rather than
  // beside it.
  await app.nav.enter('playlists');
  await expect(app.playlists.row(pid)).toBeVisible();

  // The playlist listing carries a CJK name, so the deferred face must
  // come down, and from this server.
  await expect
    .poll(() => requested.some((u) => u.endsWith('assets/fonts/NotoSansCJK.otf')), {
      message: 'the CJK face should be fetched on demand',
    })
    .toBeTruthy();

  // Fetched is not installed: a face the engine rejected (or one
  // registered under the wrong family) looks identical on the wire
  // and still renders tofu. The app publishes families only after
  // FontLoader.load succeeded, meaning the engine parsed the bytes.
  await expect
    .poll(() => page.evaluate('window.__waxFontsLoaded ?? []'), {
      message: 'the CJK face should install, not just download',
    })
    .toContain('NotoSansCJK');

  // Nothing in the journey so far (engine, fonts, artwork, API) may
  // have left the origin: this is the air-gap promise as an assertion.
  const origin = new URL(app.nav.location()).origin;
  const offOrigin = requested.filter(
    (u) => !u.startsWith(origin) && !u.startsWith(`blob:${origin}`),
  );
  expect(offOrigin, 'every request stays on the WaxDeck origin').toEqual([]);
});

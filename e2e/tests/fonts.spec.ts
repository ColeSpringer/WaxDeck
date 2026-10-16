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
  const answered: { url: string; status: number }[] = [];
  page.on('response', (r) => answered.push({ url: r.url(), status: r.status() }));

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

  // The engine's own default face, which both renderers download from
  // the fallback base as they start, before laying out any text. The
  // build ships it at the engine's path; a Flutter upgrade that moves
  // the path turns this into a 404, and `make fonts` names the new one.
  const defaultFace = answered.filter((r) => r.url.includes('/wax-font-fallback/roboto/'));
  expect(
    defaultFace.map((r) => r.status),
    "the engine's default face is served by this origin",
  ).toEqual(expect.arrayContaining([200]));
  expect(
    defaultFace.filter((r) => r.status !== 200),
    "no request for the engine's default face goes unanswered",
  ).toEqual([]);

  // Nothing in the journey so far (engine, fonts, artwork, API) may
  // have left the origin: this is the air-gap promise as an assertion.
  const origin = new URL(app.nav.location()).origin;
  const offOrigin = requested.filter(
    (u) => !u.startsWith(origin) && !u.startsWith(`blob:${origin}`),
  );
  expect(offOrigin, 'every request stays on the WaxDeck origin').toEqual([]);
});

// The face above is the one the wasm build asks for, the only build
// Chromium runs. A browser without WasmGC is handed the JavaScript build
// and its CanvasKit engine, which names its default face separately, so
// this reads the face every build the bootstrap may hand out names and
// asks this origin for each: an engine upgrade that moves either one
// fails here, not in a browser nobody tests with.
test('every engine build the page may load finds its default face here', async ({ page }) => {
  const bootstrap = await (await page.request.get('flutter_bootstrap.js')).text();
  const builds = [...bootstrap.matchAll(/"main(?:Js|Wasm)Path":"([^"]+)"/g)].map((m) => m[1]);
  expect(builds.length, 'the bootstrap names the builds it may load').toBeGreaterThan(0);
  for (const build of builds) {
    const engine = (await (await page.request.get(build)).body()).toString('latin1');
    const faces = new Set(engine.match(/roboto\/v\d+\/[A-Za-z0-9_-]+\.woff2/g) ?? []);
    expect(faces.size, `${build} names the default face it downloads`).toBeGreaterThan(0);
    for (const face of faces) {
      const answer = await page.request.get(`vendor/wax-font-fallback/${face}`);
      expect(answer.status(), `${build}'s default face ${face} is served by this origin`).toBe(200);
    }
  }
});
